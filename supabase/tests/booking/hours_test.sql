-- GATE: stylist hours and salon holidays decide what can be booked (0098)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- Bookable times come from each stylist's week, minus their time off, minus any
-- day the whole salon is closed. Before 0098 nothing wrote a stylist's week (so
-- nothing could ever be booked) and a salon holiday blocked nothing.

select plan(16);

insert into auth.users (id) values ('aaaa7777-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('aaaa7777-aaaa-4000-8000-00000000000f', 'hours@crayora.test', 'Hours Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at, timezone)
values ('aaaa7777-0000-4000-8000-000000000001', 'Hours Salon Ltd', 'Hours Salon', 'CRAY-HRSQ22',
        'active', 'aaaa7777-aaaa-4000-8000-00000000000f', now(), 'Asia/Kolkata');

insert into public.staff (id, salon_id, name, active) values
  ('aaaa7777-3333-4000-8000-000000000001', 'aaaa7777-0000-4000-8000-000000000001', 'Suresh', true),
  ('aaaa7777-3333-4000-8000-000000000002', 'aaaa7777-0000-4000-8000-000000000001', 'Priya', true);

insert into public.services (id, salon_id, name, price_paise, duration_minutes, active)
values ('aaaa7777-2222-4000-8000-000000000001', 'aaaa7777-0000-4000-8000-000000000001',
        'Haircut', 60000, 30, true);

-- A day well in the future, so no candidate time is in the past.
create temp table d as select (current_date + 8) as day, extract(dow from current_date + 8)::int as dow;
grant select on d to public;

create function pg_temp.as_role(p_role text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', 'aaaa7777-aaaa-4000-8000-00000000000f', 'app_role', p_role,
                      'salon_id', 'aaaa7777-0000-4000-8000-000000000001')::text, true);
$$;

create function pg_temp.slots(p_staff uuid default null) returns integer language sql as $$
  select count(*)::int from public.available_slots(
    'aaaa7777-0000-4000-8000-000000000001', 'aaaa7777-2222-4000-8000-000000000001',
    p_staff, (select day from d), '{}'::uuid[], 30);
$$;

-- 0104: a stylist is bookable from the moment they are added - 10:00 to 17:00,
-- every day, until the owner sets their week.
select results_eq(
  $q$select count(*)::int, count(distinct day_of_week)::int, min(starts_at), max(ends_at)
       from public.staff_schedules where staff_id = 'aaaa7777-3333-4000-8000-000000000001'$q$,
  $q$values (7, 7, time '10:00', time '17:00')$q$,
  'a new stylist starts on 10:00-17:00, every day of the week (0104)');

set local role authenticated;
select pg_temp.as_role('owner');

select cmp_ok(pg_temp.slots(), '>', 0, 'so a salon that has just added its team can take a booking');

-- Without any hours, nothing is bookable - the state every salon was in before
-- 0104. Cleared here so the rest of this gate starts from an empty week.
reset role;
delete from public.staff_schedules where salon_id = 'aaaa7777-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.as_role('owner');

select is(pg_temp.slots(), 0, 'with no stylist hours, nothing can be booked - the state every salon was in');

-- ---------------------------------------------------------------------------
-- Who may set hours
-- ---------------------------------------------------------------------------

select pg_temp.as_role('staff');
select throws_ok(
  format($$select public.set_staff_week('aaaa7777-3333-4000-8000-000000000001',
           '[{"day": %s, "starts": "10:00", "ends": "13:00"}]'::jsonb)$$, (select dow from d)),
  '42501', null, 'a stylist cannot set working hours');

select pg_temp.as_role('customer');
select throws_ok(
  $$select public.add_time_off(null, now(), now() + interval '1 day', 'not mine to close')$$,
  '42501', null, 'a customer cannot close the salon');

select pg_temp.as_role('manager');
select is(
  (public.set_staff_week('aaaa7777-3333-4000-8000-000000000002',
     format('[{"day": %s, "starts": "10:00", "ends": "11:00"}]', (select dow from d))::jsonb) ->> 'ok'),
  'true', 'a manager can set a stylist''s week');

select pg_temp.as_role('owner');
select is(
  (public.set_staff_week('aaaa7777-3333-4000-8000-000000000001',
     format('[{"day": %1$s, "starts": "10:00", "ends": "13:00"},
              {"day": %1$s, "starts": "14:00", "ends": "15:00"}]', (select dow from d))::jsonb) ->> 'shifts'),
  '2', 'the owner sets two shifts on one day - a lunch break');

select throws_ok(
  format($$select public.set_staff_week('aaaa7777-3333-4000-8000-000000000001',
           '[{"day": %1$s, "starts": "10:00", "ends": "13:00"},
             {"day": %1$s, "starts": "12:00", "ends": "14:00"}]'::jsonb)$$, (select dow from d)),
  '22023', null, 'overlapping shifts are refused');

select throws_ok(
  format($$select public.set_staff_week('aaaa7777-3333-4000-8000-000000000001',
           '[{"day": %s, "starts": "18:00", "ends": "09:00"}]'::jsonb)$$, (select dow from d)),
  '22023', null, 'a shift that ends before it starts is refused');

-- ---------------------------------------------------------------------------
-- Hours become bookable times
-- ---------------------------------------------------------------------------

-- Suresh: 10:00-13:00 and 14:00-15:00, 30-minute service, 30-minute steps:
-- 10:00 .. 12:30 (6) + 14:00, 14:30 (2) = 8. Priya: 10:00, 10:30 = 2.
select is(pg_temp.slots('aaaa7777-3333-4000-8000-000000000001'), 8,
  'a stylist''s week becomes bookable times - and the lunch break is not one of them');
select is(pg_temp.slots(), 10, 'every stylist''s times together');

-- A refused week leaves the saved one exactly as it was.
select is(pg_temp.slots('aaaa7777-3333-4000-8000-000000000001'), 8,
  'a refused change did not half-save');

-- ---------------------------------------------------------------------------
-- Time off: one stylist, then the whole salon
-- ---------------------------------------------------------------------------

select public.add_time_off('aaaa7777-3333-4000-8000-000000000001',
  ((select day from d) + time '10:00') at time zone 'Asia/Kolkata',
  ((select day from d) + time '11:00') at time zone 'Asia/Kolkata', 'Dentist');

select is(pg_temp.slots('aaaa7777-3333-4000-8000-000000000001'), 6,
  'a stylist''s hour off removes the times that would overlap it');
select is(pg_temp.slots('aaaa7777-3333-4000-8000-000000000002'), 2,
  'and touches no other stylist');

create temp table h as
  select (public.add_time_off(null,
            ((select day from d) + time '00:00') at time zone 'Asia/Kolkata',
            ((select day from d) + time '23:59') at time zone 'Asia/Kolkata',
            'Diwali') ->> 'id')::uuid as id;
grant select on h to public;

select is(pg_temp.slots(), 0,
  'a SALON holiday closes every chair - it used to block nothing (0098)');

select public.remove_time_off((select id from h));
select is(pg_temp.slots(), 8, 'and removing it opens them again');

reset role;
select * from finish();
