-- 0087 M11: the subscription lifecycle, read-only grace, retention notices,
-- and plan entitlements.
--
-- PRD 14: past due -> 7-day grace, READ-ONLY -> suspended -> 90 days retained,
-- with notices to the owner at day 60 and day 80 -> purge. Read-only grace is
-- enforced IN THE DATABASE: a lapsed tenant keeps SELECT and loses writes.
--
-- HOW (the same shape as 0033's messaging block)
--
-- The billing state is a CONDITION computed from dates, not an event fired by a
-- job. `renews_at` is the moment the paid period ends; everything else follows
-- from it:
--
--     renews_at            -> grace      (read-only)
--     renews_at + 7 days   -> suspended  (read-only, retained)
--     suspended + 60 days  -> notice
--     suspended + 80 days  -> notice
--     suspended + 90 days  -> purge_due  (flagged; the purge itself is M12)
--
-- So writes stop at exactly the deadline, with no scheduler that can fail to
-- run, and they come back the moment a payment moves `renews_at`.
--
-- Why billing does NOT flip `salons.status`: RULES 6.3 - nothing but a
-- deliberate human action may make a salon active, "no payment event, no
-- timer". A job that suspended on a date and a payment that reactivated would
-- be exactly that. `salons.status` stays the operator's decision (setup,
-- active, and a manual grace or suspension); billing is a separate condition
-- that both gates apply.
--
-- What stays open while lapsed, on purpose:
--   * reading - a customer can see the money they paid (PRD 16A);
--   * logging in, for people the salon already has - an owner who cannot log
--     in cannot see why the app stopped. Only a NEW customer is refused;
--   * consent withdrawal (DPDP; 0033 keeps it outside salon_writable);
--   * Razorpay's webhook - a captured payment has already moved money.
--
-- Nightly (Automation I) records each notice ONCE, when it falls due, for the
-- console. There is no owner channel yet (owner push registration is open), so
-- a notice is a to-do for Crayora to call the owner, and the owner's own app
-- shows the state on every open.

-- ---------------------------------------------------------------------------
-- Plans and the price agreed with this salon
-- ---------------------------------------------------------------------------

alter table public.subscriptions
  add column monthly_price_paise bigint not null default 0
    check (monthly_price_paise >= 0);

alter table public.subscriptions
  add constraint subscriptions_plan_known check (plan in ('starter', 'growth', 'pro'));

comment on column public.subscriptions.monthly_price_paise is
  'What THIS salon agreed to pay per month (0087). Plans are proposals until the pilot (PRD 14); the agreed number is what MRR is computed from.';

comment on column public.subscriptions.renews_at is
  'The end of the paid period (0087). The billing state - active, grace, suspended, purge_due - is computed from it by app.billing_state; nothing else stores it.';

-- ---------------------------------------------------------------------------
-- Subscription payments: Crayora's own revenue, collected offline
-- ---------------------------------------------------------------------------

create table public.subscription_payments (
  id            bigint generated always as identity primary key,
  salon_id      uuid not null references public.salons(id) on delete restrict,
  amount_paise  bigint not null check (amount_paise > 0),
  months        integer not null check (months between 1 and 24),
  period_start  timestamptz not null,
  period_end    timestamptz not null check (period_end > period_start),
  -- Collected outside the system, like the setup fee: the reference is the
  -- only evidence it was collected at all (RULES 6.4).
  reference     text not null check (length(btrim(reference)) > 0),
  paid_on       date not null,
  recorded_by   uuid not null references public.platform_admins(id),
  created_at    timestamptz not null default now()
);

create index subscription_payments_salon on public.subscription_payments (salon_id, created_at desc);

alter table public.subscription_payments enable row level security;
alter table public.subscription_payments force row level security;
revoke all on public.subscription_payments from public, anon, authenticated;

comment on table public.subscription_payments is
  'Crayora''s subscription revenue, recorded by an operator (0087). Append-only. No policies: only app_admin functions read or write it.';

create or replace function app.subscription_payments_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'subscription_payments is append-only - a mistake is corrected by a new row'
    using errcode = '42501';
end;
$$;

create trigger subscription_payments_append_only
  before update or delete on public.subscription_payments
  for each row execute function app.subscription_payments_append_only();

