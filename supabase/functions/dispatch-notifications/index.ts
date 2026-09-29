// dispatch-notifications
//
// The worker end of the channel ladder. Called per salon, on a schedule.
//
//   POST { salon_id, limit? }   (service-role only - no customer ever calls this)
//     -> 200 { claimed, sent, failed, escalated }
//
// What it does, in order:
//
//   1. `claim_notification_batch` opens the first rung for anything pending and
//      hands back the rendered body. Claiming is a WRITTEN delivery row, so a
//      crash mid-send leaves "we tried" rather than a message that sends twice.
//   2. Each row goes to its channel's sender.
//   3. `record_send` writes what the provider said.
//   4. `escalate_due_deliveries` promotes anything still unacked past its
//      window (ARCHITECTURE 12.3).
//
// **`sent` is not `delivered`, and is never `acked`.** FCM reports acceptance
// by Google, which is why the ack protocol exists at all - a dispatcher that
// concluded delivery from a 200 would either never escalate or always escalate,
// and the second one spends the salon's money on every single message.
//
// **Nothing here falls back to Crayora's account except by fault** (RULES 7.1.3,
// and that path lives in the OTP functions). A salon whose Message Central
// credentials are missing does not send SMS - it records why, and that is a
// state the console shows rather than a cost Crayora absorbs.

import { admin, alert, json } from '../_shared/runtime.ts';
import { type BatchRow, fcmMessage, type PushBrand } from '../_shared/push_message.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Message Central's per-message prices, in paise (ARCHITECTURE 12.2b).
 *
 * **RCS is deliberately absent.** 12.2b prices push, WhatsApp Utility, SMS and
 * WhatsApp Marketing; it does not price RCS, and an earlier version of this
 * file carried 10 paise for it - a number nobody sourced. This figure is
 * written into `daily_salon_metrics` as the SALON's spend, so inventing it
 * would mean showing an owner a bill we made up. A channel with no confirmed
 * price records nothing until the price comes off a real invoice.
 */
const COST_PAISE: Record<string, number> = { push: 0, whatsapp: 17, sms: 22 };

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  // Service-role only. This function reads every customer's notifications for a
  // salon and can spend that salon's money; it is not a customer-facing
  // endpoint and must never become one.
  const auth = req.headers.get('Authorization') ?? '';
  const secret = Deno.env.get('CRAY_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!secret || auth !== `Bearer ${secret}`) return json(401, { error: 'unauthenticated' });

  let salonId: unknown;
  let limit: unknown;
  try {
    ({ salon_id: salonId, limit } = await req.json());
  } catch {
    return json(400, { error: 'invalid_request' });
  }
  if (typeof salonId !== 'string' || !UUID.test(salonId)) {
    return json(400, { error: 'invalid_request' });
  }

  const db = admin();

  const { data: batch, error: claimError } = await db.rpc('claim_notification_batch', {
    p_salon_id: salonId,
    p_limit: typeof limit === 'number' ? limit : 50,
  });

  if (claimError) {
    await alert('dispatch_claim_failed', { salon_id: salonId });
    return json(500, { error: 'internal' });
  }

  const rows: BatchRow[] = batch ?? [];
  let sent = 0;
  let failed = 0;

  // Once per batch, and only if there is a push in it. A brand we could not
  // read still sends - the message matters more than its colour.
  const brand = rows.some((r) => r.channel === 'push') ? await pushBrand(db, salonId) : null;

  for (const row of rows) {
    const result = await send(db, salonId, row, brand);

    await db.rpc('record_send', {
      p_delivery_id: row.delivery_id,
      p_status: result.ok ? 'sent' : 'failed',
      p_provider_message_id: result.providerMessageId ?? null,
      p_failure_reason: result.reason ?? null,
      // Only a send that happened costs anything. A failure that is billed is a
      // failure the salon pays for twice.
      p_cost_paise: result.ok ? (COST_PAISE[row.channel] ?? 0) : 0,
    });

    if (result.ok) sent++;
    else failed++;

    // FCM said this device is gone. Marking it now means the next message
    // skips push entirely instead of waiting out a window it can never
    // satisfy (ARCHITECTURE 12.3).
    if (result.deadToken && row.token) {
      await db.rpc('mark_token_dead', { p_token: row.token });
    }
  }

  const { data: swept } = await db.rpc('escalate_due_deliveries', { p_salon_id: salonId });

  return json(200, {
    claimed: rows.length,
    sent,
    failed,
    escalated: swept?.escalated ?? 0,
    exhausted: swept?.exhausted ?? 0,
  });
});

