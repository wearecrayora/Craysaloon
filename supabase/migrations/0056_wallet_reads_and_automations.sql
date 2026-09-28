-- 0056 What the customer sees, and the two automations M7 still owed
--
-- Three things, all of them the tail of M7:
--
--   1. The reads the wallet screen needs. SECURITY INVOKER, so RLS answers -
--      including the restrictive customer_scope policy (0038). A definer
--      function here would be a second, weaker copy of that rule.
--   2. **Automation B** - the receipt. The webhook already credits; what was
--      missing is the event that says a top-up landed, so the dispatcher (M8)
--      can send a receipt without polling the ledger.
--   3. **Automation L** - bonus-lot expiry, and the nudge before it. The sweep
--      is per salon (tenant-sharded, ARCHITECTURE 11.2), and idempotency comes
--      from `wallet_lots.expired_at` for the expiry and from a unique index for
--      the nudge - never from "we only call it once".
--
-- **The schedule is not here.** pg_cron is not installed on this project, and
-- installing it changes infrastructure rather than schema. These functions are
-- correct and gated now; M8 attaches the nightly trigger alongside the rest of
-- the scheduled surface. A function that runs when called is testable; a
-- schedule that has never fired is not.

-- ---------------------------------------------------------------------------
-- 1. The wallet, as its owner sees it
-- ---------------------------------------------------------------------------
--
-- Paid and bonus are reported SEPARATELY (DESIGN 6.2): the summary is one
-- number, the detail is honest. Both come from the lots, not from the cached
-- balance, because the lots are what spending and expiry actually consume.

create or replace function public.my_wallet()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'balance_paise', coalesce(
      (select a.balance_paise from public.wallet_accounts a
        where a.customer_id = app.current_customer_id()), 0),
    'paid_paise', coalesce(
      (select sum(l.remaining_paise) from public.wallet_lots l
        where l.customer_id = app.current_customer_id()
          and l.kind = 'paid' and l.expired_at is null), 0),
    'bonus_paise', coalesce(
      (select sum(l.remaining_paise) from public.wallet_lots l
        where l.customer_id = app.current_customer_id()
          and l.kind = 'bonus' and l.expired_at is null), 0),
    -- The NEXT bonus to go, so the screen can say "₹200 expires on the 14th"
    -- rather than a total with no date attached to it.
    'next_bonus_expiry', (
      select min(l.expires_at) from public.wallet_lots l
       where l.customer_id = app.current_customer_id()
         and l.kind = 'bonus' and l.expired_at is null
         and l.remaining_paise > 0 and l.expires_at is not null),
    'next_bonus_paise', coalesce((
      select l.remaining_paise from public.wallet_lots l
       where l.customer_id = app.current_customer_id()
         and l.kind = 'bonus' and l.expired_at is null
         and l.remaining_paise > 0 and l.expires_at is not null
       order by l.expires_at
       limit 1), 0)
  )
$$;

comment on function public.my_wallet is
  'Balance with paid and bonus shown SEPARATELY (DESIGN 6.2), read from the lots rather than the cached balance. SECURITY INVOKER: the restrictive customer_scope policy (0038) is what keeps this to one customer, not a second copy of the rule written here.';

revoke all on function public.my_wallet() from public, anon;
grant execute on function public.my_wallet() to authenticated;