revoke all on function app.subscription_payments_append_only() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Notices: each fires once per lapse
-- ---------------------------------------------------------------------------

create table public.billing_notices (
  salon_id        uuid not null references public.salons(id) on delete cascade,
  kind            text not null check (kind in
                    ('grace_started', 'suspended', 'retention_60', 'retention_80', 'purge_due')),
  -- Which lapse this belongs to: a salon that pays and lapses again gets a
  -- fresh set of notices, and a replayed night gets none.
  cycle_renews_at timestamptz not null,
  due_at          timestamptz not null,
  created_at      timestamptz not null default now(),
  primary key (salon_id, kind, cycle_renews_at)
);

alter table public.billing_notices enable row level security;
alter table public.billing_notices force row level security;
revoke all on public.billing_notices from public, anon, authenticated;

comment on table public.billing_notices is
  'When each lapse notice fell due (0087, PRD 14). One row per salon, kind and lapse. No policies: the console reads it through app_admin.billing_overview.';

-- ---------------------------------------------------------------------------
-- The state, and its dates
-- ---------------------------------------------------------------------------

create or replace function app.billing_state(p_salon uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when s.renews_at is null                                   then 'unbilled'
           when now() <  s.renews_at                                  then 'active'
           when now() <  s.renews_at + interval '7 days'              then 'grace'
           when now() <  s.renews_at + interval '7 days' + interval '90 days' then 'suspended'
           else 'purge_due'
         end
    from public.subscriptions s
   where s.salon_id = p_salon
  union all
  select 'unbilled'
   where not exists (select 1 from public.subscriptions s where s.salon_id = p_salon)
  limit 1
$$;

comment on function app.billing_state(uuid) is
  'unbilled | active | grace | suspended | purge_due, from renews_at alone (0087). Grace starts at renews_at, suspension 7 days later, purge is due 90 days after that.';

create or replace function app.billing_open(p_salon uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.billing_state(p_salon) in ('unbilled', 'active')
$$;

create or replace function app.billing_dates(p_salon uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'state',          app.billing_state(p_salon),
           'renews_at',      s.renews_at,
           'grace_ends_at',  s.renews_at + interval '7 days',
           'notice_60_at',   s.renews_at + interval '7 days' + interval '60 days',
           'notice_80_at',   s.renews_at + interval '7 days' + interval '80 days',
           'purge_after',    s.renews_at + interval '7 days' + interval '90 days')
    from public.subscriptions s
   where s.salon_id = p_salon
$$;

revoke all on function app.billing_state(uuid) from public, anon, authenticated;
revoke all on function app.billing_open(uuid) from public, anon, authenticated;
revoke all on function app.billing_dates(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The gates
-- ---------------------------------------------------------------------------

-- Open for LOGIN: what salon_writable meant before 0087 - active, not blocked.
create or replace function app.salon_open(p_salon uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.salons s where s.id = p_salon and s.status = 'active')
     and not app.salon_blocked(p_salon)
$$;

revoke all on function app.salon_open(uuid) from public, anon, authenticated;

-- Writable: open AND paid up. Every INSERT/UPDATE policy and every writing RPC
-- already calls this one function, which is why read-only grace is one line.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('app.salon_writable(uuid)'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$  and not app.salon_blocked(p_salon)$x$,
    $x$  and not app.salon_blocked(p_salon)
  -- 0087: a lapsed subscription is read-only (PRD 14).
  and app.billing_open(p_salon)$x$);
  if v_new = v_def then
    raise exception '0087: salon_writable did not have the expected shape';
  end if;
  execute v_new;
end;
$$;

-- Login: existing people log in and read; only a NEW customer is refused.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p
   where p.proname = 'otp_finish_login' and p.pronamespace = 'public'::regnamespace;

  v_new := replace(v_def,
    $x$  if not app.salon_writable(v_salon) then$x$,
    $x$  -- 0087: open, not writable - a lapsed salon's own people still log in.
  if not app.salon_open(v_salon) then$x$);

  v_new := replace(v_new,
    $x$  -- A first join. Everything below is one transaction.$x$,
    $x$  -- 0087: nobody NEW joins a salon whose subscription has lapsed. A first
  -- join writes a customer, and a lapsed salon is read-only.
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  -- A first join. Everything below is one transaction.$x$);

  if v_new = v_def or v_new !~ 'salon_open' or v_new !~ 'nobody NEW joins' then
    raise exception '0087: otp_finish_login did not have the expected shape';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Automation I: record the notices as they fall due
-- ---------------------------------------------------------------------------

create or replace function app.run_billing_lifecycle()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub     record;
  v_state   text;
  v_suspend timestamptz;
  v_kind    text;
  v_due     timestamptz;
  v_new     integer := 0;
  v_lapsed  integer := 0;
begin
  for v_sub in
    select s.salon_id, s.renews_at, s.status
      from public.subscriptions s
      join public.salons sa on sa.id = s.salon_id
     where s.renews_at is not null
       and sa.status <> 'setup'
  loop
    v_state := app.billing_state(v_sub.salon_id);

    -- The subscription's own status is a label for the console, kept in step
    -- with the dates. It gates nothing - app.billing_open does.
    if v_state in ('grace', 'suspended', 'purge_due') then
      v_lapsed := v_lapsed + 1;
      update public.subscriptions
         set status = 'past_due', past_due_since = v_sub.renews_at, updated_at = now()
       where salon_id = v_sub.salon_id
         and (status <> 'past_due' or past_due_since is distinct from v_sub.renews_at);
    else
      update public.subscriptions
         set status = 'active', past_due_since = null, updated_at = now()
       where salon_id = v_sub.salon_id and status = 'past_due';
      continue;
    end if;

    v_suspend := v_sub.renews_at + interval '7 days';

    foreach v_kind in array
      array['grace_started', 'suspended', 'retention_60', 'retention_80', 'purge_due']
    loop
      v_due := case v_kind
                 when 'grace_started' then v_sub.renews_at
                 when 'suspended'     then v_suspend
                 when 'retention_60'  then v_suspend + interval '60 days'
                 when 'retention_80'  then v_suspend + interval '80 days'
                 else                      v_suspend + interval '90 days'
               end;
      exit when v_due > now();

      insert into public.billing_notices (salon_id, kind, cycle_renews_at, due_at)
      values (v_sub.salon_id, v_kind, v_sub.renews_at, v_due)
      on conflict (salon_id, kind, cycle_renews_at) do nothing;

      if found then
        v_new := v_new + 1;
        insert into public.domain_events (salon_id, type, aggregate_id, payload)
        values (v_sub.salon_id, 'billing.' || v_kind, v_sub.salon_id,
                jsonb_build_object('renews_at', v_sub.renews_at, 'due_at', v_due));
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'lapsed', v_lapsed, 'notices', v_new);
end;
$$;

revoke all on function app.run_billing_lifecycle() from public, anon, authenticated;

comment on function app.run_billing_lifecycle() is
  'Automation I (0087): records each lapse notice once when it falls due, and keeps subscriptions.status in step as a label. Gates nothing - the dates do. Called by app.run_nightly.';

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('app.run_nightly()'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$  return jsonb_build_object('ok', true, 'salons_drifted', v_drifted, 'salons_failed', v_failed);$x$,
    $x$  -- Automation I (0087). Outside the per-salon loop: it walks every
  -- subscription, including salons the loop above skips.
  return jsonb_build_object('ok', true, 'salons_drifted', v_drifted, 'salons_failed', v_failed,
                            'billing', app.run_billing_lifecycle());$x$);
  if v_new = v_def then
    raise exception '0087: run_nightly did not have the expected shape';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Plan entitlements, checked server-side
-- ---------------------------------------------------------------------------
--
-- ARCHITECTURE 13.2: plans differ on FEATURES, checked in the RPC layer and
-- mirrored for the UI. Which plan carries which feature is PRD 21 Q-A, and it
-- is still open until the pilot. So every plan carries every built feature
-- today - the mechanism is real and gated, and setting the tiers is a one-line
-- change here, not a build. A per-salon feature flag overrides the plan either
-- way (a comp, or switching something off).

create or replace function app.plan_features(p_plan text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_plan
           when 'starter' then array['dashboard', 'referrals']
           when 'growth'  then array['dashboard', 'referrals']
           when 'pro'     then array['dashboard', 'referrals']
           else array[]::text[]
         end
$$;

create or replace function app.salon_has_feature(p_salon uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select f.enabled from public.feature_flags f
      where f.salon_id = p_salon and f.flag = p_feature),
    (select p_feature = any(app.plan_features(s.plan))
       from public.subscriptions s where s.salon_id = p_salon),
    false)
$$;

revoke all on function app.plan_features(text) from public, anon, authenticated;
revoke all on function app.salon_has_feature(uuid, text) from public, anon, authenticated;

-- For the UI: which features this salon has. A courtesy - the server gate below
-- is the control.
create or replace function public.my_features()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(f order by f), array[]::text[])
    from unnest(array['dashboard', 'referrals']) as f
   where app.current_salon_id() is not null
     and app.salon_has_feature(app.current_salon_id(), f)
$$;

revoke all on function public.my_features() from public, anon;
grant execute on function public.my_features() to authenticated;

-- The gates themselves.
do $$
declare
  v_def text;
  v_new text;
begin
  -- The owner's dashboard.
  select pg_get_functiondef('public.owner_dashboard()'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$    raise exception 'owner_dashboard: owners and managers only' using errcode = '42501';
  end if;$x$,
    $x$    raise exception 'owner_dashboard: owners and managers only' using errcode = '42501';
  end if;

  -- 0087: a plan feature, checked here - the hidden button is only a courtesy.
  if not app.salon_has_feature(v_salon, 'dashboard') then
    raise exception 'not_in_plan: dashboard';
  end if;$x$);
  if v_new = v_def then raise exception '0087: owner_dashboard shape'; end if;
  execute v_new;

  -- A customer's own referral code.
  select pg_get_functiondef('public.my_referral_code()'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$    raise exception 'my_referral_code: no customer in this session' using errcode = '42501';
  end if;$x$,
    $x$    raise exception 'my_referral_code: no customer in this session' using errcode = '42501';
  end if;

  if not app.salon_has_feature(v_salon, 'referrals') then
    raise exception 'not_in_plan: referrals';
  end if;$x$);
  if v_new = v_def then raise exception '0087: my_referral_code shape'; end if;
  execute v_new;

  -- Claiming a friend's code.
  select pg_get_functiondef('public.claim_referral(text)'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$    raise exception 'claim_referral: no customer in this session' using errcode = '42501';
  end if;$x$,
    $x$    raise exception 'claim_referral: no customer in this session' using errcode = '42501';
  end if;

  if not app.salon_has_feature(v_salon, 'referrals') then
    return jsonb_build_object('ok', false, 'reason', 'not_in_plan');
  end if;$x$);
  if v_new = v_def then raise exception '0087: claim_referral shape'; end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- What the salon's own staff see
-- ---------------------------------------------------------------------------

create or replace function public.my_salon_billing()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_role  text := app.current_app_role();
  v_out   jsonb;
begin
  if v_salon is null or v_role not in ('owner', 'manager', 'staff') then
    raise exception 'my_salon_billing: salon staff only' using errcode = '42501';
  end if;

  v_out := app.billing_dates(v_salon)
           || jsonb_build_object('read_only', not app.salon_writable(v_salon));

  -- What the salon pays is the owner's business, not the stylist's.
  if v_role in ('owner', 'manager') then
    v_out := v_out || (
      select jsonb_build_object('plan', s.plan, 'monthly_price_paise', s.monthly_price_paise)
        from public.subscriptions s where s.salon_id = v_salon);
  end if;

  return coalesce(v_out, jsonb_build_object('state', 'unbilled', 'read_only', false));
end;
$$;

revoke all on function public.my_salon_billing() from public, anon;
grant execute on function public.my_salon_billing() to authenticated;

-- ---------------------------------------------------------------------------
-- The console
-- ---------------------------------------------------------------------------

-- Activation needs the commitment first: "no free trial - the setup fee is the
-- commitment" (PRD 14). Waived is a deliberate, recorded exception.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(
           'app_admin.activate_salon(uuid, uuid, text)'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$  -- DPDP ss.5 and 13:$x$,
    $x$  -- PRD 14: there is no free trial; the setup fee is the commitment (0087).
  if not exists (select 1 from public.subscriptions s
                  where s.salon_id = p_salon_id
                    and s.setup_fee_status in ('paid', 'waived')) then
    raise exception
      'app_admin: record the setup fee (paid, or waived with a reason) before '
      'activating - there is no free trial';
  end if;

  -- DPDP ss.5 and 13:$x$);
  if v_new = v_def then raise exception '0087: activate_salon shape'; end if;
  execute v_new;
