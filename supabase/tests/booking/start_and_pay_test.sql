-- RELEASE GATE: starting a service with the customer's code, and the customer
-- paying their own bill (requested 29 Sep 2026; 0083-0086)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- The properties this feature rests on, each of which fails quietly:
--
--   * STAFF CANNOT READ A START CODE - or typing it proves nothing
--   * a wrong code is refused, and five lock it; a replayed guess costs nothing
--   * starting WITHOUT the code is allowed and never silent: the reason is kept
--     and the owner sees it
--   * an IN-PROGRESS chair is not free - before 0084 the double-booking
--     constraint covered pending and confirmed only
--   * a Razorpay payment for a BILL settles the visit and does NOT credit the
--     wallet; the amount is always the server's
--   * "I'll pay at the counter" settles nothing - staff confirm the cash
--   * "your bill is ready" goes to a phone that can take a push, and never
--     escalates to a channel the salon pays for

select plan(28);

insert into auth.users (id) values
  ('66666666-aaaa-4000-8000-00000000000a'),
  ('66666666-aaaa-4000-8000-00000000000c'),
  ('66666666-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('66666666-aaaa-4000-8000-00000000000f', 'start@crayora.test', 'Start Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('66666666-0000-4000-8000-000000000001', 'Start Salon Ltd', 'Start Salon',
        'CRAY-STRTPY', 'active', 'Asia/Kolkata',
        '66666666-aaaa-4000-8000-00000000000f', now());

-- Asha has the app and a live push token. Bhanu was booked by phone: no app.
-- Chitra has the app too, and a wallet - and must never reach Asha's bill.
insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('66666666-1111-4000-8000-00000000000a', '66666666-0000-4000-8000-000000000001',
   '66666666-aaaa-4000-8000-00000000000a', 'Asha', app.phone_hash('9755500011')),
  ('66666666-1111-4000-8000-00000000000b', '66666666-0000-4000-8000-000000000001',
   null, 'Bhanu', app.phone_hash('9755500012')),
  ('66666666-1111-4000-8000-00000000000c', '66666666-0000-4000-8000-000000000001',
   '66666666-aaaa-4000-8000-00000000000c', 'Chitra', app.phone_hash('9755500013'));

insert into public.notification_tokens (salon_id, customer_id, token, platform)
values ('66666666-0000-4000-8000-000000000001', '66666666-1111-4000-8000-00000000000a',
        'fcm-token-asha-start', 'android');

insert into public.staff (id, salon_id, name, active)
values ('66666666-3333-4000-8000-000000000001', '66666666-0000-4000-8000-000000000001',
        'Start stylist', true);

-- Today, in the SALON's day, at fixed hours - so a run near midnight does not
-- push a booking into tomorrow.
create temp table at_hour as
  select h, ((app.salon_day('66666666-0000-4000-8000-000000000001', now())::timestamp
             + make_interval(hours => h)) at time zone 'Asia/Kolkata') as t
    from generate_series(9, 18) as h;
grant select on at_hour to public;

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status, total_paise)
select v.id::uuid, '66666666-0000-4000-8000-000000000001', v.customer::uuid,
       '66666666-3333-4000-8000-000000000001',
       (select t from at_hour where h = v.hr),
       (select t from at_hour where h = v.hr) + interval '45 minutes',
       'confirmed', 45000
  from (values
    -- started WITH the code, then completed and paid
    ('66666666-4444-4000-8000-000000000001', '66666666-1111-4000-8000-00000000000a', 10),
    -- five wrong guesses
    ('66666666-4444-4000-8000-000000000002', '66666666-1111-4000-8000-00000000000a', 12),
    -- a customer with no app
    ('66666666-4444-4000-8000-000000000003', '66666666-1111-4000-8000-00000000000b', 14),
    -- completed without ever being started
    ('66666666-4444-4000-8000-000000000004', '66666666-1111-4000-8000-00000000000a', 16)
  ) as v(id, customer, hr);

-- A real service: completing a visit schedules its reminder, which points here.
insert into public.services (id, salon_id, name, price_paise, duration_minutes, active)
values ('66666666-5555-4000-8000-000000000001', '66666666-0000-4000-8000-000000000001',
        'Haircut', 45000, 45, true);

