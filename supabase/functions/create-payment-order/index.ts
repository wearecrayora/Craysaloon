// create-payment-order
//
// The customer wants to add money. This creates the payment row, asks the
// SALON's own Razorpay account for an order, and returns what the checkout sheet
// needs - nothing else.
//
//   POST { client_action_id, amount_paise }  (with the customer's own JWT)
//     -> 200 { payment_id, order_id, key_id, amount_paise, bonus_paise }
//
// Two rules shape every line here:
//
//   * **The amount is the server's decision.** The request names one, and
//     `start_topup` checks it against the salon's minimum and a ceiling. What is
//     sent to Razorpay is what the database stored, never the request's number.
//   * **Nobody's money passes through Crayora.** The order is created with the
//     salon's key, so the settlement goes to the salon's bank (ARCH 13.1).
//
// This function runs with the CUSTOMER's JWT, so `start_topup` resolves who they
// are from the database rather than from anything the request claims.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createOrder, parseRazorpaySecret } from '../_shared/razorpay.ts';
import { admin, alert, json } from '../_shared/runtime.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authorization = req.headers.get('Authorization');
  if (!authorization) return json(401, { error: 'unauthenticated' });

  let clientActionId: unknown;
  let amountPaise: unknown;
  try {
    ({ client_action_id: clientActionId, amount_paise: amountPaise } = await req.json());
  } catch {
    return json(400, { error: 'invalid_request' });
  }
  if (typeof clientActionId !== 'string' || !UUID.test(clientActionId)) {
    return json(400, { error: 'invalid_request' });
  }
  if (typeof amountPaise !== 'number' || !Number.isInteger(amountPaise)) {
    // Paise are integers. A decimal here means somebody is sending rupees.
    return json(400, { error: 'invalid_amount' });
  }

  // As the customer: their claims decide their salon, and the database decides
  // which customer row that is.
  const asCustomer = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('CRAY_PUBLISHABLE_KEY')!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );

  const { data: started, error: startError } = await asCustomer.rpc('start_topup', {
    p_client_action_id: clientActionId,
    p_amount_paise: amountPaise,
  });

  if (startError) return json(403, { error: 'not_allowed' });
  if (!started?.ok) {
    return json(400, {
      error: started?.reason ?? 'invalid_amount',
      min_topup_paise: started?.min_topup_paise,
    });
  }

  const paymentId: string = started.payment_id;
  const amount: number = started.amount_paise ?? amountPaise;

  // Everything below needs privileges the customer does not have: the salon's
  // credential, and the order link on the payment row.
  const db = admin();

  const { data: payment } = await db
    .from('payments')
    .select('salon_id,amount_paise,razorpay_order_id,status')
    .eq('id', paymentId)
    .single();

  if (!payment) return json(500, { error: 'internal' });
  if (payment.status !== 'created') {
    // Already paid, or already cancelled. Not something to create an order for.
    return json(409, { error: 'already_settled' });
  }

  // A retried tap: the order already exists, so hand back the same one rather
  // than creating a second way to pay the same payment.
  if (payment.razorpay_order_id) {
    const { data: secret } = await db.rpc('salon_provider_secret', {
      p_salon_id: payment.salon_id,
      p_provider: 'razorpay',
    });
    const creds = secret ? parseRazorpaySecret(secret.public_key_id, secret.secret) : null;
    if (!creds) return json(503, { error: 'payments_unavailable' });
    return json(200, {
      payment_id: paymentId,
      order_id: payment.razorpay_order_id,
      key_id: creds.keyId,
      amount_paise: payment.amount_paise,
    });
  }

  const { data: secret } = await db.rpc('salon_provider_secret', {
    p_salon_id: payment.salon_id,
    p_provider: 'razorpay',
  });
  const creds = secret ? parseRazorpaySecret(secret.public_key_id, secret.secret) : null;

  if (!creds) {
    // The salon has no usable Razorpay account. There is no Crayora account to
    // fall back on - by design - so this is refused and raised.
    await alert('payments_no_salon_credentials', { salon_id: payment.salon_id });
    return json(503, { error: 'payments_unavailable' });
  }

  const order = await createOrder(creds, {
    // THE DATABASE'S amount, not the request's.
    amountPaise: payment.amount_paise,
    receipt: paymentId,
    notes: { payment_id: paymentId, salon_id: payment.salon_id },
  });

  if (!order.ok) {
    if (order.reason === 'bad_credentials') {
      await alert('payments_bad_credentials', { salon_id: payment.salon_id });
    }
    return json(502, { error: order.reason });
  }

  const { data: attached } = await db.rpc('attach_payment_order', {
    p_payment_id: paymentId,
    p_order_id: order.orderId,
  });
  if (attached !== true) {
    // The order exists at Razorpay but we could not record it. Refusing is
    // right: the webhook would have no way back to this row.
    await alert('payments_order_not_recorded', { salon_id: payment.salon_id });
    return json(500, { error: 'internal' });
  }

  return json(200, {
    payment_id: paymentId,
    order_id: order.orderId,
    key_id: creds.keyId,
    amount_paise: payment.amount_paise,
  });
});
