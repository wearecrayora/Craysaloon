-- RELEASE GATE: the subscription lifecycle (M11, 0087)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PHASES M11 done-when, asserted against the functions that run:
--   * read-only grace is enforced IN THE DATABASE - a lapsed salon keeps SELECT
--     and loses writes, at exactly the due date, with no job involved
--   * retention notices fire at day 60 and day 80 of suspension, once each
--   * plan entitlements are checked server-side
-- and what must stay open while lapsed: the salon's own people logging in,
-- customers reading their money, consent withdrawal, and Razorpay's webhook.
-- Plus RULES 6.3: billing never flips a salon's status - a payment does not
-- activate, a date does not suspend.

select plan(36);

insert into auth.users (id) values
  ('77777777-aaaa-4000-8000-00000000000a'),   -- operator
  ('77777777-aaaa-4000-8000-00000000000c'),   -- customer
  ('77777777-aaaa-4000-8000-00000000000d'),   -- a would-be new customer
  ('77777777-aaaa-4000-8000-00000000000f');   -- owner

insert into public.platform_admins (id, email, name, is_super, active)
values ('77777777-aaaa-4000-8000-00000000000a', 'billing@crayora.test', 'Billing Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           wallet_rule, activated_by, activated_at,
                           grievance_name, grievance_email)
values
  ('77777777-0000-4000-8000-000000000001', 'Billed Salon Ltd', 'Billed Salon', 'CRAY-BRNGAA',
   'active', 'Asia/Kolkata',
   '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 50000}'::jsonb,
   '77777777-aaaa-4000-8000-00000000000a', now(), 'Owner', 'owner@billed.test'),
  -- A salon still in setup, for the activation rule.
  ('77777777-0000-4000-8000-000000000002', 'New Salon Ltd', 'New Salon', 'CRAY-BRNGSB',
   'setup', 'Asia/Kolkata', default, null, null, 'Owner', 'owner@new.test');

insert into public.subscriptions (salon_id, plan, renews_at, monthly_price_paise)
values ('77777777-0000-4000-8000-000000000001', 'starter', now() + interval '10 days', 79900),
       ('77777777-0000-4000-8000-000000000002', 'starter', null, 0);

insert into public.users (id, salon_id, name, role, phone, phone_hash, auth_user_id, active)
values ('77777777-2222-4000-8000-00000000000f', '77777777-0000-4000-8000-000000000001',
        'Owner', 'owner', '9766600019', app.phone_hash('9766600019'), '77777777-aaaa-4000-8000-00000000000f', true);

insert into public.services (salon_id, name, price_paise, duration_minutes)
values ('77777777-0000-4000-8000-000000000001', 'Haircut', 30000, 30);

-- A completed Message Central verification, as otp-verify would have it.
create or replace function pg_temp.verified(p_phone text, p_salon uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := public.otp_record_challenge(p_phone, p_salon, 'mc-' || p_phone, 'salon');
  perform public.otp_complete(v);
  return v;
end $$;

create or replace function pg_temp.try_reprice()
returns bigint language plpgsql as $$
begin
  begin
    update public.services set price_paise = 1 where name = 'Haircut';
  exception when insufficient_privilege then
    null;
  end;
  return (select price_paise from public.services where name = 'Haircut');
end $$;

-- The customer joins while the salon is paid up.
select public.start_join('CRAY-BRNGAA', '9766600011');
create temp table first_login as
  select pg_temp.verified('9766600011', '77777777-0000-4000-8000-000000000001') as id;
select public.otp_finish_login((select id from first_login),
                               '77777777-aaaa-4000-8000-00000000000c', '{}'::jsonb);

create temp table cust as
  select id from public.customers where auth_user_id = '77777777-aaaa-4000-8000-00000000000c';
grant select on cust to public;

insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
select id, '77777777-0000-4000-8000-000000000001', 20000 from cust;

-- A top-up the customer started while paid up; Razorpay captures it later.
insert into public.payments (id, salon_id, customer_id, method, amount_paise, status,
                             razorpay_order_id, idempotency_key)
select '77777777-9999-4000-8000-000000000001', '77777777-0000-4000-8000-000000000001', id,
       'upi', 100000, 'created', 'order_billing_test', 'billing-test-topup'
  from cust;

-- ---------------------------------------------------------------------------
-- Paid up: an ordinary salon
-- ---------------------------------------------------------------------------

select is(app.billing_state('77777777-0000-4000-8000-000000000001'), 'active',
  'a salon whose paid period has not ended is active');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select lives_ok(
  $q$insert into public.services (name, price_paise, duration_minutes) values ('Beard', 15000, 15)$q$,
  'the owner can change the menu');

reset role;

-- ---------------------------------------------------------------------------
-- The paid period ends: READ-ONLY, at once, with no job run
-- ---------------------------------------------------------------------------

update public.subscriptions set renews_at = now() - interval '1 hour'
 where salon_id = '77777777-0000-4000-8000-000000000001';

select is(app.billing_state('77777777-0000-4000-8000-000000000001'), 'grace',
  'an hour after the period ends, the salon is in grace');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select throws_ok(
  $q$insert into public.services (name, price_paise, duration_minutes) values ('Colour', 90000, 60)$q$,
  '42501', null,
  'grace is READ-ONLY in the database - the insert is refused, not a button hidden');

-- An UPDATE under RLS may be refused OR simply match nothing, depending on the
-- policy; either is read-only. What matters is that the price did not change.
select is(pg_temp.try_reprice(), 30000::bigint,
  'and an update changes nothing');

select is((select count(*)::int from public.services), 2,
  'but the owner still READS everything - read-only, not locked out');

select is((public.my_salon_billing() ->> 'read_only'), 'true',
  'the owner''s app is told it is read-only, and why');

select is((public.my_salon_billing() ->> 'state'), 'grace',
  'with the state named');

reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000c","app_role":"customer",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select is((select balance_paise from public.wallet_accounts), 20000::bigint,
  'a customer can still SEE their money - a dispute with Crayora never hides it (PRD 16A)');

