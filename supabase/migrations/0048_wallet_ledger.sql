-- 0048 The wallet ledger (M7)
--
-- Money, and the rules that are not negotiable (RULES 5):
--
--   * `wallet_transactions` is APPEND-ONLY. A reversal is a new row. The table
--     already blocks UPDATE and DELETE twice over (0013); nothing here loosens
--     that, and nothing here ever needs to.
--   * **ONE write path.** `app.wallet_post` is the only function that inserts a
--     ledger row. It takes the row lock, recomputes the balance, writes the
--     entry and updates the cached balance in one transaction (ARCH 5.1.3). The
--     five permitted callers (RULES 5.2) all go through it, so "cannot
--     overdraw" is implemented once rather than remembered five times.
--   * **Paid credit never expires.** Not a default, not a flag: the function
--     that expires a lot REFUSES a paid one, and the table refuses to store an
--     expiry on one. Two independent refusals, because this is the rule most
--     likely to be "simplified" later (RULES 5.3.3).
--   * **Bonus first, FIFO by expiry.** The customer keeps the credit that cannot
--     expire for as long as possible - which is the opposite of what maximises
--     the salon's breakage, and is the point.
--   * No owner, manager or staff path exists. These functions are not granted to
--     any tenant role; the server calls them.

-- ---------------------------------------------------------------------------
-- The one write path
-- ---------------------------------------------------------------------------

create or replace function app.wallet_post(
  p_salon_id    uuid,
  p_customer_id uuid,
  p_kind        public.wallet_entry_kind,
  p_amount_paise bigint,
  p_lot_id      uuid default null,
  p_payment_id  uuid default null,
  p_visit_id    uuid default null,
  p_reason      text default null,
  p_actor_admin_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance bigint;
  v_entry   bigint;
begin
  if p_amount_paise = 0 then
    raise exception 'wallet_post: a zero entry says nothing - do not write one';
  end if;

  -- The lock is the whole mechanism for "concurrent debits cannot overdraw":
  -- two checkouts for the same customer serialise here, and the second one sees
  -- the first one's balance rather than the one it read a moment ago.
  select w.balance_paise into v_balance
    from public.wallet_accounts w
   where w.customer_id = p_customer_id
   for update;

  if v_balance is null then
    insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
    values (p_customer_id, p_salon_id, 0)
    on conflict (customer_id) do nothing;

    select w.balance_paise into v_balance
      from public.wallet_accounts w
     where w.customer_id = p_customer_id
     for update;
    v_balance := coalesce(v_balance, 0);
  end if;

  if v_balance + p_amount_paise < 0 then
    -- Not an assertion about the caller's arithmetic: it is the guarantee that a
    -- customer cannot spend credit they do not have, whatever raced.
    raise exception 'wallet_post: insufficient credit' using errcode = '23514';
  end if;

  insert into public.wallet_transactions
    (salon_id, customer_id, kind, amount_paise, balance_after, lot_id, payment_id,
     visit_id, reason, actor_admin_id)
  values
    (p_salon_id, p_customer_id, p_kind, p_amount_paise, v_balance + p_amount_paise,
     p_lot_id, p_payment_id, p_visit_id, p_reason, p_actor_admin_id)
  returning id into v_entry;

  update public.wallet_accounts
     set balance_paise = v_balance + p_amount_paise, updated_at = now()
   where customer_id = p_customer_id;

  return v_entry;
end;
$$;

comment on function app.wallet_post is
  'The ONLY function that writes a ledger row (RULES 5.1.3). Takes the row lock, recomputes, inserts, updates the cached balance - so "cannot overdraw" exists once instead of in five places. Never granted to a tenant role.';

-- ---------------------------------------------------------------------------
-- Caller 1: credit from a captured payment
-- ---------------------------------------------------------------------------
--
-- Bonus terms are CAPTURED ONTO THE LOT at issue (RULES 5.3.4): changing the
-- salon's rule tomorrow cannot retroactively expire money issued today. The paid
-- lot gets no expiry at all, which the table enforces independently.

create or replace function app.wallet_credit_from_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment  record;
  v_rule     jsonb;
  v_bonus    bigint := 0;
  v_paid_lot uuid;
  v_bonus_lot uuid;
  v_days     integer;
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
  v_rule := coalesce(v_rule, '{}'::jsonb);

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

  -- The bonus, if the salon offers one and this top-up reaches the threshold.
  if coalesce((v_rule ->> 'bonus_percent')::numeric, 0) > 0
     and v_payment.amount_paise >= coalesce((v_rule ->> 'min_topup_paise')::bigint, 0) then
    -- Integer paise throughout: the percentage is applied and truncated, never
    -- carried as a float.
    v_bonus := (v_payment.amount_paise * (v_rule ->> 'bonus_percent')::numeric / 100)::bigint;
  end if;

  if v_bonus > 0 then
    v_days := coalesce((v_rule ->> 'bonus_expiry_days')::integer, 0);

    insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at, source_payment_id)
    values
      (v_payment.salon_id, v_payment.customer_id, 'bonus', v_bonus, v_bonus,
       case when v_days > 0 then now() + make_interval(days => v_days) end,
       p_payment_id)
    returning id into v_bonus_lot;

    perform app.wallet_post(
      v_payment.salon_id, v_payment.customer_id, 'credit_bonus', v_bonus,
      v_bonus_lot, p_payment_id, null, null, null);
  end if;

  return jsonb_build_object(
    'ok', true, 'paid_paise', v_payment.amount_paise, 'bonus_paise', v_bonus,
    'paid_lot_id', v_paid_lot, 'bonus_lot_id', v_bonus_lot);