insert into public.booking_items (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
select b.id, b.salon_id, 'service', '66666666-5555-4000-8000-000000000001', 'Haircut', 45000, 45
  from public.bookings b where b.salon_id = '66666666-0000-4000-8000-000000000001';

-- Asha has Rs 200 in her wallet: less than the Rs 450 bill, which is the case
-- the whole wallet design exists for.
insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
values ('66666666-1111-4000-8000-00000000000a', '66666666-0000-4000-8000-000000000001', 20000);
insert into public.wallet_lots (salon_id, customer_id, kind, amount_paise, remaining_paise)
values ('66666666-0000-4000-8000-000000000001', '66666666-1111-4000-8000-00000000000a',
        'paid', 20000, 20000);
insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
values ('66666666-1111-4000-8000-00000000000c', '66666666-0000-4000-8000-000000000001', 10000);
insert into public.wallet_lots (salon_id, customer_id, kind, amount_paise, remaining_paise)
values ('66666666-0000-4000-8000-000000000001', '66666666-1111-4000-8000-00000000000c',
        'paid', 10000, 10000);

-- ---------------------------------------------------------------------------
-- The customer sees their code; staff never can
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000a","app_role":"customer",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

create temp table today as select public.my_visits_today() as v;
grant select on today to public;

reset role;

create temp table codes as
  select (e ->> 'booking_id')::uuid as booking_id, e ->> 'start_code' as code
    from today, jsonb_array_elements(today.v) e;
grant select on codes to public;

select matches(
  (select code from codes where booking_id = '66666666-4444-4000-8000-000000000001'),
  '^[0-9]{4}$',
  'the customer''s app shows a 4-digit start code for today''s booking');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

select throws_ok(
  $q$select count(*) from public.booking_start_codes$q$,
  '42501', null,
  'STAFF CANNOT READ A START CODE - not even the owner. If they could, typing it would prove nothing');

-- ---------------------------------------------------------------------------
-- Starting with the code
-- ---------------------------------------------------------------------------

select is(
  (public.start_service('66666666-9999-4000-8000-000000000001',
                        '66666666-4444-4000-8000-000000000001',
                        (select case when code = '0000' then '1111' else '0000' end
                           from codes where booking_id = '66666666-4444-4000-8000-000000000001'))
     ->> 'reason'),
  'wrong_code',
  'a wrong code is refused');

select is(
  (public.start_service('66666666-9999-4000-8000-000000000001',
                        '66666666-4444-4000-8000-000000000001', 'anything') ->> 'reason'),
  'wrong_code',
  'and REPLAYING that wrong attempt returns the same refusal without spending a second guess');

select is(
  (public.start_service('66666666-9999-4000-8000-000000000002',
                        '66666666-4444-4000-8000-000000000001',
                        (select code from codes
                          where booking_id = '66666666-4444-4000-8000-000000000001'))
     ->> 'method'),
  'code',
  'the customer''s own code starts the service');

select is(
  (select status::text || '/' || start_method from public.bookings
    where id = '66666666-4444-4000-8000-000000000001'),
  'in_progress/code',
  'the booking is in progress, started with the code');

reset role;

-- The replayed wrong guess really did not count.
select is(
  (select attempts from public.booking_start_codes
    where booking_id = '66666666-4444-4000-8000-000000000001'),
  1,
  'one wrong guess recorded, not two - the replay was free');

-- ---------------------------------------------------------------------------
-- An occupied chair is not free
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$insert into public.bookings (salon_id, customer_id, staff_id, starts_at, ends_at, status)
     select '66666666-0000-4000-8000-000000000001', '66666666-1111-4000-8000-00000000000b',
            '66666666-3333-4000-8000-000000000001',
            t + interval '15 minutes', t + interval '45 minutes', 'confirmed'
       from at_hour where h = 10$q$,
  '23P01', null,
  'the chair of a service IN PROGRESS cannot be booked over - the constraint had to learn the new status');

select ok(
  (select prosrc ~ 'in_progress' from pg_proc
    where proname = 'available_slots'
      and pronamespace = 'app'::regnamespace),
  'and the slot finder does not offer it either');

-- ---------------------------------------------------------------------------
-- Five wrong guesses lock it; starting without it says why
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

select public.start_service(gen_random_uuid(), '66666666-4444-4000-8000-000000000002',
         (select case when code = '0000' then '1111' else '0000' end
            from codes where booking_id = '66666666-4444-4000-8000-000000000002'))
  from generate_series(1, 4);

select is(
  (public.start_service(gen_random_uuid(), '66666666-4444-4000-8000-000000000002',
     (select case when code = '0000' then '1111' else '0000' end
        from codes where booking_id = '66666666-4444-4000-8000-000000000002')) ->> 'reason'),
  'code_locked',
  'the fifth wrong guess LOCKS the code - 1 in 2,000 odds, not 1 in 10');

select is(
  (public.start_service(gen_random_uuid(), '66666666-4444-4000-8000-000000000002',
     (select code from codes where booking_id = '66666666-4444-4000-8000-000000000002'))
     ->> 'reason'),
  'code_locked',
  'and once locked, even the right code is refused');

select is(
  (public.start_service(gen_random_uuid(), '66666666-4444-4000-8000-000000000002') ->> 'note'),
  'code_locked',
  'the stylist starts without it - nobody is turned away - and the REASON is kept');