select is((public.set_consent('promotional', false) ->> 'ok'), 'true',
  'and can still withdraw consent - DPDP does not wait for a salon to pay its bill');

reset role;

-- Razorpay captured a payment the customer made before the lapse: the money has
-- already moved, so the credit must land.
select is(
  (app.record_payment_captured('77777777-9999-4000-8000-000000000001', 'pay_billing', 100000) ->> 'ok'),
  'true',
  'the webhook still credits a captured payment - the money already moved');

-- Logging in: the salon's own people yes, somebody new no.
select public.start_join('CRAY-BRNGAA', '9766600011');
create temp table again as
  select pg_temp.verified('9766600011', '77777777-0000-4000-8000-000000000001') as id;

select is(
  public.otp_finish_login((select id from again), '77777777-aaaa-4000-8000-00000000000c',
                          '{}'::jsonb) ->> 'outcome',
  'returning',
  'an existing customer still logs in - to read what is theirs');

select public.start_join('CRAY-BRNGAA', '9766600012');
create temp table newcomer as
  select pg_temp.verified('9766600012', '77777777-0000-4000-8000-000000000001') as id;

select is(
  public.otp_finish_login((select id from newcomer), '77777777-aaaa-4000-8000-00000000000d',
                          '{}'::jsonb) ->> 'reason',
  'salon_unavailable',
  'but nobody NEW joins a lapsed salon - a first join is a write');

-- ---------------------------------------------------------------------------
-- Automation I: notices, once each; the status is never touched
-- ---------------------------------------------------------------------------

select app.run_billing_lifecycle();
select app.run_billing_lifecycle();

select is(
  (select count(*)::int from public.billing_notices
    where salon_id = '77777777-0000-4000-8000-000000000001' and kind = 'grace_started'),
  1,
  'grace is noticed ONCE, however many nights the job runs');

select is(
  (select status::text from public.subscriptions
    where salon_id = '77777777-0000-4000-8000-000000000001'),
  'past_due',
  'the subscription is labelled past due for the console');

select is(
  (select status::text from public.salons where id = '77777777-0000-4000-8000-000000000001'),
  'active',
  'and the SALON''s status is untouched - billing never flips it (RULES 6.3)');

-- Eight days on: suspended.
update public.subscriptions set renews_at = now() - interval '8 days'
 where salon_id = '77777777-0000-4000-8000-000000000001';

select is(app.billing_state('77777777-0000-4000-8000-000000000001'), 'suspended',
  'seven days of grace, then suspended');

-- Day 61 of suspension.
update public.subscriptions set renews_at = now() - interval '7 days' - interval '61 days'
 where salon_id = '77777777-0000-4000-8000-000000000001';
select app.run_billing_lifecycle();

select is(
  (select array_agg(kind order by due_at) from public.billing_notices
    where salon_id = '77777777-0000-4000-8000-000000000001'
      and cycle_renews_at = (select renews_at from public.subscriptions
                              where salon_id = '77777777-0000-4000-8000-000000000001')),
  array['grace_started', 'suspended', 'retention_60'],
  'on day 61 the day-60 notice has fired, and the day-80 one has not');

-- Day 81.
update public.subscriptions set renews_at = now() - interval '7 days' - interval '81 days'
 where salon_id = '77777777-0000-4000-8000-000000000001';
select app.run_billing_lifecycle();

select ok(
  (select 'retention_80' = any(array_agg(kind)) and not 'purge_due' = any(array_agg(kind))
     from public.billing_notices
    where salon_id = '77777777-0000-4000-8000-000000000001'
      and cycle_renews_at = (select renews_at from public.subscriptions
                              where salon_id = '77777777-0000-4000-8000-000000000001')),
  'on day 81 the day-80 notice has fired, and purge is not yet due');

