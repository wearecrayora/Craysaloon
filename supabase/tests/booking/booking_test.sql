-- RELEASE GATE: booking, slots and mark-complete (M6)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PHASES M6 done-when, asserted against the functions that run:
--   * two bookings for the same chair at the same time cannot both succeed
--   * a price is SNAPSHOTTED, so repricing never rewrites what a booking cost
--   * mark-complete is idempotent, because the offline queue will deliver it
--     more than once (RULES 9.4)
--   * an add-on that is not offered with the service is refused
--   * a customer books only for themselves, and never completes their own visit

select plan(41);

insert into auth.users (id) values
  ('ffffffff-aaaa-4000-8000-00000000000f'),
  ('ffffffff-aaaa-4000-8000-00000000000c'),
  ('ffffffff-aaaa-4000-8000-00000000000d');

insert into public.platform_admins (id, email, name, is_super, active)
values ('ffffffff-aaaa-4000-8000-00000000000f', 'book@crayora.test', 'Book Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           timezone, activated_by, activated_at)
values ('ffffffff-0000-4000-8000-000000000001', 'Book Salon Ltd', 'Book Salon',
        'CRAY-BKKQQQ', 'active', 'Asia/Kolkata',
        'ffffffff-aaaa-4000-8000-00000000000f', now());

insert into public.users (id, salon_id, auth_user_id, role, name, phone, phone_hash, active)
values ('ffffffff-5555-4000-8000-00000000000f', 'ffffffff-0000-4000-8000-000000000001',
        'ffffffff-aaaa-4000-8000-00000000000f', 'owner', 'Book Owner', '9888800009',
        app.phone_hash('9888800009'), true);

insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash)
values
  ('ffffffff-1111-4000-8000-00000000000c', 'ffffffff-0000-4000-8000-000000000001',
   'ffffffff-aaaa-4000-8000-00000000000c', 'Asha', '9888800001', app.phone_hash('9888800001')),
  ('ffffffff-1111-4000-8000-00000000000d', 'ffffffff-0000-4000-8000-000000000001',
   'ffffffff-aaaa-4000-8000-00000000000d', 'Dev', '9888800002', app.phone_hash('9888800002'));

insert into public.staff (id, salon_id, name, active)
values ('ffffffff-4444-4000-8000-000000000001', 'ffffffff-0000-4000-8000-000000000001',
        'Rahul', true);

insert into public.services (id, salon_id, name, price_paise, duration_minutes, active)
values ('ffffffff-2222-4000-8000-000000000001', 'ffffffff-0000-4000-8000-000000000001',
        'Haircut', 40000, 30, true);

insert into public.add_ons (id, salon_id, name, price_paise, extra_duration_minutes, active)
values
  ('ffffffff-6666-4000-8000-000000000001', 'ffffffff-0000-4000-8000-000000000001',
   'Head massage', 15000, 15, true),
  -- Offered with some other service, never with Haircut.
  ('ffffffff-6666-4000-8000-000000000002', 'ffffffff-0000-4000-8000-000000000001',
   'Beard colour', 25000, 20, true);

insert into public.service_addons (salon_id, service_id, add_on_id)
values ('ffffffff-0000-4000-8000-000000000001', 'ffffffff-2222-4000-8000-000000000001',
        'ffffffff-6666-4000-8000-000000000001');

-- Rahul works 10:00-18:00 local, every day of the week.
insert into public.staff_schedules (salon_id, staff_id, day_of_week, starts_at, ends_at)
select 'ffffffff-0000-4000-8000-000000000001', 'ffffffff-4444-4000-8000-000000000001',
       d::smallint, time '10:00', time '18:00'
  from generate_series(0, 6) d;

-- Tomorrow, 11:00 in the salon's own timezone: safely in the future, inside the
-- working day, whatever time the suite runs.
create temp table slot as
select ((now() at time zone 'Asia/Kolkata')::date + 1 + time '11:00')
         at time zone 'Asia/Kolkata' as at;

-- Readable after the role switch below: the fixture is created as the migration
-- role, and everything after this point runs as `authenticated`.
grant select on slot to public;

-- ---------------------------------------------------------------------------
-- As the owner
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ffffffff-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"ffffffff-0000-4000-8000-000000000001"}',
  true
);

select is((select current_user)::text, 'authenticated',
  'the test runs as authenticated, so these assertions mean something');

-- Availability -------------------------------------------------------------

select is(
  (select count(*)::int from public.available_slots(
     'ffffffff-0000-4000-8000-000000000001',
     'ffffffff-2222-4000-8000-000000000001',
     'ffffffff-4444-4000-8000-000000000001',
     ((now() at time zone 'Asia/Kolkata')::date + 1))),
  -- 10:00-18:00 is 8 hours; a 30-minute service on a 15-minute grid leaves
  -- 31 starts (the last one at 17:30).
  31,
  'a free day offers every 15-minute start that fits the service'
);