-- Keyset, like every other list in this system (0039): an offset that a
-- customer can page past is an offset that gets slower as they spend.
create or replace function public.my_wallet_history(
  p_limit  integer default 20,
  p_before bigint default null
)
returns table (
  id            bigint,
  kind          text,
  amount_paise  bigint,
  balance_after bigint,
  reason        text,
  created_at    timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select t.id, t.kind::text, t.amount_paise, t.balance_after, t.reason, t.created_at
    from public.wallet_transactions t
   where t.customer_id = app.current_customer_id()
     and (p_before is null or t.id < p_before)
   order by t.id desc
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;

comment on function public.my_wallet_history is
  'The customer''s own ledger, newest first, keyset-paged. Append-only, so a page can never shift under the reader.';

revoke all on function public.my_wallet_history(integer, bigint) from public, anon;
grant execute on function public.my_wallet_history(integer, bigint) to authenticated;

create index if not exists wallet_transactions_customer_recent_idx
  on public.wallet_transactions (salon_id, customer_id, id desc);

-- ---------------------------------------------------------------------------
-- 2. Automation B - the receipt event
-- ---------------------------------------------------------------------------
--
-- 0048's body, with one addition at the end. The function is already idempotent
-- per payment - a redelivered webhook returns early - so the event inherits that
-- guard rather than needing its own: one credit, one receipt.
--
-- The event carries the numbers the receipt needs. The dispatcher must not have
-- to re-derive "how much bonus did they get" from the ledger to write a
-- sentence; an automation that reconstructs its own trigger is an automation
-- that will one day reconstruct it differently.

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
  'Caller 1 of five (RULES 5.2). Credit follows CAPTURE, not authorisation, and is idempotent per payment so a webhook redelivery cannot credit twice. Bonus terms are captured onto the lot at issue: a rule change tomorrow cannot expire money issued today (RULES 5.3.4). Since 0056 it also emits wallet.topped_up in the same transaction - Automation B, the receipt.';

-- ---------------------------------------------------------------------------
-- 3. Automation L - expiry, and the warning before it
-- ---------------------------------------------------------------------------

-- The nudge must not repeat nightly for a fortnight. One warning per lot, and
-- the database is what says so.
create unique index if not exists domain_events_bonus_expiring_once_idx
  on public.domain_events (aggregate_id)
  where type = 'wallet.bonus_expiring';

comment on index public.domain_events_bonus_expiring_once_idx is
  'Automation L''s idempotency guard: one expiry warning per lot, ever. Without it a nightly sweep warns the same customer every night for a fortnight, which is how a helpful message becomes spam.';

create or replace function app.expire_due_bonus_lots(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lots   uuid[];
  v_lot    uuid;
  v_count  integer := 0;
  v_paise  bigint := 0;
  v_result jsonb;
begin
  -- Collected FIRST, then expired. app.wallet_expire_lot writes, and a volatile
  -- function evaluated inside a WHERE runs once per row the planner scans - a
  -- mistake this codebase has already made once, in wallet_correct.
  select coalesce(array_agg(l.id), '{}')
    into v_lots
    from public.wallet_lots l
   where l.salon_id = p_salon_id
     and l.kind = 'bonus'
     and l.expired_at is null
     and l.expires_at is not null
     and l.expires_at <= now();

  foreach v_lot in array v_lots loop
    v_result := app.wallet_expire_lot(v_lot);
    if v_result ->> 'ok' = 'true' and coalesce(v_result ->> 'already', 'false') <> 'true' then
      v_count := v_count + 1;
      v_paise := v_paise + coalesce((v_result ->> 'expired_paise')::bigint, 0);
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'lots_expired', v_count, 'paise_expired', v_paise);
end;
$$;

comment on function app.expire_due_bonus_lots is
  'Automation L, one salon at a time (tenant-sharded, ARCHITECTURE 11.2: a single bad tenant must not stall the platform). Idempotent through wallet_lots.expired_at, so a double run expires nothing twice. Paid lots are not selected, and wallet_expire_lot would refuse them anyway.';

create or replace function app.nudge_expiring_bonus(
  p_salon_id uuid,
  p_days     integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- The warning is worth sending only while the money can still be spent, so
  -- a lot with nothing left in it is skipped: "your ₹0 is expiring" is noise.
  with due as (
    select l.id, l.customer_id, l.remaining_paise, l.expires_at
      from public.wallet_lots l
     where l.salon_id = p_salon_id
       and l.kind = 'bonus'
       and l.expired_at is null
       and l.remaining_paise > 0
       and l.expires_at is not null
       and l.expires_at <= now() + make_interval(days => greatest(coalesce(p_days, 7), 1))
       and l.expires_at > now()
  ), inserted as (
    insert into public.domain_events (salon_id, type, aggregate_id, payload)
    select p_salon_id, 'wallet.bonus_expiring', d.id,
           jsonb_build_object(
             'customer_id', d.customer_id,
             'amount_paise', d.remaining_paise,
             'expires_at', d.expires_at)
      from due d
    -- The unique index is the guard; this turns a redelivery into a no-op
    -- rather than an error.
    on conflict (aggregate_id) where type = 'wallet.bonus_expiring' do nothing
    returning 1
  )
  select count(*)::integer into v_count from inserted;

  return jsonb_build_object('ok', true, 'nudged', v_count);
end;
$$;

comment on function app.nudge_expiring_bonus is
  'Automation L''s second half: warn before bonus credit expires, once per lot ever. Only lots with money still in them - "your zero rupees are expiring" is noise, and noise is what gets a salon''s messages muted.';

select app_admin.close_privileges();
