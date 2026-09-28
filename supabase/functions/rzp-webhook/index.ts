// rzp-webhook/{token}
//
// Razorpay telling us a payment happened. This is the ONLY thing in the system
// that turns money into wallet credit, and it is built to be suspicious:
//
//   1. **The salon comes from the URL path token, never from the body.** A body
//      can claim any salon; the token is a value only that salon's Razorpay
//      account was configured with (ARCHITECTURE 8.3).
//   2. **The signature is verified with THAT salon's webhook secret**, over the
//      raw bytes, in constant time. An unverified webhook is discarded without
//      reading further.
//   3. **The event is deduped** on (provider, event_id) before any work.
//   4. **The amount is re-verified** in the database against the payment we
//      created. The body is not evidence of what was owed.
//
// It always answers 200 once the signature is good, even when there is nothing
// to do: a 500 makes Razorpay retry, and retrying a webhook we have already
// processed correctly is noise, not safety.

import { parseRazorpaySecret, verifyWebhook } from '../_shared/razorpay.ts';
import { admin, alert, json } from '../_shared/runtime.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  // /rzp-webhook/<token>
  const token = new URL(req.url).pathname.split('/').filter(Boolean).pop() ?? '';
  if (token === '' || token === 'rzp-webhook') {
    return json(404, { error: 'not_found' });
  }

  const signature = req.headers.get('x-razorpay-signature');
  if (!signature) return json(401, { error: 'unsigned' });

  // The RAW body: re-serialising parsed JSON changes bytes and breaks the HMAC.
  const raw = await req.text();

  const db = admin();

  const { data: salonId } = await db.rpc('salon_by_webhook_token', { p_token: token });
  if (!salonId) {
    // An unknown token. Nothing is logged about the body: a forged webhook is
    // not worth storing, and storing it is an invitation to fill the table.
    return json(404, { error: 'not_found' });
  }

  const { data: secret } = await db.rpc('salon_provider_secret', {
    p_salon_id: salonId,
    p_provider: 'razorpay',
  });
  const creds = secret ? parseRazorpaySecret(secret.public_key_id, secret.secret) : null;

  if (!creds?.webhookSecret) {
    // The salon's webhook secret is not set, so this webhook CANNOT be verified.
    // Refusing is the only safe answer - accepting an unverifiable payment
    // notification would let anyone with the URL credit a wallet.
    await alert('payments_no_webhook_secret', { salon_id: salonId });
    return json(503, { error: 'not_verifiable' });
  }

  if (!(await verifyWebhook(creds.webhookSecret, raw, signature))) {
    await alert('payments_bad_signature', { salon_id: salonId });
    return json(401, { error: 'bad_signature' });
  }

  let event: {
    event?: string;
    payload?: { payment?: { entity?: Record<string, unknown> } };
  };
  try {
    event = JSON.parse(raw);
  } catch {
    return json(400, { error: 'invalid_request' });
  }

  const entity = event.payload?.payment?.entity ?? {};
  const rzpPaymentId = typeof entity.id === 'string' ? entity.id : null;
  const eventId = req.headers.get('x-razorpay-event-id') ?? rzpPaymentId;

  if (!eventId) return json(400, { error: 'invalid_request' });

  // Dedupe BEFORE the work. Razorpay redelivers; the ledger must not care.
  const { data: seen } = await db.rpc('webhook_seen', {
    p_provider: 'razorpay',
    p_event_id: eventId,
    p_salon_id: salonId,
    p_payload: event,
  });
  if (seen === true) return json(200, { ok: true, duplicate: true });

  // Only captures credit a wallet. An authorised-but-uncaptured payment is money
  // that has not arrived, and a failure is not an event to act on here.
  if (event.event !== 'payment.captured') {
    return json(200, { ok: true, ignored: event.event ?? 'unknown' });
  }

  // Our own payment id travels in the order's notes and the receipt, so the
  // webhook can find its way back to the row we created.
  const notes = (entity.notes ?? {}) as Record<string, unknown>;
  const paymentId = typeof notes.payment_id === 'string' ? notes.payment_id : null;
  const amountPaise = typeof entity.amount === 'number' ? entity.amount : null;

  if (!paymentId || !rzpPaymentId || amountPaise === null) {
    await alert('payments_webhook_missing_fields', { salon_id: salonId });
    return json(200, { ok: true, ignored: 'incomplete' });
  }

  const { data: captured, error } = await db.rpc('record_payment_captured', {
    p_payment_id: paymentId,
    p_rzp_payment_id: rzpPaymentId,
    p_amount_paise: amountPaise,
  });

  if (error) {
    await alert('payments_capture_failed', { salon_id: salonId });
    // A 500 here is deliberate: this is the one case where Razorpay SHOULD
    // retry, because the money is real and the credit has not happened.
    return json(500, { error: 'internal' });
  }

  if (!captured?.ok) {
    // A mismatch or an unknown payment. Answering 200 stops a retry loop that
    // cannot succeed; the alert is how a person finds out.
    await alert('payments_capture_refused', {
      salon_id: salonId,
      reason: String(captured?.reason ?? 'unknown'),
    });
    return json(200, { ok: false, reason: captured?.reason ?? 'unknown' });
  }

  return json(200, { ok: true, already: captured.already === true });
});
