// otp-send (ADR-36)
//
// Asks Message Central to send an OTP from the right salon's account, and
// remembers which verification it started. Runs before anyone is logged in.
//
//   POST { phone }  ->  200 { challenge_id }
//
// The order is fixed: resolve the salon and apply the limits in the database,
// THEN spend money. Nothing is sent for a number with no salon context.

import { mcSend, platformCreds, type McCreds } from '../_shared/message-central.ts';
import { admin, alert, clientAddress, json } from '../_shared/runtime.ts';

/**
 * A number with no salon context gets a response that looks like success.
 *
 * If it got a distinct "not registered" answer, anyone could walk phone
 * numbers and learn which people use a Cray Salon app at all - personal data
 * under DPDP, and exactly what a stalker would want. So it gets a random,
 * unusable challenge id, nothing is sent, nothing is spent, and verifying
 * against it fails exactly like a wrong code on an expired challenge.
 *
 * The delay matters as much as the body. Without it this path answers in a few
 * milliseconds while a real send waits on Message Central, and the difference
 * is the oracle all over again.
 */
async function decoy(): Promise<Response> {
  await new Promise((r) => setTimeout(r, 450 + Math.floor(Math.random() * 500)));
  return json(200, { challenge_id: crypto.randomUUID(), expires_in: 60 });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  let phone: unknown;
  try {
    ({ phone } = await req.json());
  } catch {
    return json(400, { error: 'invalid_request' });
  }
  if (typeof phone !== 'string' || phone.trim() === '') {
    return json(400, { error: 'invalid_phone' });
  }

  const db = admin();

  // 1. Salon resolution and rate limits, in the database, before any spend.
  const { data: begin, error: beginErr } = await db.rpc('otp_begin', {
    p_phone: phone,
    p_device_key: clientAddress(req),
  });
  if (beginErr) {
    // app.phone_hash raises on anything that is not a valid Indian mobile.
    return json(400, { error: 'invalid_phone' });
  }
  if (!begin?.ok) {
    if (begin?.reason === 'rate_limited') return json(429, { error: 'rate_limited' });
    if (begin?.reason === 'salon_blocked') {
      // A real customer of a real salon whose messaging trial and grace have
      // both ended without it setting up its own account (0033). Not a decoy:
      // they are owed a true answer, and a code that never arrives would look
      // like the app is broken. The app tells them to contact the salon.
      return json(403, { error: 'salon_unavailable' });
    }
    return decoy();
  }

  const salonId: string = begin.salon_id;
  const mobile: string = begin.mobile;

  // 2. The salon's own account, decrypted at the moment of use (ARCH 8.1).
  const { data: salonSender } = await db.rpc('otp_salon_sender', { p_salon_id: salonId });

  let creds: McCreds | null = salonSender
    ? { customerId: salonSender.customer_id, authToken: salonSender.auth_token }
    : null;
  let sender: 'salon' | 'trial' | 'grace' | 'platform' = 'salon';

  if (!creds) {
    creds = platformCreds();
    const state: string = begin.messaging_state ?? (begin.messaging_trial_active ? 'trial' : 'fallback');
    if (state === 'trial' || state === 'grace') {
      // An operator-granted trial (0032) or grace period (0033): Crayora pays
      // for this salon's OTPs ON PURPOSE until it ends. Intended, so not
      // alerted, and recorded under its own sender so it never inflates the
      // count of genuine fallbacks. A salon that HAS its own account never
      // gets here: its own account is used even during a trial.
      sender = state;
    } else {
      sender = 'platform';
      await alert('otp_fallback_no_salon_credentials', { salon_id: salonId });
    }
  }
  if (!creds) {
    await alert('otp_no_sender_available', { salon_id: salonId });
    return json(503, { error: 'send_unavailable' });
  }

  // 3. Send. A salon account that fails falls back to Crayora's, once.
  let sent = await mcSend(creds, mobile, begin.country_code);

  if (!sent.ok && sender === 'salon') {
    await alert('otp_fallback_salon_send_failed', { salon_id: salonId, reason: sent.reason });
    const platform = platformCreds();
    if (platform) {
      creds = platform;
      sender = 'platform';
      sent = await mcSend(creds, mobile, begin.country_code);
    }
  }

  if (!sent.ok) {
    await alert('otp_send_failed', { salon_id: salonId, sender, reason: sent.reason });
    return json(502, { error: 'send_failed' });
  }

  // 4. Remember what we asked, so verify can only ever check against this.
  const { data: challengeId, error: recErr } = await db.rpc('otp_record_challenge', {
    p_phone: phone,
    p_salon_id: salonId,
    p_verification_id: sent.verificationId,
    p_sender: sender,
  });
  if (recErr || !challengeId) {
    await alert('otp_challenge_not_recorded', { salon_id: salonId });
    return json(500, { error: 'internal' });
  }

  // expires_in is Message Central's window for the CODE, which is what the
  // customer is racing - not our challenge's, which is longer.
  return json(200, { challenge_id: challengeId, expires_in: sent.timeoutSeconds });
});