select is(
  (select count(*)::int from public.available_slots(
     'ffffffff-0000-4000-8000-000000000001',
     'ffffffff-2222-4000-8000-000000000001',
     'ffffffff-4444-4000-8000-000000000001',
     ((now() at time zone 'Asia/Kolkata')::date + 1),
     array['ffffffff-6666-4000-8000-000000000001'::uuid])),
  -- 45 minutes on a 15-minute grid: (480 - 45) / 15 + 1, the last start 17:15.
  30,
  'adding a 15-minute add-on makes the appointment longer, so fewer starts fit'
);

select is(
  (select count(*)::int from public.available_slots(
     'ffffffff-0000-4000-8000-000000000001',
     'ffffffff-2222-4000-8000-000000000001',
     'ffffffff-4444-4000-8000-000000000001',
     ((now() at time zone 'Asia/Kolkata')::date - 1))),
  0,
  'yesterday offers nothing - a slot that has already started cannot be booked'
);

-- Booking -------------------------------------------------------------------

create temp table booked as
select public.create_booking(
  '11111111-9999-4000-8000-000000000001',
  'ffffffff-2222-4000-8000-000000000001',
  (select at from slot),
  'ffffffff-4444-4000-8000-000000000001',
  'ffffffff-1111-4000-8000-00000000000c') as r;

select is((select r ->> 'ok' from booked), 'true', 'the owner books a walk-in');

select is(
  (select (r ->> 'total_paise')::bigint from booked),
  40000::bigint,
  'and the total is the service price'
);

select is(
  (select status::text from public.bookings where id = (select (r ->> 'booking_id')::uuid from booked)),
  'confirmed',
  'the booking is confirmed, not left pending for someone to chase'
);

select results_eq(
  $$select kind::text, name_snapshot, price_paise, duration_minutes
      from public.booking_items
     where booking_id = (select (r ->> 'booking_id')::uuid from booked)$$,
  $$values ('service', 'Haircut', 40000::bigint, 30)$$,
  'the service is snapshotted onto the booking - name, price and duration'
);

-- THE SNAPSHOT, tested the only way that means anything: change the price.
update public.services set price_paise = 60000
 where id = 'ffffffff-2222-4000-8000-000000000001';

select is(
  (select price_paise from public.booking_items
    where booking_id = (select (r ->> 'booking_id')::uuid from booked) and kind = 'service'),
  40000::bigint,
  'repricing the service does NOT rewrite what this booking cost (ARCH 6.2)'
);

-- The race -------------------------------------------------------------------

select is(
  (public.create_booking(
     '11111111-9999-4000-8000-000000000002',
     'ffffffff-2222-4000-8000-000000000001',
     (select at from slot),
     'ffffffff-4444-4000-8000-000000000001',
     'ffffffff-1111-4000-8000-00000000000d') ->> 'reason'),
  'slot_taken',
  'the same chair at the same time cannot be booked twice - the constraint decides'
);

select is(
  (public.create_booking(
     '11111111-9999-4000-8000-000000000003',
     'ffffffff-2222-4000-8000-000000000001',
     (select at + interval '15 min' from slot),
     'ffffffff-4444-4000-8000-000000000001',
     'ffffffff-1111-4000-8000-00000000000d') ->> 'reason'),
  'slot_taken',
  'nor OVERLAPPED - 15 minutes into a 30-minute cut is the same chair'
);

select is(
  (public.create_booking(
     '11111111-9999-4000-8000-000000000004',
     'ffffffff-2222-4000-8000-000000000001',
     (select at + interval '30 min' from slot),
     'ffffffff-4444-4000-8000-000000000001',
     'ffffffff-1111-4000-8000-00000000000d') ->> 'ok'),
  'true',
  'but the moment the first one ends is free - the range is half-open'
);

-- Idempotency ----------------------------------------------------------------

select is(
  (public.create_booking(
     '11111111-9999-4000-8000-000000000001',
     'ffffffff-2222-4000-8000-000000000001',
     (select at from slot),
     'ffffffff-4444-4000-8000-000000000001',
     'ffffffff-1111-4000-8000-00000000000c') ->> 'booking_id'),
  (select r ->> 'booking_id' from booked),
  'a REPLAY returns the original booking (RULES 9.3) - the queue may drain twice'
);

select is(
  (select count(*)::int from public.bookings
    where client_action_id = '11111111-9999-4000-8000-000000000001'),
  1,
  'and creates no second booking'
);