end;
$$;

-- The setup fee now carries its AMOUNT (RULES 6.4: amount, date, reference).
-- Added last so every existing positional call keeps working.
drop function app_admin.record_setup_fee(uuid, uuid, text, text, date);

create function app_admin.record_setup_fee(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_status         text,
  p_reference      text default null,
  p_paid_on        date default null,
  p_amount_paise   bigint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_status not in ('unpaid', 'paid', 'waived') then
    raise exception 'app_admin: setup fee status must be unpaid, paid or waived';
  end if;

  -- The money moved outside the system, so the reference is the only evidence.
  if p_status = 'paid' and coalesce(btrim(p_reference), '') = '' then
    raise exception
      'app_admin: a paid setup fee needs a reference - it was collected offline '
      'and this is the only record that it was collected at all';
  end if;

  -- A waiver is a decision somebody made; say why.
  if p_status = 'waived' and coalesce(btrim(p_reference), '') = '' then
    raise exception 'app_admin: a waived setup fee needs a reason';
  end if;

  if p_amount_paise is not null and p_amount_paise < 0 then
    raise exception 'app_admin: the setup fee cannot be negative';
  end if;

  select jsonb_build_object(
           'setup_fee_status', s.setup_fee_status,
           'setup_fee_paise', s.setup_fee_paise,
           'setup_fee_reference', s.setup_fee_reference,
           'setup_fee_paid_on', s.setup_fee_paid_on)
    into v_before
    from public.subscriptions s where s.salon_id = p_salon_id;

  if v_before is null then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;

  update public.subscriptions
     set setup_fee_status    = p_status::public.setup_fee_status,
         setup_fee_paise     = coalesce(p_amount_paise, setup_fee_paise),
         setup_fee_reference = p_reference,
         setup_fee_paid_on   = case when p_status = 'paid'
                                    then coalesce(p_paid_on, current_date) end,
         updated_at          = now()
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.setup_fee_recorded', 'subscriptions',
    p_salon_id::text, p_reference, v_before,
    jsonb_build_object('setup_fee_status', p_status,
                       'setup_fee_paise', p_amount_paise,
                       'setup_fee_reference', p_reference));
