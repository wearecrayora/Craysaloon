-- RELEASE GATE: nomination (DPDP s.14, 0112).
--
-- Never skipped, never deleted, never narrowed to pass.
--
--   * a customer names, changes and removes their own nominee - nobody else can
--   * another customer cannot see it; the salon (the Data Fiduciary) can
--   * nothing reaches the table except through set_nominee / clear_nominee
--   * erasure takes the nominee with the identity

select plan(11);

insert into auth.users (id) values
  ('9c9c9c9c-aaaa-4000-8000-00000000000a'),
  ('9c9c9c9c-aaaa-4000-8000-00000000000b'),
  ('9c9c9c9c-aaaa-4000-8000-0000000000a1'),
  ('9c9c9c9c-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('9c9c9c9c-aaaa-4000-8000-00000000000f', 'nominee@crayora.test', 'Nominee Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('9c9c9c9c-0000-4000-8000-000000000001', 'Nominee Salon Ltd', 'Nominee Salon',
        'CRAY-NMNEES', 'active', 'Asia/Kolkata',
        '9c9c9c9c-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('9c9c9c9c-1111-4000-8000-00000000000a', '9c9c9c9c-0000-4000-8000-000000000001',
   '9c9c9c9c-aaaa-4000-8000-00000000000a', 'Asha', app.phone_hash('9799900011')),
  ('9c9c9c9c-1111-4000-8000-00000000000b', '9c9c9c9c-0000-4000-8000-000000000001',
   '9c9c9c9c-aaaa-4000-8000-00000000000b', 'Bhanu', app.phone_hash('9799900012'));

insert into public.users (id, salon_id, role, name, phone, phone_hash, active, auth_user_id)
values ('9c9c9c9c-2222-4000-8000-0000000000a1', '9c9c9c9c-0000-4000-8000-000000000001', 'owner',
        'Owner', '+919799900021', app.phone_hash('9799900021'), true,
        '9c9c9c9c-aaaa-4000-8000-0000000000a1');

-- Asha names her brother.
select set_config('request.jwt.claims',
  '{"sub":"9c9c9c9c-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"9c9c9c9c-0000-4000-8000-000000000001","customer_id":"9c9c9c9c-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;

select is((public.set_nominee('Ravi Rao', '9876500011', 'Brother') ->> 'ok'), 'true',
  'a customer names their nominee');
select is((public.my_nominee() ->> 'name'), 'Ravi Rao', 'and sees who they named');
select is((public.set_nominee('Ravi Rao', '12345', 'Brother') ->> 'reason'), 'invalid_phone',
  'a nominee needs a number someone can actually call');
select is((public.set_nominee('Ravi Kumar Rao', '9876500011', 'Brother') ->> 'ok'), 'true',
  'and can change it');
select is((select count(*)::int from public.customer_nominees), 1,
  'one nominee per customer, changed in place');
select throws_ok(
  $q$insert into public.customer_nominees (salon_id, customer_id, name, phone)
     values ('9c9c9c9c-0000-4000-8000-000000000001', '9c9c9c9c-1111-4000-8000-00000000000a',
             'Somebody', '+919876500099')$q$,
  '42501', NULL,
  'nothing reaches the table except through set_nominee');
reset role;

-- Bhanu cannot see it.
select set_config('request.jwt.claims',
  '{"sub":"9c9c9c9c-aaaa-4000-8000-00000000000b","role":"authenticated","app_role":"customer",'
  '"salon_id":"9c9c9c9c-0000-4000-8000-000000000001","customer_id":"9c9c9c9c-1111-4000-8000-00000000000b"}',
  true);
set local role authenticated;
select is((select count(*)::int from public.customer_nominees), 0,
  'another customer of the same salon cannot see it');
reset role;

-- The salon can - it is who a nominee comes to - but cannot name one for anybody.
select set_config('request.jwt.claims',
  '{"sub":"9c9c9c9c-aaaa-4000-8000-0000000000a1","role":"authenticated","app_role":"owner",'
  '"salon_id":"9c9c9c9c-0000-4000-8000-000000000001"}', true);
set local role authenticated;
select is((select count(*)::int from public.customer_nominees), 1,
  'the salon, as the Data Fiduciary, can see a customer''s nominee');
select throws_ok($q$select public.set_nominee('Someone', '9876500012', null)$q$, '42501', NULL,
  'but no staff path names a nominee for a customer');
reset role;

-- Asha removes it; then names one again, and is erased.
select set_config('request.jwt.claims',
  '{"sub":"9c9c9c9c-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"9c9c9c9c-0000-4000-8000-000000000001","customer_id":"9c9c9c9c-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;
select public.clear_nominee();
select is(public.my_nominee(), null::jsonb, 'removing a nominee is one call');
select public.set_nominee('Ravi Rao', '9876500011', 'Brother');
reset role;

select app_admin.anonymise_customer('9c9c9c9c-aaaa-4000-8000-00000000000f',
  '9c9c9c9c-1111-4000-8000-00000000000a', 'Customer asked for the account to be deleted');
select is((select count(*)::int from public.customer_nominees
            where customer_id = '9c9c9c9c-1111-4000-8000-00000000000a'), 0,
  'erasure takes the nominee with the identity');

select * from finish();