-- Add-ons --------------------------------------------------------------------

create temp table with_addon as
select public.create_booking(
  '11111111-9999-4000-8000-000000000005',
  'ffffffff-2222-4000-8000-000000000001',
  (select at + interval '2 hours' from slot),
  'ffffffff-4444-4000-8000-000000000001',
  'ffffffff-1111-4000-8000-00000000000c',
  array['ffffffff-6666-4000-8000-000000000001'::uuid]) as r;

select is(
  (select (r ->> 'total_paise')::bigint from with_addon),
  75000::bigint,
  'an add-on adds its price - at TODAY''s price of the service, 60000 + 15000'
);

select is(
  (select (r ->> 'minutes')::int from with_addon),
  45,
  'and its extra minutes, which is what made the slot grid shorter'
);

select throws_ok(
  $$select public.create_booking(
      '11111111-9999-4000-8000-000000000006',
      'ffffffff-2222-4000-8000-000000000001',
      now() + interval '3 days',
      'ffffffff-4444-4000-8000-000000000001',
      'ffffffff-1111-4000-8000-00000000000c',
      array['ffffffff-6666-4000-8000-000000000002'::uuid])$$,
  '42501', null,
  'an add-on that is not offered with this service is refused, not quietly dropped'
);

-- Mark complete ---------------------------------------------------------------

create temp table completed as
select public.mark_visit_complete(
  '22222222-9999-4000-8000-000000000001',
  (select (r ->> 'booking_id')::uuid from booked)) as r;

select is((select r ->> 'ok' from completed), 'true', 'the owner marks the visit complete');

select is(
  (select status::text from public.bookings
    where id = (select (r ->> 'booking_id')::uuid from booked)),
  'completed',
  'the booking moves confirmed -> completed'
);

select is(
  (select final_amount_paise from public.visits
    where booking_id = (select (r ->> 'booking_id')::uuid from booked)),
  40000::bigint,
  'the visit records what the booking actually cost, not today''s price list'
);

select is(
  (select last_visit_at is not null from public.customers
    where id = 'ffffffff-1111-4000-8000-00000000000c'),
  true,
  'and the customer''s last visit moves, which is what the owner''s list sorts by'
);

-- THE SEAM. Automation A is gated in its own file by calling it directly, and
-- it had NO CALLER for three days: marking a visit complete scheduled no
-- reminder and wrote no metric (0075). Asserting a function works is not
-- asserting that anything runs it.

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'ffffffff-1111-4000-8000-00000000000c' and status = 'scheduled'),
  1,
  'marking a visit complete SCHEDULES THE REMINDER - Automation A actually runs'
);

select is(
  (select sum(completed)::int from public.daily_salon_metrics
    where salon_id = 'ffffffff-0000-4000-8000-000000000001'),
  1,
  'and today''s numbers move'
);

select is(
  (select sum(revenue_paise)::bigint from public.daily_salon_metrics
    where salon_id = 'ffffffff-0000-4000-8000-000000000001'),
  40000::bigint,
  'by what the visit actually cost'
);

-- RULES 9.4: replays are no-ops. This is the assertion that makes offline safe.
select is(
  (public.mark_visit_complete(
     '22222222-9999-4000-8000-000000000001',
     (select (r ->> 'booking_id')::uuid from booked)) ->> 'visit_id'),
  (select (r ->> 'visit_id') from completed),
  'a replayed mark-complete returns the SAME visit'
);

-- And the replay must not run the automation a second time. The metrics are
-- INCREMENTS, so a double count here is revenue the owner never took.
select is(
  (select sum(completed)::int from public.daily_salon_metrics
    where salon_id = 'ffffffff-0000-4000-8000-000000000001'),
  1,
  'a replay counts the visit ONCE - the automation runs only on the path that created it'
);

select is(
  (select sum(revenue_paise)::bigint from public.daily_salon_metrics
    where salon_id = 'ffffffff-0000-4000-8000-000000000001'),
  40000::bigint,
  'and adds the revenue once - a double count is money the owner never took'
);

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'ffffffff-1111-4000-8000-00000000000c'
      and status in ('scheduled', 'sent', 'delivered')),
  1,
  'and schedules no second reminder'
);

-- Automation C, same seam: a booking that nobody is told about. Read with the
-- role reset, because `notifications` is closed to staff by the restrictive
-- customer-scope policy (0038) - correctly, and the automation's EFFECT is what
-- is being asserted here rather than who may look at it.
reset role;

