-- 0107 Security audit, 14 Oct 2026: four holes, each reproduced before fixing.
--
-- 1. A WEBHOOK COULD CREDIT ANOTHER SALON'S PAYMENT.
--    app.record_payment_captured(payment, rzp_payment, amount) never checked
--    that the payment belonged to the salon whose webhook delivered it. The
--    webhook secret belongs to the SALON's Razorpay account, so its owner knows
--    it and can sign any body. Owner of salon A, also a customer of salon B on a
--    second phone: start a top-up at B (the app is handed the payment id), do
--    not pay, then sign "payment.captured" with A's secret naming B's payment -
--    and B's ledger credits money that never moved. The capture now needs the
--    salon the webhook token resolved to AND the Razorpay order the payment was
--    created with. rzp-webhook additionally fetches the payment from Razorpay's
--    own API before calling this, so a signed body alone proves nothing.
--
-- 2. EVERY IP RATE LIMIT WAS KEYED ON A VALUE THE CALLER WRITES.
--    app.caller_key() took the LEFT-most x-forwarded-for entry. Proxies append
--    on the right; the left is whatever the client sent. Reproduced against the
--    live API: a request carrying "X-Forwarded-For: 203.0.113.77" was counted
--    in the bucket join_code:203.0.113.77. Rotate the header and the 60-an-hour
--    join-code limit is gone. cf-connecting-ip is set by Cloudflare, which
--    fronts the Supabase API, and overwritten on every request - preferred now,
--    as the Edge Functions already did (_shared/runtime.ts clientAddress).
--
-- 3. start_join WAS AN UNLIMITED JOIN-CODE ORACLE.
--    It rejected an unknown code BEFORE counting anything, so "that code is not
--    valid" vs anything else could be asked forever - around resolve_join_code's
--    limit. Which salons use Cray Salon is theirs to tell (RULES 2). The
--    caller is now counted first.
--
-- 4. ONE NUMBER COULD BE SENT ~430 OTPs A DAY.
--    3 per 10 minutes, all day, every one an SMS the salon pays for. A person
--    signing in needs a handful; ten a day is generous and ends the bombing.

-- ---------------------------------------------------------------------------
-- 1. Capture: the right salon, the right order.
-- ---------------------------------------------------------------------------

drop function if exists public.record_payment_captured(uuid, text, bigint);
drop function if exists app.record_payment_captured(uuid, text, bigint);

