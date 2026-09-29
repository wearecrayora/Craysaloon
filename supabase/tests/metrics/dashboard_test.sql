-- RELEASE GATE: the owner's numbers (M10)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PRD 9.5 AC, verbatim in intent:
--   * card totals match completed transactions EXACTLY
--   * a nightly reconciliation ALERTS on mismatch rather than silently correcting
--   * no wallet-adjustment control exists anywhere an owner can reach
--
-- And three that follow from how the numbers are built:
--   * "today" is the SALON's today, not UTC's (0076)
--   * a cohort rate is unknown - NULL - until every member has had the window
--   * messaging spend is never returned without the conversion it bought

select plan(22);

insert into auth.users (id) values
  ('33333333-aaaa-4000-8000-00000000000f'),
  ('33333333-aaaa-4000-8000-00000000000c');

insert into public.platform_admins (id, email, name, is_super, active)
values ('33333333-aaaa-4000-8000-00000000000f', 'm10@crayora.test', 'M10 Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('33333333-0000-4000-8000-000000000001', 'Numbers Salon Ltd', 'Numbers Salon',
        'CRAY-NMBRS2', 'active', 'Asia/Kolkata',
        '33333333-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('33333333-1111-4000-8000-00000000000a', '33333333-0000-4000-8000-000000000001',
   '33333333-aaaa-4000-8000-00000000000c', 'Anil', app.phone_hash('9744400011')),
  ('33333333-1111-4000-8000-00000000000b', '33333333-0000-4000-8000-000000000001',
   null, 'Bela', app.phone_hash('9744400012'));

insert into public.staff (id, salon_id, name, active)
values ('33333333-3333-4000-8000-000000000001', '33333333-0000-4000-8000-000000000001',
        'Numbers stylist', true);

-- ---------------------------------------------------------------------------
-- The salon's day
-- ---------------------------------------------------------------------------

-- 00:30 IST on 10 March is 19:00 UTC on 9 March.
select is(
  app.salon_day('33333333-0000-4000-8000-000000000001',
                timestamptz '2027-03-09 19:00:00+00'),
  date '2027-03-10',
  'half past midnight in Kolkata is TODAY in Kolkata - not yesterday in Greenwich (0076)');

-- ---------------------------------------------------------------------------
-- Reconciliation: alert, do not heal
-- ---------------------------------------------------------------------------

-- A visit yesterday, written the honest way: through the automation.
insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('33333333-4444-4000-8000-000000000001', '33333333-0000-4000-8000-000000000001',
        '33333333-1111-4000-8000-00000000000a', '33333333-3333-4000-8000-000000000001',
        now() - interval '1 day', now() - interval '1 day' + interval '30 minutes', 'completed');