-- Scoped to THIS booking. A bare count over the salon passes for the wrong
-- reason the moment another test above it books anything.
select is(
  (select count(*)::int from public.notifications
    where purpose = 'booking_confirmed'
      and params ->> 'booking_id' = (select r ->> 'booking_id' from booked)),
  1,
  'and creating a booking told the customer - Automation C runs too'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ffffffff-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"ffffffff-0000-4000-8000-000000000001"}',
  true
);

select is(
  (select count(*)::int from public.visits
    where booking_id = (select (r ->> 'booking_id')::uuid from booked)),
  1,
  'and writes no second visit'
);

-- A different action id for a booking already completed: still one visit.
select is(
  (public.mark_visit_complete(
     '22222222-9999-4000-8000-000000000002',
     (select (r ->> 'booking_id')::uuid from booked)) ->> 'already'),
  'true',
  'even under a NEW action id, completing twice is a no-op - the state decides'
);

-- Cancelling ------------------------------------------------------------------

create temp table late as
select public.create_booking(
  '44444444-9999-4000-8000-000000000001',
  'ffffffff-2222-4000-8000-000000000001',
  (select at + interval '6 hours' from slot),
  'ffffffff-4444-4000-8000-000000000001',
  'ffffffff-1111-4000-8000-00000000000d') as r;

select is(
  (public.cancel_booking('44444444-9999-4000-8000-000000000002',
     (select (r ->> 'booking_id')::uuid from late), 'Customer called') ->> 'ok'),
  'true',
  'the salon cancels a booking'
);

-- THE POINT of cancelling: the chair is free again, because the exclusion
-- constraint counts only pending and confirmed.
select is(
  (public.create_booking(
     '44444444-9999-4000-8000-000000000003',
     'ffffffff-2222-4000-8000-000000000001',
     (select at + interval '6 hours' from slot),
     'ffffffff-4444-4000-8000-000000000001',
     'ffffffff-1111-4000-8000-00000000000c') ->> 'ok'),
  'true',
  'and the freed slot can be booked by someone else immediately'
);

select is(
  (public.cancel_booking('44444444-9999-4000-8000-000000000002',
     (select (r ->> 'booking_id')::uuid from late)) ->> 'booking_id'),
  (select r ->> 'booking_id' from late),
  'a replayed cancel returns the original result (RULES 9.3)'
);

select is(
  (public.cancel_booking('44444444-9999-4000-8000-000000000009',
     (select (r ->> 'booking_id')::uuid from booked)) ->> 'reason'),
  'already_completed',
  'a completed visit is history - cancelling it away is refused'
);

-- ---------------------------------------------------------------------------
-- As a customer of the same salon
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"ffffffff-aaaa-4000-8000-00000000000c",'
  '"app_role":"customer",'
  '"salon_id":"ffffffff-0000-4000-8000-000000000001"}',
  true
);

select is(
  (public.create_booking(
     '33333333-9999-4000-8000-000000000001',
     'ffffffff-2222-4000-8000-000000000001',
     (select at + interval '4 hours' from slot),
     'ffffffff-4444-4000-8000-000000000001') ->> 'ok'),
  'true',
  'a customer books their own appointment'
);

select is(
  (select customer_id from public.bookings
    where client_action_id = '33333333-9999-4000-8000-000000000001'),
  'ffffffff-1111-4000-8000-00000000000c'::uuid,
  'and it is THEIRS, resolved from the database rather than the request'
);

select throws_ok(
  $$select public.create_booking(
      '33333333-9999-4000-8000-000000000002',
      'ffffffff-2222-4000-8000-000000000001',
      now() + interval '5 days',
      'ffffffff-4444-4000-8000-000000000001',
      'ffffffff-1111-4000-8000-00000000000d')$$,
  '42501', null,
  'a customer cannot book in someone else''s name'
);

select throws_ok(
  $$select public.mark_visit_complete(
      '33333333-9999-4000-8000-000000000003',
      (select id from public.bookings
        where client_action_id = '33333333-9999-4000-8000-000000000001'))$$,
  '42501', null,
  'and cannot complete their own visit - that record is the salon''s to write'
);

select is(
  (public.cancel_booking('33333333-9999-4000-8000-000000000004',
     (select id from public.bookings
       where client_action_id = '33333333-9999-4000-8000-000000000001')) ->> 'ok'),
  'true',
  'but a customer CAN cancel their own appointment - no phone call needed'
);

-- Dev's booking, not Asha's. It exists and is refused BECAUSE it is not theirs,
-- and the refusal names no other customer.
select throws_ok(
  $$select public.cancel_booking('33333333-9999-4000-8000-000000000005',
      (select id from public.bookings
        where client_action_id = '11111111-9999-4000-8000-000000000004'))$$,
  '42501', null,
  'and cannot cancel someone else''s'
);

reset role;
select * from finish();