-- Day 98: purge is DUE. Nothing is deleted by a date.
update public.subscriptions set renews_at = now() - interval '98 days'
 where salon_id = '77777777-0000-4000-8000-000000000001';
select app.run_billing_lifecycle();

select is(app.billing_state('77777777-0000-4000-8000-000000000001'), 'purge_due',
  'ninety days after suspension, purge is due');

select is(
  (select count(*)::int from public.customers where salon_id = '77777777-0000-4000-8000-000000000001'),
  1,
  'and NOTHING has been deleted - purging is a deliberate act, not a date (M12)');

-- ---------------------------------------------------------------------------
-- Paying: the only thing that ends a lapse
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$select app_admin.record_subscription_payment('77777777-aaaa-4000-8000-00000000000a',
       '77777777-0000-4000-8000-000000000001', 79900, 1, '  ')$q$,
  'P0001', null,
  'a payment with no reference is refused - it was collected offline');

-- Four months, from where the last period ENDED (98 days ago).
select app_admin.record_subscription_payment('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 319600, 4, 'NEFT UTR 4471', current_date);

select ok(
  (select renews_at between now() + interval '15 days' and now() + interval '30 days'
     from public.subscriptions where salon_id = '77777777-0000-4000-8000-000000000001'),
  'the period runs on from where the last one ended - a late payer pays for the time they had');

select ok(app.salon_writable('77777777-0000-4000-8000-000000000001'),
  'and the salon is writable again the moment it is recorded');

select throws_ok(
  $q$update public.subscription_payments set amount_paise = 1$q$,
  '42501', null,
  'subscription payments are append-only');

-- A salon an operator suspended BY HAND stays suspended when it pays.
select app_admin.set_salon_status('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 'suspended', 'fraud review');
select app_admin.record_subscription_payment('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 79900, 1, 'NEFT UTR 4472', current_date);

select is(
  (select status::text from public.salons where id = '77777777-0000-4000-8000-000000000001'),
  'suspended',
  'a payment never reactivates a salon - activation is a human act (RULES 6.3)');

-- ---------------------------------------------------------------------------
-- Activation needs the setup fee
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$select app_admin.activate_salon('77777777-aaaa-4000-8000-00000000000a',
       '77777777-0000-4000-8000-000000000002', 'go live')$q$,
  'P0001', null,
  'a salon with an unpaid setup fee cannot be activated - there is no free trial');

select throws_ok(
  $q$select app_admin.record_setup_fee('77777777-aaaa-4000-8000-00000000000a',
       '77777777-0000-4000-8000-000000000002', 'waived', null)$q$,
  'P0001', null,
  'a waiver needs a reason');

select app_admin.record_setup_fee('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000002', 'paid', 'Cash receipt 0019', current_date, 1500000);

select lives_ok(
  $q$select app_admin.activate_salon('77777777-aaaa-4000-8000-00000000000a',
       '77777777-0000-4000-8000-000000000002', 'go live')$q$,
  'once the fee is recorded, the operator can activate');

select is(
  (select setup_fee_paise from public.subscriptions
    where salon_id = '77777777-0000-4000-8000-000000000002'),
  1500000::bigint,
  'and the fee''s AMOUNT is on record, not just its status (RULES 6.4)');

-- ---------------------------------------------------------------------------
-- Entitlements, checked by the server
-- ---------------------------------------------------------------------------

select app_admin.set_feature_flag('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 'dashboard', false, 'not in their plan');

-- The fraud review is over: a person lifts it, on purpose (0092).
select throws_like(
  $q$select app_admin.reactivate_salon('77777777-aaaa-4000-8000-00000000000a',
       '77777777-0000-4000-8000-000000000001', '   ')$q$,
  '%needs a reason%',
  'lifting a suspension needs a reason');

select app_admin.reactivate_salon('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 'Fraud review cleared');

select is(
  (select status::text from public.salons where id = '77777777-0000-4000-8000-000000000001'),
  'active',
  'a suspended salon CAN be brought back - by a super-admin, with a reason, audited');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select throws_like(
  $q$select public.owner_dashboard()$q$,
  '%not_in_plan%',
  'a feature the salon does not have is refused BY THE SERVER, not just hidden');

select ok(not 'dashboard' = any(public.my_features()),
  'and the app is told, so it can hide the button');

reset role;

select app_admin.set_feature_flag('77777777-aaaa-4000-8000-00000000000a',
  '77777777-0000-4000-8000-000000000001', 'dashboard', null, 'back to the plan');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select lives_ok($q$select public.owner_dashboard()$q$,
  'cleared, the plan decides again');

reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"77777777-aaaa-4000-8000-00000000000f","app_role":"staff",'
  '"salon_id":"77777777-0000-4000-8000-000000000001"}', true);

select ok(not (public.my_salon_billing() ? 'monthly_price_paise'),
  'a stylist sees whether the app is read-only, not what the salon pays');

reset role;

select * from finish();