end;
$$;

-- Plan, price and the first due date.
create or replace function app_admin.set_billing(
  p_actor_admin_id      uuid,
  p_salon_id            uuid,
  p_plan                text,
  p_monthly_price_paise bigint,
  p_billing_starts_on   date,
  p_reason              text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
  v_tz     text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_plan not in ('starter', 'growth', 'pro') then
    raise exception 'app_admin: plan must be starter, growth or pro';
  end if;
  if p_monthly_price_paise is null or p_monthly_price_paise < 0 then
    raise exception 'app_admin: the monthly price cannot be negative';
  end if;

  select to_jsonb(s) - 'messages_used_this_cycle', sa.timezone
    into v_before, v_tz
    from public.subscriptions s join public.salons sa on sa.id = s.salon_id
   where s.salon_id = p_salon_id
   for update of s;

  if v_before is null then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;

  update public.subscriptions
     set plan                = p_plan,
         monthly_price_paise = p_monthly_price_paise,
         billing_starts_on   = coalesce(p_billing_starts_on, billing_starts_on),
         -- The first month is due on the billing start date, at the start of
         -- the salon's own day. Set once: after that only a payment or an
         -- extension moves it, so changing the plan never forgives a debt.
         renews_at           = coalesce(renews_at,
                                 case when p_billing_starts_on is not null
                                      then (p_billing_starts_on::timestamp at time zone v_tz) end),
         updated_at          = now()
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'subscription.billing_set', 'subscriptions',
    p_salon_id::text, p_reason, v_before,
    jsonb_build_object('plan', p_plan, 'monthly_price_paise', p_monthly_price_paise,
                       'billing_starts_on', p_billing_starts_on));

  return app.billing_dates(p_salon_id);