create function app.record_payment_captured(
  p_payment_id     uuid,
  p_rzp_payment_id text,
  p_amount_paise   bigint,
  p_salon_id       uuid,
  p_rzp_order_id   text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment record;
begin
  select p.id, p.salon_id, p.customer_id, p.amount_paise, p.status, p.visit_id,
         p.razorpay_order_id
    into v_payment
    from public.payments p
   where p.id = p_payment_id
   for update;

  -- Another salon's payment answers exactly like no payment: the webhook of
  -- salon A learns nothing about salon B's rows.
  if v_payment.id is null or v_payment.salon_id is distinct from p_salon_id then
    return jsonb_build_object('ok', false, 'reason', 'no_such_payment');
  end if;

  -- A payment is only ever paid through the order we created for it (0050).
  if v_payment.razorpay_order_id is null
     or v_payment.razorpay_order_id is distinct from p_rzp_order_id then
    return jsonb_build_object('ok', false, 'reason', 'order_mismatch');
  end if;

  if v_payment.amount_paise <> p_amount_paise then
    return jsonb_build_object('ok', false, 'reason', 'amount_mismatch',
                              'expected_paise', v_payment.amount_paise);
  end if;

  if v_payment.status = 'captured' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.payments
     set status = 'captured',
         razorpay_payment_id = p_rzp_payment_id,
         captured_at = now()
   where id = p_payment_id;

  if v_payment.visit_id is not null then
    return jsonb_build_object('ok', true, 'already', false,
                              'settled', app.refresh_visit_payment_status(v_payment.visit_id));
  end if;

  return jsonb_build_object('ok', true, 'already', false,
                            'credit', app.wallet_credit_from_payment(p_payment_id));
end;
$$;

create function public.record_payment_captured(
  p_payment_id     uuid,
  p_rzp_payment_id text,
  p_amount_paise   bigint,
  p_salon_id       uuid,
  p_rzp_order_id   text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select app.record_payment_captured(p_payment_id, p_rzp_payment_id, p_amount_paise,
                                     p_salon_id, p_rzp_order_id)
$$;

comment on function public.record_payment_captured(uuid, text, bigint, uuid, text) is
  'PostgREST entry point for rzp-webhook (0078, 0107). The salon is the one the webhook token resolved to, and the order and amount come from Razorpay''s API, not the webhook body. Service role only: a customer who could call this could tell the ledger they had paid.';

revoke all on function app.record_payment_captured(uuid, text, bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.record_payment_captured(uuid, text, bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.record_payment_captured(uuid, text, bigint, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 2. The caller's address: the one Cloudflare writes.
-- ---------------------------------------------------------------------------

create or replace function app.caller_key(p_fallback text default null)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_headers json;
  v_ip      text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    v_headers := null;
  end;

  if v_headers is not null then
    -- Set by Cloudflare at the edge and overwritten on every request: the one
    -- address here the caller cannot choose.
    v_ip := nullif(trim(coalesce(v_headers ->> 'cf-connecting-ip', '')), '');
    if v_ip is null then
      -- Without it, the RIGHT-most x-forwarded-for entry: the one the last
      -- proxy appended. The left-most is whatever the client wrote (0107).
      v_ip := nullif(trim(regexp_replace(
                coalesce(v_headers ->> 'x-forwarded-for', ''), '^.*,', '')), '');
    end if;
  end if;

  return coalesce(v_ip, nullif(trim(coalesce(p_fallback, '')), ''), 'unknown');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. start_join: count the caller before answering anything.
-- ---------------------------------------------------------------------------

create or replace function app.start_join(p_code text, p_phone text, p_device_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code     text;
  v_salon_id uuid;
  v_hash     bytea;
begin
  -- FIRST, before the code is looked at: an unknown code that costs nothing is
  -- an oracle for which codes exist (0107).
  if not app.rate_limit_hit(
       'join_caller:' || app.caller_key(p_device_key), 20, interval '1 hour') then
    raise exception 'too many attempts' using errcode = '53400';
  end if;

  v_code := app.normalise_join_code(p_code);

  select id into v_salon_id
    from public.salons
   where join_code = v_code and status = 'active'
     and not app.salon_blocked(id);

  if v_salon_id is null then
    raise exception 'that code is not valid' using errcode = '22023';
  end if;

  v_hash := app.phone_hash(p_phone);

  if not app.rate_limit_hit(
       'join_phone:' || encode(v_hash, 'hex'), 5, interval '1 hour') then
    raise exception 'too many attempts for this number' using errcode = '53400';
  end if;

  if not app.rate_limit_hit(
       'join_salon:' || v_salon_id::text, 500, interval '1 day') then
    raise exception 'this salon has reached its daily join limit'
      using errcode = '53400';
  end if;

  insert into public.join_intents (phone_hash, salon_id, created_at, expires_at)
  values (v_hash, v_salon_id, now(), now() + interval '15 minutes')
  on conflict (phone_hash) do update
    set salon_id = excluded.salon_id,
        created_at = excluded.created_at,
        expires_at = excluded.expires_at;

  return jsonb_build_object('ok', true, 'expires_in_seconds', 900);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. otp_begin: a daily ceiling per number.
-- ---------------------------------------------------------------------------

create or replace function public.otp_begin(p_phone text, p_device_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   bytea;
  v_sender jsonb;
  v_caller text;
  v_state  text;
begin
  v_hash := app.phone_hash(p_phone);

  v_sender := app.resolve_otp_sender(p_phone);
  if not (v_sender ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  if not app.rate_limit_hit(
       'otp_send_phone:' || encode(v_hash, 'hex'), 3, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  -- 3 per 10 minutes alone allowed ~430 a day to one number, each an SMS the
  -- salon pays for (0107).
  if not app.rate_limit_hit(
       'otp_send_phone_day:' || encode(v_hash, 'hex'), 10, interval '1 day') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  -- NOT app.caller_key(): the caller is the otp-send Edge Function, so the
  -- customer's address is passed explicitly (0030).
  v_caller := coalesce(nullif(trim(coalesce(p_device_key, '')), ''), 'unknown');
  if not app.rate_limit_hit(
       'otp_send_caller:' || v_caller, 10, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  v_state := app.salon_messaging_state((v_sender ->> 'salon_id')::uuid);

  if v_state = 'blocked' then
    return jsonb_build_object('ok', false, 'reason', 'salon_blocked');
  end if;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_sender ->> 'salon_id',
    'source', v_sender ->> 'source',
    'mobile', app.canonical_phone(p_phone),
    'country_code', '91',
    'messaging_state', v_state,
    'messaging_trial_active', v_state = 'trial'
  );
end;
$$;