select is(
  (public.start_service(gen_random_uuid(), '66666666-4444-4000-8000-000000000003') ->> 'note'),
  'customer_has_no_app',
  'a customer with no app is started without a code, and the booking says why');

-- ---------------------------------------------------------------------------
-- Work completed
-- ---------------------------------------------------------------------------

create temp table done as
  select public.mark_visit_complete('66666666-9999-4000-8000-000000000011',
                                    '66666666-4444-4000-8000-000000000001') as r;
grant select on done to public;

select is((select r ->> 'ok' from done), 'true', 'the stylist marks the work complete');

-- A booking completed without ever being started began without the code.
select public.mark_visit_complete('66666666-9999-4000-8000-000000000014',
                                  '66666666-4444-4000-8000-000000000004');

reset role;

select is(
  (select start_method || '/' || start_note from public.bookings
    where id = '66666666-4444-4000-8000-000000000004'),
  'without_code/completed_without_start',
  'completing a booking that was never started is counted as a start without the code');

select is(
  (select count(*)::int from public.notifications
    where purpose = 'visit_completed'
      and customer_id = '66666666-1111-4000-8000-00000000000a'),
  2,
  'the customer is told "your bill is ready" - one notice per completed visit');

select is(app.escalation_window('visit_completed'), null,
  'and that notice NEVER escalates to a paid channel - they are in the room');

-- ---------------------------------------------------------------------------
-- The customer pays: wallet first, then UPI
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000a","app_role":"customer",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

create temp table bill as
  select e ->> 'visit_id' as visit_id, (e ->> 'due_paise')::bigint as due
    from jsonb_array_elements(public.my_bills()) e
   where (e ->> 'visit_id')::uuid = (select (r ->> 'visit_id')::uuid from done);
grant select on bill to public;

select is((select due from bill), 45000::bigint, 'the bill is in the customer''s app, for Rs 450');

create temp table fromwallet as
  select public.pay_bill_from_wallet('66666666-9999-4000-8000-000000000021',
                                     (select visit_id::uuid from bill)) as r;
grant select on fromwallet to public;

select is((select r ->> 'from_wallet_paise' from fromwallet), '20000',
  'the wallet pays as far as it goes - all Rs 200');

select is((select r ->> 'payment_status' from fromwallet), 'partial',
  'which leaves the bill partly paid, not paid');

create temp table upi as
  select public.start_bill_payment('66666666-9999-4000-8000-000000000022',
                                   (select visit_id::uuid from bill)) as r;
grant select on upi to public;

select is((select r ->> 'amount_paise' from upi), '25000',
  'the UPI payment is for what is LEFT - Rs 250 - and the server decided it');

reset role;

-- Razorpay's webhook arrives.
select is(
  (app.record_payment_captured((select (r ->> 'payment_id')::uuid from upi),
                               'pay_start_test', 25000) ->> 'settled'),
  'paid',
  'a captured payment for a BILL settles the visit');

select is(
  (select count(*)::int from public.wallet_transactions
    where customer_id = '66666666-1111-4000-8000-00000000000a'
      and kind in ('credit_topup', 'credit_bonus')),
  0,
  'and credits NOTHING to the wallet - a haircut paid by UPI is not wallet credit');

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '66666666-1111-4000-8000-00000000000a'),
  0::bigint,
  'the wallet holds exactly what is left after paying the bill: nothing');

-- ---------------------------------------------------------------------------
-- Cash at the counter settles nothing; nobody pays someone else's bill
-- ---------------------------------------------------------------------------

-- The visit of the booking completed without being started: unpaid, and Asha's.
create temp table other_bill as
  select v.id as visit_id from public.visits v
   where v.booking_id = '66666666-4444-4000-8000-000000000004';
grant select on other_bill to public;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000a","app_role":"customer",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

select is(
  (public.request_counter_payment((select visit_id from other_bill)) ->> 'ok'),
  'true',
  'the customer can say they will pay at the counter');

reset role;

select is(
  (select payment_status::text from public.visits
    where id = (select visit_id from other_bill)),
  'unpaid',
  'and that settles NOTHING - staff confirm the cash (decision of 29 Sep 2026)');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000c","app_role":"customer",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

select is(
  (public.pay_bill_from_wallet(gen_random_uuid(), (select visit_id from other_bill)) ->> 'reason'),
  'no_such_bill',
  'another customer cannot pay - or even see - someone else''s bill');

reset role;

-- ---------------------------------------------------------------------------
-- The owner sees every start without the code
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"66666666-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"66666666-0000-4000-8000-000000000001"}', true);

select is(
  (public.owner_dashboard() -> 'start_exceptions' ->> 'month')::int,
  3,
  'the owner sees all three starts without a code: locked, no app, never started');

reset role;

select * from finish();
