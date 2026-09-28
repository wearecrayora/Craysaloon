-- 0049 Taking the money (M7): top-up, capture, webhook
--
-- The licensing boundary this whole file exists to respect (RULES 8,
-- ARCHITECTURE 13.1): **the customer's money goes into the SALON's own Razorpay
-- account.** Crayora holds no float, touches no settlement and is not a payment
-- aggregator. So every call is made with that salon's own key, fetched at the
-- moment of use, and the webhook that confirms it is per-salon.
--
-- Four things here, and one thing deliberately NOT here:
--
--   topup_quote              what the Add Money screen must show BEFORE payment
--   start_topup              the amount is decided by the SERVER, not the client
--   record_payment_captured  capture, amount re-verified, then credit
--   webhook_seen             a redelivered webhook is a no-op
--
-- Not here: any path that credits a wallet from a client request. A phone saying
-- "I paid" is not payment. Credit follows a captured payment, and a captured
-- payment comes from Razorpay's webhook, verified with the salon's own secret.

-- ---------------------------------------------------------------------------
-- 1. ONE function reads a decrypted credential - now for any provider
-- ---------------------------------------------------------------------------
--
-- 0028 said of otp_salon_sender: "The ONE function that returns a decrypted
-- credential... Never add a second." Razorpay needs one too, and adding a second
-- reader would turn one auditable door into two. So the door is generalised and
-- otp_salon_sender becomes a caller of it, keeping the shape otp-send expects.
-- The count stays one, which is the property that matters.