type SendResult = {
  ok: boolean;
  providerMessageId?: string;
  reason?: string;
  deadToken?: boolean;
};

/** The salon's name, colour and logo for this batch's pushes (0093). */
async function pushBrand(db: ReturnType<typeof admin>, salonId: string): Promise<PushBrand | null> {
  const { data, error } = await db.rpc('salon_push_brand', { p_salon_id: salonId });
  if (error || !data) return null;
  return { name: data.name ?? null, color: data.color ?? null, logo: data.logo ?? null };
}

async function send(
  db: ReturnType<typeof admin>,
  salonId: string,
  row: BatchRow,
  brand: PushBrand | null,
): Promise<SendResult> {
  if (!row.body) {
    // No template for this key, locale and channel. Recorded rather than
    // guessed at: a message whose body we had to invent is a message the salon
    // did not agree to send.
    return { ok: false, reason: 'no_template' };
  }

  if (row.channel === 'push') {
    if (!row.token) return { ok: false, reason: 'no_token', deadToken: false };
    return await sendPush(row, brand);
  }

  // SMS, WhatsApp and RCS all ride the SALON's own Message Central account.
  const { data: secret } = await db.rpc('salon_provider_secret', {
    p_salon_id: salonId,
    p_provider: 'message_central',
  });

  if (!secret?.secret) {
    // No credential. There is no Crayora account to quietly fall back on for
    // ordinary traffic - that path exists for OTP faults alone, and it is
    // alerted when it fires.
    return { ok: false, reason: 'messaging_not_configured' };
  }

  return await sendViaMessageCentral(row, secret);
}

/**
 * FCM HTTP v1, with a service account.
 *
 * Absent the credential this reports `push_not_configured` rather than
 * pretending, and the sweep escalates at the window like any other miss. That
 * is the honest failure: a dispatcher that claimed success would leave a
 * customer waiting for a message nobody sent.
 */
async function sendPush(row: BatchRow, brand: PushBrand | null): Promise<SendResult> {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) return { ok: false, reason: 'push_not_configured' };

  let account: { client_email: string; private_key: string; project_id: string };
  try {
    account = JSON.parse(raw);
  } catch {
    await alert('fcm_service_account_unparseable');
    return { ok: false, reason: 'push_not_configured' };
  }

  const token = await googleAccessToken(account);
  if (!token) return { ok: false, reason: 'push_auth_failed' };

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: fcmMessage(row, brand) }),
    },
  );

  if (response.ok) {
    const body = await response.json().catch(() => ({}));
    return { ok: true, providerMessageId: body?.name };
  }

  const text = await response.text().catch(() => '');
  const dead = /UNREGISTERED|INVALID_ARGUMENT/i.test(text);
  return { ok: false, reason: dead ? 'token_dead' : 'push_failed', deadToken: dead };
}

/** A Google access token from the service account, signed with RS256. */
async function googleAccessToken(account: {
  client_email: string;
  private_key: string;
}): Promise<string | null> {
  try {
    const now = Math.floor(Date.now() / 1000);
    const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claim = b64url(
      JSON.stringify({
        iss: account.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    );

    const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToBytes(account.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(`${header}.${claim}`),
    );

    const assertion = `${header}.${claim}.${b64urlBytes(new Uint8Array(signature))}`;
    const response = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    });
    if (!response.ok) return null;
    const body = await response.json();
    return body?.access_token ?? null;
  } catch {
    await alert('fcm_token_mint_failed');
    return null;
  }
}

async function sendViaMessageCentral(
  row: BatchRow,
  secret: { secret: string; public_key_id?: string | null },
): Promise<SendResult> {
  const base = Deno.env.get('MESSAGE_CENTRAL_BASE_URL') ?? 'https://cpaas.messagecentral.com';
  try {
    const response = await fetch(`${base}/verification/v3/send`, {
      method: 'POST',
      headers: { authToken: secret.secret, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        customerId: secret.public_key_id,
        channel: row.channel.toUpperCase(),
        message: row.body,
      }),
    });
    if (!response.ok) {
      return { ok: false, reason: `provider_${response.status}` };
    }
    const body = await response.json().catch(() => ({}));
    return { ok: true, providerMessageId: body?.data?.transactionId ?? undefined };
  } catch {
    return { ok: false, reason: 'provider_unreachable' };
  }
}

function b64url(text: string): string {
  return b64urlBytes(new TextEncoder().encode(text));
}

function b64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function pemToBytes(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  // An ArrayBuffer rather than a Uint8Array view: importKey wants a buffer
  // whose backing store is known not to be shared.
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
