// Razorpay, per salon.
//
// The licensing boundary (RULES 8, ARCHITECTURE 13.1): customer money settles
// into the SALON's own Razorpay account. Crayora holds no float. So there is no
// platform key here - every call carries one salon's credentials, fetched from
// Vault at the moment of use, and nothing is cached between requests.

export interface RazorpayCreds {
  /** Public: it ships to the client to open the checkout sheet. */
  keyId: string;
  /** Secret: used server-side only, for the Orders API. */
  keySecret: string;
  /** Secret: used to verify webhook signatures. Separate from keySecret. */
  webhookSecret: string | null;
}

/**
 * Reads the salon's stored Razorpay secret.
 *
 * The stored value is JSON - `{"key_secret": "...", "webhook_secret": "..."}` -
 * because Razorpay uses two different secrets and a single opaque string cannot
 * carry both. A plain string is still accepted and treated as the key secret
 * alone, so a salon configured before the webhook secret existed keeps working
 * for payments and simply cannot verify webhooks until it is filled in. That is
 * the honest failure: refusing verification is safe, guessing is not.
 */
export function parseRazorpaySecret(publicKeyId: string | null, stored: string): RazorpayCreds | null {
  if (!publicKeyId) return null;

  let keySecret = stored;
  let webhookSecret: string | null = null;

  const trimmed = stored.trim();
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      keySecret = typeof parsed.key_secret === 'string' ? parsed.key_secret : '';
      webhookSecret = typeof parsed.webhook_secret === 'string' ? parsed.webhook_secret : null;
    } catch {
      return null;
    }
  }

  if (!keySecret) return null;
  return { keyId: publicKeyId, keySecret, webhookSecret };
}

/**
 * Creates an order on the SALON's account. Returns the order id, or null with a
 * reason - never throws, because a payment screen needs an answer rather than a
 * stack trace.
 */
export async function createOrder(
  creds: RazorpayCreds,
  args: { amountPaise: number; receipt: string; notes: Record<string, string> },
): Promise<{ ok: true; orderId: string } | { ok: false; reason: string }> {
  const auth = btoa(`${creds.keyId}:${creds.keySecret}`);

  let response: Response;
  try {
    response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        // Razorpay counts in paise, like this codebase does everywhere.
        amount: args.amountPaise,
        currency: 'INR',
        receipt: args.receipt,
        notes: args.notes,
        // The webhook is authoritative; auto-capture keeps the customer from
        // seeing an authorised-but-uncaptured limbo the salon cannot resolve.
        payment_capture: 1,
      }),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    return { ok: false, reason: 'gateway_unreachable' };
  }

  if (!response.ok) {
    // Razorpay's body can carry the key id. Log the status only.
    console.log(JSON.stringify({ razorpay_order_failed: response.status }));
    return { ok: false, reason: response.status === 401 ? 'bad_credentials' : 'gateway_refused' };
  }

  const body = (await response.json()) as { id?: string };
  if (!body.id) return { ok: false, reason: 'gateway_refused' };
  return { ok: true, orderId: body.id };
}

/**
 * Verifies a webhook came from Razorpay, using THIS salon's webhook secret:
 * HMAC-SHA256 over the raw body, compared in constant time.
 *
 * The raw body matters - re-serialising parsed JSON changes bytes and breaks the
 * signature, so callers must pass the text exactly as received.
 */
export async function verifyWebhook(
  secret: string,
  rawBody: string,
  signature: string,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return timingSafeEqual(expected, signature.trim().toLowerCase());
}

/** Length-independent, content-constant comparison. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