insert into public.visits (id, salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values ('33333333-5555-4000-8000-000000000001', '33333333-0000-4000-8000-000000000001',
        '33333333-4444-4000-8000-000000000001', '33333333-1111-4000-8000-00000000000a',
        '33333333-3333-4000-8000-000000000001', 50000, now() - interval '1 day');

select app.on_visit_completed('33333333-5555-4000-8000-000000000001');

-- The booking row was inserted by hand above, so Automation C never counted it.
-- That is the realistic drift: a row the automation missed, exactly as every
-- booking made before 0075 was missed.
create temp table yday as
  select app.salon_day('33333333-0000-4000-8000-000000000001', now() - interval '1 day') as d;

create temp table recon1 as
  select app.reconcile_day('33333333-0000-4000-8000-000000000001', (select d from yday)) as r;

select is((select r ->> 'drifted' from recon1), 'true',
  'a booking the automation never counted is DETECTED');

select is(
  (select r -> 'drift' -> 'bookings' ->> 'source' from recon1), '1',
  'the alert says what the source actually holds');

select is(
  (select r -> 'drift' -> 'bookings' ->> 'stored' from recon1), '0',
  'and what the card was showing');

select is(
  (select bookings from public.daily_salon_metrics
    where salon_id = '33333333-0000-4000-8000-000000000001' and day = (select d from yday)),
  0,
  'and the stored number is NOT healed - silently correcting it would hide the bug (PRD 9.5)');

select is(
  (select count(*)::int from public.domain_events
    where salon_id = '33333333-0000-4000-8000-000000000001' and type = 'metrics.drift'),
  1,
  'the drift is written down where a person can find it');

select is(
  (app.reconcile_day('33333333-0000-4000-8000-000000000001', (select d from yday))
     ->> 'drifted'),
  'true',
  'a second run still reports it - the drift is real until the cause is fixed');

select is(
  (select count(*)::int from public.domain_events
    where salon_id = '33333333-0000-4000-8000-000000000001' and type = 'metrics.drift'),
  1,
  'but raises ONE alert per salon-day, not one per run - an alert that repeats is ignored');

-- Revenue and completed came through the automation, so they AGREE.
select is(
  (select r -> 'drift' -> 'revenue_paise' from recon1), null,
  'revenue written by the automation matches the visits exactly - no drift');

select is(
  (select revenue_paise from public.daily_salon_metrics
    where salon_id = '33333333-0000-4000-8000-000000000001' and day = (select d from yday)),
  (select coalesce(sum(final_amount_paise), 0)::bigint from public.visits
    where salon_id = '33333333-0000-4000-8000-000000000001'
      and app.salon_day(salon_id, completed_at) = (select d from yday)),
  'the card total equals the completed transactions (PRD 9.5 AC)');

-- The DERIVED columns: the nightly job is their only writer.
select is(
  (select new_customers from public.daily_salon_metrics
    where salon_id = '33333333-0000-4000-8000-000000000001' and day = (select d from yday)),
  1,
  'a first-ever visit is counted as a new customer by the job that owns that column');

-- ---------------------------------------------------------------------------
-- Cohorts: unknown is not zero
-- ---------------------------------------------------------------------------

select app.refresh_retention_cohorts('33333333-0000-4000-8000-000000000001');

select is(
  (select cohort_size from public.retention_cohorts
    where salon_id = '33333333-0000-4000-8000-000000000001'),
  1,
  'the cohort counts its members - the n a chart must show');

select is(
  (select d30 from public.retention_cohorts
    where salon_id = '33333333-0000-4000-8000-000000000001'),
  null,
  'a day-old cohort has NO 30-day rate - printing 0% would call people who have not '
  'had the chance to return "lost"');

-- A cohort that has had the window: first visit 100 days ago, back on day 20.
insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values
  ('33333333-4444-4000-8000-000000000002', '33333333-0000-4000-8000-000000000001',
   '33333333-1111-4000-8000-00000000000b', '33333333-3333-4000-8000-000000000001',
   now() - interval '100 days', now() - interval '100 days' + interval '30 minutes', 'completed'),
  ('33333333-4444-4000-8000-000000000003', '33333333-0000-4000-8000-000000000001',
   '33333333-1111-4000-8000-00000000000b', '33333333-3333-4000-8000-000000000001',
   now() - interval '80 days', now() - interval '80 days' + interval '30 minutes', 'completed');

insert into public.visits (salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values
  ('33333333-0000-4000-8000-000000000001', '33333333-4444-4000-8000-000000000002',
   '33333333-1111-4000-8000-00000000000b', '33333333-3333-4000-8000-000000000001',
   30000, now() - interval '100 days'),
  ('33333333-0000-4000-8000-000000000001', '33333333-4444-4000-8000-000000000003',
   '33333333-1111-4000-8000-00000000000b', '33333333-3333-4000-8000-000000000001',
   30000, now() - interval '80 days');

select app.refresh_retention_cohorts('33333333-0000-4000-8000-000000000001');

select is(
  (select d30 from public.retention_cohorts
    where salon_id = '33333333-0000-4000-8000-000000000001'
      and cohort_month = date_trunc('month',
            app.salon_day('33333333-0000-4000-8000-000000000001', now() - interval '100 days'))::date),
  100.0::numeric,
  'a matured cohort whose one member came back on day 20 returned 100% within 30 days');

select is(
  (select count(*)::int from public.retention_cohorts
    where salon_id = '33333333-0000-4000-8000-000000000001'),
  2,
  'rebuilt whole, so no stale row outlives the data that made it');

-- ---------------------------------------------------------------------------
-- The owner's dashboard
-- ---------------------------------------------------------------------------

-- Today, completed through the automation.
insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('33333333-4444-4000-8000-000000000009', '33333333-0000-4000-8000-000000000001',
        '33333333-1111-4000-8000-00000000000a', '33333333-3333-4000-8000-000000000001',
        now(), now() + interval '30 minutes', 'completed');

insert into public.visits (salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values ('33333333-0000-4000-8000-000000000001', '33333333-4444-4000-8000-000000000009',
        '33333333-1111-4000-8000-00000000000a', '33333333-3333-4000-8000-000000000001',
        45000, now());

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"33333333-0000-4000-8000-000000000001"}',
  true
);

create temp table dash as select public.owner_dashboard() as d;
grant select on dash to public;

select is(
  (select (d -> 'today' ->> 'revenue_paise')::bigint from dash),
  45000::bigint,
  'today''s revenue is computed from the visits themselves - it cannot drift');

select is(
  (select (d -> 'today' ->> 'completed')::int from dash), 1,
  'and today''s completed count likewise');

select ok(
  (select d -> 'messaging' ? 'spend_by_channel' and d -> 'messaging' ? 'reminder_bookings'
     from dash),
  'messaging spend is returned WITH reminder conversion, never alone (PRD 9.5)');

select is(
  (select jsonb_array_length(d -> 'drift_days') from dash), 1,
  'and the drift is SHOWN to the owner, not hidden from them');

reset role;

-- Only owners and managers.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"33333333-aaaa-4000-8000-00000000000c",'
  '"app_role":"customer",'
  '"salon_id":"33333333-0000-4000-8000-000000000001"}',
  true
);

select throws_ok(
  $q$select public.owner_dashboard()$q$,
  '42501', null,
  'a customer cannot read the salon''s takings');

reset role;

-- ---------------------------------------------------------------------------
-- No wallet adjustment anywhere an owner can reach (PRD 9.5 AC)
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app', 'app_admin')
      and p.prosrc ~* 'wallet_post'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0,
  'no function an owner, manager or customer can execute posts to the wallet ledger');

select is(
  (select count(*)::int from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~* '(adjust|correct|credit|set_balance)'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0,
  'and nothing on the API surface is even NAMED like an adjustment');

select * from finish();