end;
$$;

comment on function app.wallet_credit_from_payment is
  'Caller 1 of five (RULES 5.2). Credit follows CAPTURE, not authorisation, and is idempotent per payment so a webhook redelivery cannot credit twice. Bonus terms are captured onto the lot at issue: a rule change tomorrow cannot expire money issued today (RULES 5.3.4).';

-- ---------------------------------------------------------------------------
-- Caller 2: spend at checkout
-- ---------------------------------------------------------------------------

create or replace function app.wallet_debit_at_checkout(
  p_salon_id    uuid,
  p_customer_id uuid,
  p_amount_paise bigint,
  p_visit_id    uuid default null,
  p_client_action_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining bigint := p_amount_paise;
  v_take      bigint;
  v_lot       record;
  v_payment   uuid;
  v_available bigint;
begin
  if p_amount_paise <= 0 then
    raise exception 'wallet_debit_at_checkout: nothing to debit';
  end if;

  -- Idempotent on the offline action id, like every other capture (RULES 9.3).
  if p_client_action_id is not null then
    select t.payment_id into v_payment
      from public.wallet_transactions t
     where t.salon_id = p_salon_id
       and t.reason = 'client_action:' || p_client_action_id::text
     limit 1;
    if v_payment is not null then
      return jsonb_build_object('ok', true, 'already', true, 'payment_id', v_payment);
    end if;
  end if;

  -- Lock first. Everything below assumes nobody else is spending this wallet.
  select w.balance_paise into v_available
    from public.wallet_accounts w
   where w.customer_id = p_customer_id
   for update;

  if coalesce(v_available, 0) < p_amount_paise then
    return jsonb_build_object('ok', false, 'reason', 'insufficient_credit',
                              'available_paise', coalesce(v_available, 0));
  end if;

  -- One payment row of method 'wallet', so the visit's settlement is expressed
  -- the same way whatever it was paid with (ARCH 6.3).
  insert into public.payments
    (salon_id, customer_id, visit_id, method, amount_paise, status, captured_at,
     idempotency_key)
  values
    (p_salon_id, p_customer_id, p_visit_id, 'wallet', p_amount_paise, 'captured', now(),
     case when p_client_action_id is not null then p_client_action_id::text end)
  returning id into v_payment;

  -- BONUS FIRST, oldest expiry first; then paid, oldest first. The customer
  -- keeps the credit that cannot expire for as long as possible (RULES 5.3.2).
  for v_lot in
    select l.id, l.kind, l.remaining_paise
      from public.wallet_lots l
     where l.customer_id = p_customer_id
       and l.remaining_paise > 0
       and l.expired_at is null
       and (l.expires_at is null or l.expires_at > now())
     order by case when l.kind = 'bonus' then 0 else 1 end,
              l.expires_at asc nulls last,
              l.created_at asc
     for update
  loop
    exit when v_remaining <= 0;

    v_take := least(v_lot.remaining_paise, v_remaining);

    update public.wallet_lots
       set remaining_paise = remaining_paise - v_take
     where id = v_lot.id;

    insert into public.payment_allocations (salon_id, payment_id, wallet_lot_id, amount_paise)
    values (p_salon_id, v_payment, v_lot.id, v_take);

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    -- The cached balance and the lots disagree. That is a bug, not a customer
    -- problem, and it must not become a silent partial debit.
    raise exception 'wallet_debit_at_checkout: lots do not cover the balance (short by %)',
      v_remaining;
  end if;

  perform app.wallet_post(
    p_salon_id, p_customer_id, 'debit_spend', -p_amount_paise,
    null, v_payment, p_visit_id,
    case when p_client_action_id is not null
         then 'client_action:' || p_client_action_id::text end,
    null);

  return jsonb_build_object('ok', true, 'already', false, 'payment_id', v_payment);
end;
$$;

comment on function app.wallet_debit_at_checkout is
  'Caller 2 of five. Consumes BONUS lots first, oldest expiry first, then paid lots - so the credit that cannot expire is kept longest (RULES 5.3.2). Refuses rather than overdraws, and cannot partially debit: if the lots do not cover the cached balance it raises.';

-- ---------------------------------------------------------------------------
-- Caller 3: a bonus lot expires
-- ---------------------------------------------------------------------------

create or replace function app.wallet_expire_lot(p_lot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lot record;
begin
  select l.id, l.salon_id, l.customer_id, l.kind, l.remaining_paise, l.expires_at, l.expired_at
    into v_lot
    from public.wallet_lots l
   where l.id = p_lot_id
   for update;

  if v_lot.id is null then
    raise exception 'wallet_expire_lot: no such lot';
  end if;

  -- **PAID CREDIT NEVER EXPIRES.** The table refuses to store an expiry on a
  -- paid lot; this refuses to expire one even if someone got an expiry in there
  -- another way. Two independent refusals, on purpose (RULES 5.3.3).
  if v_lot.kind = 'paid' then
    raise exception 'wallet_expire_lot: paid credit never expires' using errcode = '23514';
  end if;

  if v_lot.expired_at is not null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if v_lot.expires_at is null or v_lot.expires_at > now() then
    return jsonb_build_object('ok', false, 'reason', 'not_due');
  end if;
  if v_lot.remaining_paise = 0 then
    update public.wallet_lots set expired_at = now() where id = p_lot_id;
    return jsonb_build_object('ok', true, 'expired_paise', 0);
  end if;

  perform app.wallet_post(
    v_lot.salon_id, v_lot.customer_id, 'debit_expiry', -v_lot.remaining_paise,
    p_lot_id, null, null, 'bonus lot expired', null);

  update public.wallet_lots
     set remaining_paise = 0, expired_at = now()
   where id = p_lot_id;

  return jsonb_build_object('ok', true, 'expired_paise', v_lot.remaining_paise);
end;
$$;

comment on function app.wallet_expire_lot is
  'Caller 3 of five. BONUS ONLY - it raises on a paid lot, which is the second of two independent refusals protecting "paid credit never expires" (the first is the table constraint).';

-- ---------------------------------------------------------------------------
-- Caller 5: the one human path to a balance
-- ---------------------------------------------------------------------------
--
-- Caller 4, app.referral_release_reward, arrives with referrals (M9). It is not
-- stubbed here: a function that moves money before the rule that justifies it
-- exists is worse than a missing one.
--
-- This is the ONLY way a person changes a balance, it is Crayora's alone, and it
-- is audited. No owner or manager path exists anywhere (RULES 5.2, §2).

create or replace function app_admin.wallet_correct(
  p_actor_admin_id uuid,
  p_customer_id    uuid,
  p_amount_paise   bigint,
  p_reason         text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer record;
  v_lot      uuid;
  v_entry    bigint;
  v_remaining bigint;
  v_take     bigint;
  v_lot_row  record;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: a correction needs a reason - it is the audit entry';
  end if;
  if p_amount_paise = 0 then
    raise exception 'app_admin: a zero correction says nothing';
  end if;

  select c.id, c.salon_id into v_customer
    from public.customers c where c.id = p_customer_id;
  if v_customer.id is null then
    raise exception 'app_admin: no such customer';
  end if;

  if p_amount_paise > 0 then
    -- A correction in the customer's favour is credit they did not buy but are
    -- owed. It is PAID-kind, so it never expires: expiring a correction would
    -- be taking back an apology.
    insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
    values
      (v_customer.salon_id, p_customer_id, 'paid', p_amount_paise, p_amount_paise, null)
    returning id into v_lot;
  else
    -- Taking credit back consumes lots in the same order a purchase would, so a
    -- correction and a spend leave the wallet in the same shape.
    v_remaining := -p_amount_paise;
    for v_lot_row in
      select l.id, l.remaining_paise
        from public.wallet_lots l
       where l.customer_id = p_customer_id
         and l.remaining_paise > 0
         and l.expired_at is null
       order by case when l.kind = 'bonus' then 0 else 1 end,
                l.expires_at asc nulls last, l.created_at asc
       for update
    loop
      exit when v_remaining <= 0;
      v_take := least(v_lot_row.remaining_paise, v_remaining);
      update public.wallet_lots set remaining_paise = remaining_paise - v_take
       where id = v_lot_row.id;
      v_remaining := v_remaining - v_take;
    end loop;
  end if;

  v_entry := app.wallet_post(
    v_customer.salon_id, p_customer_id, 'admin_correction', p_amount_paise,
    v_lot, null, null, p_reason, p_actor_admin_id);

  perform app_admin.audit(
    v_customer.salon_id, p_actor_admin_id, 'wallet.corrected', 'wallet_transactions',
    v_entry::text, p_reason, null,
    jsonb_build_object('customer_id', p_customer_id, 'amount_paise', p_amount_paise));

  return v_entry;
end;
$$;

comment on function app_admin.wallet_correct is
  'Caller 5 of five, and the ONLY human path to a balance anywhere in the system (RULES 5.2). Crayora super-admin only, reason required, audited. A positive correction issues PAID-kind credit so it cannot later expire - expiring a correction would be taking back an apology.';

-- ---------------------------------------------------------------------------
-- Grants: none of this belongs to a device
-- ---------------------------------------------------------------------------
--
-- No owner, manager, staff or customer may call any of it. The server does -
-- mark-complete, the payment webhook, the expiry job - and each of those runs as
-- a definer function or the service role.

revoke all on function app.wallet_post(uuid, uuid, public.wallet_entry_kind, bigint, uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function app.wallet_credit_from_payment(uuid) from public, anon, authenticated;
revoke all on function app.wallet_debit_at_checkout(uuid, uuid, bigint, uuid, uuid)
  from public, anon, authenticated;
revoke all on function app.wallet_expire_lot(uuid) from public, anon, authenticated;

grant execute on function app.wallet_credit_from_payment(uuid) to service_role;
grant execute on function app.wallet_debit_at_checkout(uuid, uuid, bigint, uuid, uuid) to service_role;
grant execute on function app.wallet_expire_lot(uuid) to service_role;

select app_admin.close_privileges();