end;
$$;

-- A month (or more) paid, offline.
create or replace function app_admin.record_subscription_payment(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_amount_paise   bigint,
  p_months         integer,
  p_reference      text,
  p_paid_on        date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_renews timestamptz;
  v_end    timestamptz;
  v_id     bigint;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reference), '') = '' then
    raise exception
      'app_admin: a subscription payment needs a reference - it was collected '
      'offline and this is the only record that it was collected at all';
  end if;
  if p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'app_admin: the amount must be more than zero';
  end if;
  if p_months is null or p_months not between 1 and 24 then
    raise exception 'app_admin: a payment covers 1 to 24 months';
  end if;

  select renews_at into v_renews
    from public.subscriptions where salon_id = p_salon_id for update;

  if not found then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;
  if v_renews is null then
    raise exception 'app_admin: set the plan and billing start date before recording a payment';
  end if;

  -- The period runs ON from where the last one ended, even when that was weeks
  -- ago: a salon that pays late pays for the time it had, and the lapse ends
  -- only if the payment actually covers today.
  v_end := v_renews + make_interval(months => p_months);

  insert into public.subscription_payments
    (salon_id, amount_paise, months, period_start, period_end, reference, paid_on, recorded_by)
  values
    (p_salon_id, p_amount_paise, p_months, v_renews, v_end, btrim(p_reference),
     coalesce(p_paid_on, current_date), p_actor_admin_id)
  returning id into v_id;

  update public.subscriptions
     set renews_at = v_end, updated_at = now()
   where salon_id = p_salon_id;

  perform app.run_billing_lifecycle();

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'subscription.payment_recorded', 'subscription_payments',
    v_id::text, p_reference, jsonb_build_object('renews_at', v_renews),
    jsonb_build_object('renews_at', v_end, 'amount_paise', p_amount_paise,
                       'months', p_months));

  return app.billing_dates(p_salon_id);
