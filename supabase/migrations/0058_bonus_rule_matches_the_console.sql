-- 0058 The bonus rule the console writes is not the one the ledger read
--
-- The console has always written `wallet_rule = {topup_paise, bonus_paise}` -
-- the PRD's shape, "₹500 → +₹50" (PRD §9.1, IMPLEMENTATION C3). 0048 and 0049
-- read `bonus_percent` and `min_topup_paise`, which no screen writes and no
-- document specifies. **A salon configured through the console would therefore
-- have issued no bonus at all**, silently, while the Add Money screen said so
-- too - consistent, and consistently wrong.
--
-- Nothing caught it because both halves were tested against a wallet_rule that
-- the test wrote itself in the shape the function expected. A fixture that
-- agrees with the code under test proves only that the code agrees with itself.
--
-- Two changes, and the second matters more than the first:
--
--   1. The rule is a **slab**: floor(amount / topup_paise) × bonus_paise, so
--      ₹500 → ₹50, ₹1,000 → ₹100, ₹2,000 → ₹200 (decision of 28 Sep 2026). A
--      threshold that pays ₹50 on a ₹5,000 top-up is what an owner would call a
--      bug the first time a customer asks.
--
--   2. **There is now ONE function that computes a bonus**, and the quote and
--      the credit both call it. They could disagree before because they each
--      had their own copy of the arithmetic; the comment in 0049 said they must
--      match, and a comment is not a mechanism. The gate asserts they agree
--      across a range of amounts, which is the assertion that would have caught
--      this in the first place.
--
-- `bonus_expiry_days` defaults to **180** (ARCHITECTURE 14.2). It was defaulting
-- to 0, which meant a bonus lot with NO expiry - bonus credit that never
-- expires, which is the opposite of the rule and quietly generous.

