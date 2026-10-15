-- RELEASE GATE: the birthday offer (PRD 10.5, 0113/0114), and the column
-- grants that came with it.
--
-- Never skipped, never deleted, never narrowed to pass.
--
--   * only the owner words the offer; only the customer adds their birthday -
--     day and month, never a child's
--   * on the day, from 10 am salon time, ONCE a year (a constraint, not a
--     check), and only with the offers consent
--   * the home shows the offer through the birthday month
--   * nobody edits a customer's columns directly beyond name and language

select plan(14);

insert into auth.users (id) values
  ('ab0ab0ab-aaaa-4000-8000-00000000000a'),
  ('ab0ab0ab-aaaa-4000-8000-00000000000b'),
  ('ab0ab0ab-aaaa-4000-8000-00000000000c'),
  ('ab0ab0ab-aaaa-4000-8000-0000000000a1'),
  ('ab0ab0ab-aaaa-4000-8000-0000000000a2'),
  ('ab0ab0ab-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('ab0ab0ab-aaaa-4000-8000-00000000000f', 'bday@crayora.test', 'Bday Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('ab0ab0ab-0000-4000-8000-000000000001', 'Bday Salon Ltd', 'Bday Salon',
        'CRAY-BDAYSN', 'active', 'Asia/Kolkata',
        'ab0ab0ab-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash, is_minor)
values
  ('ab0ab0ab-1111-4000-8000-00000000000a', 'ab0ab0ab-0000-4000-8000-000000000001',
   'ab0ab0ab-aaaa-4000-8000-00000000000a', 'Asha', app.phone_hash('9711100011'), false),
  ('ab0ab0ab-1111-4000-8000-00000000000b', 'ab0ab0ab-0000-4000-8000-000000000001',
   'ab0ab0ab-aaaa-4000-8000-00000000000b', 'Bhanu', app.phone_hash('9711100012'), false),
  ('ab0ab0ab-1111-4000-8000-00000000000c', 'ab0ab0ab-0000-4000-8000-000000000001',
   'ab0ab0ab-aaaa-4000-8000-00000000000c', 'Chotu', app.phone_hash('9711100013'), true);

insert into public.users (id, salon_id, role, name, phone, phone_hash, active, auth_user_id)
values
  ('ab0ab0ab-2222-4000-8000-0000000000a1', 'ab0ab0ab-0000-4000-8000-000000000001', 'owner',
   'Owner', '+919711100021', app.phone_hash('9711100021'), true, 'ab0ab0ab-aaaa-4000-8000-0000000000a1'),
  ('ab0ab0ab-2222-4000-8000-0000000000a2', 'ab0ab0ab-0000-4000-8000-000000000001', 'manager',
   'Manager', '+919711100022', app.phone_hash('9711100022'), true, 'ab0ab0ab-aaaa-4000-8000-0000000000a2');

-- Asha has said yes to offers; Bhanu has not.
insert into public.consents (salon_id, customer_id, purpose, granted, source)
values ('ab0ab0ab-0000-4000-8000-000000000001', 'ab0ab0ab-1111-4000-8000-00000000000a',
        'promotional', true, 'app');

-- ---------------------------------------------------------------------------
-- Who may set what
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"ab0ab0ab-aaaa-4000-8000-0000000000a2","role":"authenticated","app_role":"manager",'
  '"salon_id":"ab0ab0ab-0000-4000-8000-000000000001"}', true);
set local role authenticated;
select throws_ok($q$select public.set_birthday_offer('a free head massage')$q$, '42501', NULL,
  'only the owner words the birthday offer');
select throws_ok(
  $q$update public.customers set is_minor = false where id = 'ab0ab0ab-1111-4000-8000-00000000000c'$q$,
  '42501', NULL,
  'staff cannot rewrite a customer''s age - or any column beyond name and language (0113)');
reset role;

select set_config('request.jwt.claims',
  '{"sub":"ab0ab0ab-aaaa-4000-8000-0000000000a1","role":"authenticated","app_role":"owner",'
  '"salon_id":"ab0ab0ab-0000-4000-8000-000000000001"}', true);
set local role authenticated;
select is((public.set_birthday_offer('a free head massage') ->> 'ok'), 'true',
  'the owner words it');
reset role;

-- Asha, as herself.
select set_config('request.jwt.claims',
  '{"sub":"ab0ab0ab-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"ab0ab0ab-0000-4000-8000-000000000001","customer_id":"ab0ab0ab-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;
select is((public.set_my_birthday(2, 30) ->> 'reason'), 'invalid_date',
  'a day that does not exist is refused');
select throws_ok(
  $q$update public.customers set loyalty_points = 9999 where id = 'ab0ab0ab-1111-4000-8000-00000000000a'$q$,
  '42501', NULL,
  'a customer cannot write their own points, status or identity columns (0113)');
reset role;

-- Chotu is under 18.
select set_config('request.jwt.claims',
  '{"sub":"ab0ab0ab-aaaa-4000-8000-00000000000c","role":"authenticated","app_role":"customer",'
  '"salon_id":"ab0ab0ab-0000-4000-8000-000000000001","customer_id":"ab0ab0ab-1111-4000-8000-00000000000c"}',
  true);
set local role authenticated;
select is((public.set_my_birthday(6, 15) ->> 'reason'), 'minor',
  'a child is never asked for a date of birth');
reset role;
update public.customers set birthday = '2000-06-15' where id = 'ab0ab0ab-1111-4000-8000-00000000000c';
select is((select birthday from public.customers where id = 'ab0ab0ab-1111-4000-8000-00000000000c'),
  null::date, 'and whatever path tries, a child''s birthday is not kept');

-- ---------------------------------------------------------------------------
-- On the day
-- ---------------------------------------------------------------------------

-- Before 10 am in the salon's time: nothing, even on the day.
update public.salons set timezone = (
  select name from pg_timezone_names
   where name like '%/%' and extract(hour from now() at time zone name) between 1 and 8
   order by name limit 1)
 where id = 'ab0ab0ab-0000-4000-8000-000000000001';
update public.customers
   set birthday = make_date(2000,
         extract(month from now() at time zone (select timezone from public.salons where id = 'ab0ab0ab-0000-4000-8000-000000000001'))::int,
         extract(day from now() at time zone (select timezone from public.salons where id = 'ab0ab0ab-0000-4000-8000-000000000001'))::int)
 where id in ('ab0ab0ab-1111-4000-8000-00000000000a', 'ab0ab0ab-1111-4000-8000-00000000000b');
select is((app.queue_birthday_offers('ab0ab0ab-0000-4000-8000-000000000001') ->> 'queued')::int, 0,
  'no birthday wish before 10 am salon time');

-- After 10 am, on the day.
update public.salons set timezone = (
  select name from pg_timezone_names
   where name like '%/%' and extract(hour from now() at time zone name) between 11 and 22
   order by name limit 1)
 where id = 'ab0ab0ab-0000-4000-8000-000000000001';
update public.customers
   set birthday = make_date(2000,
         extract(month from now() at time zone (select timezone from public.salons where id = 'ab0ab0ab-0000-4000-8000-000000000001'))::int,
         extract(day from now() at time zone (select timezone from public.salons where id = 'ab0ab0ab-0000-4000-8000-000000000001'))::int)
 where id in ('ab0ab0ab-1111-4000-8000-00000000000a', 'ab0ab0ab-1111-4000-8000-00000000000b');

select is((app.queue_birthday_offers('ab0ab0ab-0000-4000-8000-000000000001') ->> 'queued')::int, 2,
  'on the day, both customers with a birthday are counted');
select is((app.queue_birthday_offers('ab0ab0ab-0000-4000-8000-000000000001') ->> 'queued')::int, 0,
  'and ONCE a year - the next minute''s scan sends nothing (a constraint, not a check)');

select results_eq(
  $q$select customer_id, status::text from public.notifications
      where purpose = 'birthday_offer' order by customer_id$q$,
  $q$values ('ab0ab0ab-1111-4000-8000-00000000000a'::uuid, 'pending'),
            ('ab0ab0ab-1111-4000-8000-00000000000b'::uuid, 'suppressed')$q$,
  'Asha, who said yes to offers, gets it; Bhanu, who did not, does not');

select matches(
  (select app.render_template(salon_id, template_key, 'en', 'push', params) from public.notifications
    where purpose = 'birthday_offer' and customer_id = 'ab0ab0ab-1111-4000-8000-00000000000a'
    order by created_at limit 1),
  '^Bday Salon: happy birthday, Asha! a free head massage is waiting for you this month\.$',
  'and it reads as a sentence, in the owner''s words');

-- Through the month, the home shows what to claim at the counter.
select set_config('request.jwt.claims',
  '{"sub":"ab0ab0ab-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"ab0ab0ab-0000-4000-8000-000000000001","customer_id":"ab0ab0ab-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;
select is((public.my_birthday_offer() ->> 'offer'), 'a free head massage',
  'through the birthday month, the home shows the offer to claim');
select is((public.set_my_birthday(null, null) ->> 'ok'), 'true',
  'and the customer can take their birthday away again, any time');
reset role;

select * from finish();