end;
$$;

-- Comp or extend: a deliberate, reasoned gift of time.
create or replace function app_admin.extend_subscription(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_days           integer,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_renews timestamptz;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: extending a subscription needs a reason - it is revenue given away';
  end if;
  if p_days is null or p_days not between 1 and 90 then
    raise exception 'app_admin: an extension is 1 to 90 days';
  end if;

  select renews_at into v_renews
    from public.subscriptions where salon_id = p_salon_id for update;
  if v_renews is null then
    raise exception 'app_admin: this salon has no billing yet';
  end if;

  update public.subscriptions
     set renews_at = v_renews + make_interval(days => p_days), updated_at = now()
   where salon_id = p_salon_id;

  perform app.run_billing_lifecycle();

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'subscription.extended', 'subscriptions',
    p_salon_id::text, p_reason, jsonb_build_object('renews_at', v_renews),
    jsonb_build_object('renews_at', v_renews + make_interval(days => p_days), 'days', p_days));

  return app.billing_dates(p_salon_id);
end;
$$;

-- A per-salon override of the plan. NULL clears it back to the plan.
create or replace function app_admin.set_feature_flag(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_flag           text,
  p_enabled        boolean,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before boolean;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_flag not in ('dashboard', 'referrals') then
    raise exception 'app_admin: unknown feature %', p_flag;
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a feature override needs a reason';
  end if;

  select enabled into v_before from public.feature_flags
   where salon_id = p_salon_id and flag = p_flag;

  if p_enabled is null then
    delete from public.feature_flags where salon_id = p_salon_id and flag = p_flag;
  else
    insert into public.feature_flags (salon_id, flag, enabled, updated_at)
    values (p_salon_id, p_flag, p_enabled, now())
    on conflict (salon_id, flag) do update set enabled = excluded.enabled, updated_at = now();
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.feature_flag_set', 'feature_flags',
    p_salon_id::text || ':' || p_flag, p_reason,
    jsonb_build_object('enabled', v_before), jsonb_build_object('enabled', p_enabled));
end;
$$;