create or replace function app.wallet_bonus_for(
  p_rule         jsonb,
  p_amount_paise bigint
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with rule as (
    select coalesce(p_rule, '{}'::jsonb) as r
  ), terms as (
    select
      coalesce((r ->> 'topup_paise')::bigint, 0)     as slab,
      coalesce((r ->> 'bonus_paise')::bigint, 0)     as per_slab,
      coalesce((r ->> 'min_topup_paise')::bigint, 0) as minimum,
      -- 180 unless the owner has said otherwise, captured onto the lot at
      -- issue. Not read live, ever (RULES 5.3.4).
      coalesce((r ->> 'bonus_expiry_days')::integer, 180) as days
    from rule
  )
  select jsonb_build_object(
    'bonus_paise',
      case
        when p_amount_paise is null or p_amount_paise <= 0 then 0
        when t.slab <= 0 or t.per_slab <= 0 then 0
        when p_amount_paise < t.minimum then 0
        -- The slab. Integer division in paise: no float ever touches money.
        else (p_amount_paise / t.slab) * t.per_slab
      end,
    'expiry_days', t.days,
    'min_topup_paise', t.minimum,
    'slab_paise', t.slab,
    'bonus_per_slab_paise', t.per_slab
  )
  from terms t
$$;

comment on function app.wallet_bonus_for is
  'The ONE place a bonus is computed (0058). The quote and the credit both call it, because when each had its own copy they disagreed - the console wrote {topup_paise, bonus_paise} and the ledger read bonus_percent, so every console-configured salon issued no bonus at all. A slab: floor(amount / topup_paise) x bonus_paise.';

-- ---------------------------------------------------------------------------
-- The quote, now reading the rule the console writes
-- ---------------------------------------------------------------------------

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
  v_terms jsonb;
  v_bonus bigint;
  v_days  integer;
begin
  if v_salon is null then
    raise exception 'topup_quote: no salon in session' using errcode = '42501';
  end if;
  if p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'topup_quote: an amount is required';
  end if;

  select s.wallet_rule into v_rule from public.salons s where s.id = v_salon;

  v_terms := app.wallet_bonus_for(v_rule, p_amount_paise);
  v_bonus := (v_terms ->> 'bonus_paise')::bigint;
  v_days  := (v_terms ->> 'expiry_days')::integer;

  return jsonb_build_object(
    'amount_paise', p_amount_paise,
    'bonus_paise', v_bonus,
    'bonus_expires_at', case when v_bonus > 0 and v_days > 0
                             then now() + make_interval(days => v_days) end,
    'min_topup_paise', (v_terms ->> 'min_topup_paise')::bigint,
    -- What the rule IS, so the screen can say "₹500 → +₹50" rather than only
    -- what this particular amount earns.
    'slab_paise', (v_terms ->> 'slab_paise')::bigint,
    'bonus_per_slab_paise', (v_terms ->> 'bonus_per_slab_paise')::bigint,
    -- Both of these are facts about the product, not settings. They are returned
    -- so the screen states them rather than a developer remembering to.
    'paid_credit_expires', false,
    'refundable', false);
end;
$$;

comment on function public.topup_quote is
  'What the Add Money screen must show BEFORE payment (RULES 5.3.6): the bonus, its expiry, that paid credit never expires and that a top-up is not refundable. Shares its arithmetic with the credit through app.wallet_bonus_for, so the screen cannot promise a bonus the ledger refuses (0058).';

-- ---------------------------------------------------------------------------
-- The credit, from the same arithmetic
-- ---------------------------------------------------------------------------

create or replace function app.wallet_credit_from_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment  record;
  v_rule     jsonb;
  v_terms    jsonb;
  v_bonus    bigint := 0;
  v_paid_lot uuid;
  v_bonus_lot uuid;
  v_days     integer;
  v_expires  timestamptz;
begin
  select p.id, p.salon_id, p.customer_id, p.amount_paise, p.status
    into v_payment
    from public.payments p
   where p.id = p_payment_id
   for update;

  if v_payment.id is null then
    raise exception 'wallet_credit_from_payment: no such payment';
  end if;
  if v_payment.status <> 'captured' then
    -- Credit follows capture, never authorisation: an authorised-but-uncaptured
    -- payment is money that has not arrived.
    return jsonb_build_object('ok', false, 'reason', 'not_captured');
  end if;

  -- Idempotent: a webhook redelivery must not credit twice.
  if exists (
    select 1 from public.wallet_transactions t
     where t.payment_id = p_payment_id and t.kind in ('credit_topup', 'credit_bonus')
  ) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  select s.wallet_rule into v_rule from public.salons s where s.id = v_payment.salon_id;

  -- The paid lot: what the customer paid. No expiry, ever.
  insert into public.wallet_lots
    (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at, source_payment_id)
  values
    (v_payment.salon_id, v_payment.customer_id, 'paid', v_payment.amount_paise,
     v_payment.amount_paise, null, p_payment_id)
  returning id into v_paid_lot;

  perform app.wallet_post(
    v_payment.salon_id, v_payment.customer_id, 'credit_topup', v_payment.amount_paise,
    v_paid_lot, p_payment_id, null, null, null);

  -- The same function the screen quoted from. If these ever differ again, they
  -- differ in one place, not two.
  v_terms := app.wallet_bonus_for(v_rule, v_payment.amount_paise);
  v_bonus := (v_terms ->> 'bonus_paise')::bigint;
  v_days  := (v_terms ->> 'expiry_days')::integer;

  if v_bonus > 0 then
    v_expires := case when v_days > 0 then now() + make_interval(days => v_days) end;

    insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at, source_payment_id)
    values
      (v_payment.salon_id, v_payment.customer_id, 'bonus', v_bonus, v_bonus,
       v_expires, p_payment_id)
    returning id into v_bonus_lot;

    perform app.wallet_post(
      v_payment.salon_id, v_payment.customer_id, 'credit_bonus', v_bonus,
      v_bonus_lot, p_payment_id, null, null, null);
  end if;

  -- Automation B (0056). Inside the same transaction as the credit, so there is
  -- no state where the money landed and the receipt was never owed.
  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (
    v_payment.salon_id, 'wallet.topped_up', p_payment_id,
    jsonb_build_object(
      'customer_id',   v_payment.customer_id,
      'amount_paise',  v_payment.amount_paise,
      'bonus_paise',   v_bonus,
      'bonus_expires_at', v_expires,
      'paid_lot_id',   v_paid_lot,
      'bonus_lot_id',  v_bonus_lot));

  return jsonb_build_object('ok', true, 'already', false,
                            'paid_paise', v_payment.amount_paise,
                            'bonus_paise', v_bonus,
                            'bonus_expires_at', v_expires);
end;
$$;

comment on function app.wallet_credit_from_payment is
  'Caller 1 of five (RULES 5.2). Credit follows CAPTURE, not authorisation, and is idempotent per payment so a webhook redelivery cannot credit twice. The bonus comes from app.wallet_bonus_for - the same function the quote used (0058) - and its terms are captured onto the lot at issue, so a rule change tomorrow cannot expire money issued today. Emits wallet.topped_up in the same transaction (Automation B).';