create or replace function public.salon_provider_secret(
  p_salon_id uuid,
  p_provider public.integration_provider
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row    record;
  v_secret text;
begin
  select public_key_id, vault_secret_id, status::text, last4, sender_id
    into v_row
    from public.salon_integrations
   where salon_id = p_salon_id and provider = p_provider;

  -- `failing` is excluded on purpose: a credential already seen to fail should
  -- not cost a customer a payment attempt to rediscover.
  if v_row.vault_secret_id is null or v_row.status = 'failing' then
    return null;
  end if;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets where id = v_row.vault_secret_id;

  if v_secret is null then
    return null;
  end if;

  return jsonb_build_object(
    'public_key_id', v_row.public_key_id,
    'secret', v_secret,
    'sender_id', v_row.sender_id,
    'last4', v_row.last4);
end;
$$;

comment on function public.salon_provider_secret is
  'The ONE function that returns a decrypted credential, to service_role only, for an Edge Function at the moment of use (ARCHITECTURE 8.1). Never add a second - generalise this one, as 0049 did for Razorpay.';

revoke all on function public.salon_provider_secret(uuid, public.integration_provider)
  from public, anon, authenticated;
grant execute on function public.salon_provider_secret(uuid, public.integration_provider)
  to service_role;

-- otp-send keeps its own shape and stops reading Vault itself.
create or replace function public.otp_salon_sender(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret jsonb;
begin
  v_secret := public.salon_provider_secret(p_salon_id, 'message_central');
  if v_secret is null or v_secret ->> 'public_key_id' is null then
    return null;
  end if;
  return jsonb_build_object(
    'customer_id', v_secret ->> 'public_key_id',
    'auth_token', v_secret ->> 'secret');
end;
$$;

comment on function public.otp_salon_sender is
  'The salon''s Message Central account, for otp-send at the moment of use. Delegates to salon_provider_secret (0049) so the system still has exactly ONE function that reads Vault.';

-- ---------------------------------------------------------------------------
-- 2. What the customer must be told BEFORE paying
-- ---------------------------------------------------------------------------
--
-- RULES 5.3.6: the Add Money screen shows the bonus, its expiry, that paid
-- credit never expires, and that top-ups are non-refundable - before payment.
-- This function is where those facts come from, so the screen cannot show a
-- bonus the ledger would not grant.

create or replace function public.topup_quote(p_amount_paise bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_rule  jsonb;
  v_bonus bigint := 0;
  v_days  integer;
begin
  if v_salon is null then
    raise exception 'topup_quote: no salon in session' using errcode = '42501';
  end if;
  if p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'topup_quote: an amount is required';
  end if;

  select s.wallet_rule into v_rule from public.salons s where s.id = v_salon;
  v_rule := coalesce(v_rule, '{}'::jsonb);
  v_days := coalesce((v_rule ->> 'bonus_expiry_days')::integer, 0);

  if coalesce((v_rule ->> 'bonus_percent')::numeric, 0) > 0
     and p_amount_paise >= coalesce((v_rule ->> 'min_topup_paise')::bigint, 0) then
    -- The SAME arithmetic wallet_credit_from_payment uses, in whole paise. If
    -- these two ever disagree, the screen promises a bonus the ledger refuses.
    v_bonus := (p_amount_paise * (v_rule ->> 'bonus_percent')::numeric / 100)::bigint;
  end if;

  return jsonb_build_object(
    'amount_paise', p_amount_paise,
    'bonus_paise', v_bonus,
    'bonus_expires_at', case when v_bonus > 0 and v_days > 0
                             then now() + make_interval(days => v_days) end,
    'min_topup_paise', coalesce((v_rule ->> 'min_topup_paise')::bigint, 0),
    'bonus_percent', coalesce((v_rule ->> 'bonus_percent')::numeric, 0),
    -- Both of these are facts about the product, not settings. They are returned
    -- so the screen states them rather than a developer remembering to.
    'paid_credit_expires', false,
    'refundable', false);
end;
$$;

comment on function public.topup_quote is
  'What the Add Money screen must show BEFORE payment (RULES 5.3.6): the bonus, its expiry, that paid credit never expires and that a top-up is not refundable. Shares its arithmetic with wallet_credit_from_payment so the screen cannot promise a bonus the ledger refuses.';

revoke all on function public.topup_quote(bigint) from public, anon;
grant execute on function public.topup_quote(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Starting a top-up: the SERVER decides the amount
-- ---------------------------------------------------------------------------

create or replace function public.start_topup(
  p_client_action_id uuid,
  p_amount_paise     bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_role     text := app.current_app_role();
  v_customer uuid;
  v_rule     jsonb;
  v_min      bigint;
  v_payment  uuid;
begin
  if v_salon is null or v_role <> 'customer' then
    -- A top-up is a customer paying their own money. Staff taking cash is a
    -- different thing and is not this function.
    raise exception 'start_topup: only a customer tops up their own wallet'
      using errcode = '42501';
  end if;

  v_customer := app.current_customer_id();
  if v_customer is null then
    raise exception 'start_topup: no customer for this session' using errcode = '42501';
  end if;

  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  -- Idempotent on the action id, like every other write (RULES 9.3): a retried
  -- tap must not create a second order.
  select p.id into v_payment
    from public.payments p
   where p.salon_id = v_salon and p.idempotency_key = p_client_action_id::text;
  if v_payment is not null then
    return jsonb_build_object('ok', true, 'already', true, 'payment_id', v_payment);
  end if;

  select s.wallet_rule into v_rule from public.salons s where s.id = v_salon;
  v_min := coalesce((coalesce(v_rule, '{}'::jsonb) ->> 'min_topup_paise')::bigint, 0);

  -- The amount is checked HERE, not in the app: a client that can name any
  -- amount can name one the salon never offered.
  if p_amount_paise is null or p_amount_paise <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_amount');
  end if;
  if p_amount_paise < v_min then
    return jsonb_build_object('ok', false, 'reason', 'below_minimum',
                              'min_topup_paise', v_min);
  end if;
  -- A sanity ceiling. A ten-lakh "top-up" at a salon counter is a typo or an
  -- attack, and either way it should not reach a payment gateway.
  if p_amount_paise > 10000000 then
    return jsonb_build_object('ok', false, 'reason', 'above_maximum');
  end if;

  insert into public.payments
    (salon_id, customer_id, method, amount_paise, status, idempotency_key)
  values
    (v_salon, v_customer, 'upi', p_amount_paise, 'created', p_client_action_id::text)
  returning id into v_payment;

  return jsonb_build_object('ok', true, 'already', false, 'payment_id', v_payment,
                            'amount_paise', p_amount_paise);
end;
$$;

comment on function public.start_topup is
  'Creates the payment a Razorpay order will be made for. The AMOUNT IS VALIDATED SERVER-SIDE against the salon''s minimum and a sanity ceiling: a client that can name any amount can name one the salon never offered. Idempotent on the action id.';

revoke all on function public.start_topup(uuid, bigint) from public, anon;
grant execute on function public.start_topup(uuid, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Capture, re-verified, then credit
-- ---------------------------------------------------------------------------
--
-- Called only by the webhook, which has already verified Razorpay's signature
-- with THAT salon's secret and resolved the salon from the URL path rather than
-- the body (ARCHITECTURE 8.3).

create or replace function app.record_payment_captured(
  p_payment_id       uuid,
  p_rzp_payment_id   text,
  p_amount_paise     bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment record;
begin
  select p.id, p.salon_id, p.customer_id, p.amount_paise, p.status
    into v_payment
    from public.payments p
   where p.id = p_payment_id
   for update;

  if v_payment.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_payment');
  end if;

  -- **Re-verify the amount.** The webhook body is not evidence of what was owed;
  -- the payment row we created is. A mismatch is never partially accepted.
  if v_payment.amount_paise <> p_amount_paise then
    return jsonb_build_object('ok', false, 'reason', 'amount_mismatch',
                              'expected_paise', v_payment.amount_paise);
  end if;

  if v_payment.status = 'captured' then
    -- Already done. Webhooks redeliver; this is the normal case, not an error.
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.payments
     set status = 'captured',
         razorpay_payment_id = p_rzp_payment_id,
         captured_at = now()
   where id = p_payment_id;

  -- Credit follows capture, and is itself idempotent per payment (0048).
  return jsonb_build_object('ok', true, 'already', false,
                            'credit', app.wallet_credit_from_payment(p_payment_id));
end;
$$;

comment on function app.record_payment_captured is
  'Marks a payment captured and credits the wallet. RE-VERIFIES the amount against the payment we created, because the webhook body is not evidence of what was owed. Idempotent: a redelivered webhook credits nothing twice.';

revoke all on function app.record_payment_captured(uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function app.record_payment_captured(uuid, text, bigint) to service_role;

-- ---------------------------------------------------------------------------
-- 5. The webhook's own defences
-- ---------------------------------------------------------------------------

-- The salon is resolved from the PATH TOKEN, never from the payload. A body can
-- claim any salon; a token is something only that salon's Razorpay account was
-- configured with.
create or replace function public.salon_by_webhook_token(p_token text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.salons s
   where s.webhook_token = p_token and s.status <> 'setup'
$$;

revoke all on function public.salon_by_webhook_token(text) from public, anon, authenticated;
grant execute on function public.salon_by_webhook_token(text) to service_role;

-- Dedupe. The unique index is on (provider, event_id) and deliberately does NOT
-- include salon_id: an event id is unique at the provider, so scoping it per
-- salon would let the same event be processed once per salon.
create or replace function app.webhook_seen(
  p_provider text,
  p_event_id text,
  p_salon_id uuid,
  p_payload  jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.webhook_events (provider, event_id, salon_id, payload)
  values (p_provider, p_event_id, p_salon_id, p_payload);
  return false;  -- not seen before
exception
  when unique_violation then
    return true;  -- seen; the caller does nothing further
end;
$$;

comment on function app.webhook_seen is
  'Records a webhook and says whether it had already arrived. The unique index is (provider, event_id) with NO salon_id: an event id is unique at the provider, so scoping per salon would let one event be processed once per salon.';

revoke all on function app.webhook_seen(text, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function app.webhook_seen(text, text, uuid, jsonb) to service_role;
