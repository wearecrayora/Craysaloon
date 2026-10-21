-- RELEASE GATE: the customer's own profile (0118). Never skipped, never
-- deleted, never narrowed to pass.
--
--   * a customer changes their own name and language - and nobody else's
--   * never their phone: there is no path to the binding here (RULES 4)
--   * the language they choose is the language their messages use
--   * anything else is a correction REQUEST, against the salon, on the clock

select plan(12);

insert into auth.users (id) values
  ('9d9d9d9d-aaaa-4000-8000-00000000000a'),
  ('9d9d9d9d-aaaa-4000-8000-00000000000b'),
  ('9d9d9d9d-aaaa-4000-8000-0000000000a1'),
  ('9d9d9d9d-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('9d9d9d9d-aaaa-4000-8000-00000000000f', 'profile@crayora.test', 'Profile Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('9d9d9d9d-0000-4000-8000-000000000001', 'Profile Salon Ltd', 'Profile Salon',
        'CRAY-PRFSAN', 'active', 'Asia/Kolkata',
        '9d9d9d9d-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash)
values
  ('9d9d9d9d-1111-4000-8000-00000000000a', '9d9d9d9d-0000-4000-8000-000000000001',
   '9d9d9d9d-aaaa-4000-8000-00000000000a', 'Asha', '+919799900031', app.phone_hash('9799900031')),
  ('9d9d9d9d-1111-4000-8000-00000000000b', '9d9d9d9d-0000-4000-8000-000000000001',
   '9d9d9d9d-aaaa-4000-8000-00000000000b', 'Bhanu', '+919799900032', app.phone_hash('9799900032'));

insert into public.users (id, salon_id, role, name, phone, phone_hash, active, auth_user_id)
values ('9d9d9d9d-2222-4000-8000-0000000000a1', '9d9d9d9d-0000-4000-8000-000000000001', 'owner',
        'Owner', '+919799900041', app.phone_hash('9799900041'), true,
        '9d9d9d9d-aaaa-4000-8000-0000000000a1');

-- Asha, signed in.
select set_config('request.jwt.claims',
  '{"sub":"9d9d9d9d-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"9d9d9d9d-0000-4000-8000-000000000001","customer_id":"9d9d9d9d-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;

select is((public.update_my_profile('  Asha   Rao ', 'hi') ->> 'ok'), 'true',
  'a customer corrects their own name and sets their language');
select is((select name from public.customers where id = '9d9d9d9d-1111-4000-8000-00000000000a'),
  'Asha Rao', 'the name is tidied: one space between words, none at the ends');
select is((select language from public.customers where id = '9d9d9d9d-1111-4000-8000-00000000000a'),
  'hi', 'and the language is saved, for the messages that follow');
select is((public.update_my_profile('A') ->> 'reason'), 'name_length',
  'a name is at least two characters');
select is((public.update_my_profile('9799900031') ->> 'reason'), 'name_invalid',
  'a phone number is not a name');
select is((public.update_my_profile(null, 'fr') ->> 'reason'), 'language',
  'only a language the messages exist in');
select is((public.update_my_profile('Asha R', null) ->> 'ok'), 'true',
  'changing the name leaves the language alone');
select is((select language from public.customers where id = '9d9d9d9d-1111-4000-8000-00000000000a'),
  'hi', 'still Hindi');

select is((select name from public.customers where id = '9d9d9d9d-1111-4000-8000-00000000000b'),
  null, 'and nobody else''s row is touched - Asha cannot even read it');

select throws_ok(
  $q$update public.customers set phone = '+919799900099'
      where id = '9d9d9d9d-1111-4000-8000-00000000000a'$q$,
  '42501', NULL,
  'the phone number is the binding: no customer path changes it');

select is((public.request_data_right('correction', 'My number changed') ->> 'already'), 'false',
  'anything else is asked for, as a correction');
select is(
  (select due_at::date - requested_at::date from public.data_rights_requests
    where kind = 'correction'),
  30, 'against the salon, with the same 30 days as every other right');

select * from finish();