-- Read-only: everything the billing page shows, in one call.
create or replace function app_admin.billing_overview(p_actor_admin_id uuid, p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  return (
    select jsonb_build_object(
      'subscription', jsonb_build_object(
          'plan', s.plan,
          'monthly_price_paise', s.monthly_price_paise,
          'billing_starts_on', s.billing_starts_on,
          'setup_fee_status', s.setup_fee_status,
          'setup_fee_paise', s.setup_fee_paise,
          'setup_fee_reference', s.setup_fee_reference,
          'setup_fee_paid_on', s.setup_fee_paid_on),
      'dates', app.billing_dates(p_salon_id),
      'writable', app.salon_writable(p_salon_id),
      'payments', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'id', p.id, 'amount_paise', p.amount_paise, 'months', p.months,
                   'period_start', p.period_start, 'period_end', p.period_end,
                   'reference', p.reference, 'paid_on', p.paid_on,
                   'recorded_by', a.name) order by p.created_at desc)
            from public.subscription_payments p
            left join public.platform_admins a on a.id = p.recorded_by
           where p.salon_id = p_salon_id), '[]'::jsonb),
      'notices', coalesce((
          select jsonb_agg(jsonb_build_object('kind', n.kind, 'due_at', n.due_at,
                                              'cycle_renews_at', n.cycle_renews_at)
                           order by n.due_at desc)
            from public.billing_notices n where n.salon_id = p_salon_id), '[]'::jsonb),
      'features', (
          select jsonb_object_agg(f, jsonb_build_object(
                   'plan', f = any(app.plan_features(s.plan)),
                   'override', (select ff.enabled from public.feature_flags ff
                                 where ff.salon_id = p_salon_id and ff.flag = f),
                   'effective', app.salon_has_feature(p_salon_id, f)))
            from unnest(array['dashboard', 'referrals']) as f))
      from public.subscriptions s
     where s.salon_id = p_salon_id);
end;
$$;

-- Read-only: the platform's numbers (K14).
create or replace function app_admin.platform_metrics(p_actor_admin_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_out jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  with billed as (
    select s.salon_id, s.monthly_price_paise, s.renews_at, app.billing_state(s.salon_id) as state
      from public.subscriptions s
      join public.salons sa on sa.id = s.salon_id
     where sa.status <> 'setup'
  ),
  first_bind as (
    select sa.id, sa.activated_at,
           (select min(b.occurred_at) from public.binding_events b
             where b.to_salon_id = sa.id and b.kind = 'bind') as first_at
      from public.salons sa
     where sa.activated_at is not null
  ),
  sends as (
    select d.channel::text as channel, count(*) as n
      from public.notification_deliveries d
     where d.created_at > now() - interval '30 days'
     group by d.channel
  )
  select jsonb_build_object(
    'salons', (select jsonb_object_agg(status, n) from
                (select sa.status::text as status, count(*) as n
                   from public.salons sa group by sa.status) x),
    'billing', (select jsonb_object_agg(state, n) from
                 (select state, count(*) as n from billed group by state) x),
    -- Only salons paid up today count towards recurring revenue.
    'mrr_paise', (select coalesce(sum(monthly_price_paise), 0) from billed where state = 'active'),
    'activations_30d', (select count(*) from public.salons sa
                         where sa.activated_at > now() - interval '30 days'),
    -- Churn: a salon whose grace ended - it became suspended - in the last 30 days.
    'churned_30d', (select count(*) from billed
                     where state in ('suspended', 'purge_due')
                       and renews_at + interval '7 days' > now() - interval '30 days'),
    'subscription_revenue_30d_paise', (select coalesce(sum(p.amount_paise), 0)
                                         from public.subscription_payments p
                                        where p.paid_on > current_date - 30),
    'setup_fees_paise', (select coalesce(sum(s.setup_fee_paise), 0) from public.subscriptions s
                          where s.setup_fee_status = 'paid'),
    'sends_30d', coalesce((select jsonb_object_agg(channel, n) from sends), '{}'::jsonb),
    'median_hours_to_first_bind', (
        select round((percentile_cont(0.5) within group (
                 order by extract(epoch from first_at - activated_at) / 3600.0))::numeric, 1)
          from first_bind where first_at is not null),
    'salons_never_bound', (select count(*) from first_bind where first_at is null)
  ) into v_out;

  return v_out;
end;
$$;

select app_admin.close_privileges();
