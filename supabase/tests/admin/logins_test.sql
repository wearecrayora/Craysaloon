-- GATE: managers and stylists get a login (0105).
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- Before 0105 nothing could create a manager or stylist login - the owner's,
-- made at provisioning, was the only one a salon could ever have.

select plan(9);

select set_config('app.phone_hash_pepper', 'logins-test-pepper', true);

insert into auth.users (id) values ('10501050-aaaa-4000-8000-00000000000f');
insert into public.platform_admins (id, email, name, is_super, active)
values ('10501050-aaaa-4000-8000-00000000000f', 'logins@crayora.test', 'Logins Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at)
values
  ('10501050-0000-4000-8000-000000000001', 'Login Salon Ltd', 'Login Salon', 'CRAY-KGNQ22',
   'active', '10501050-aaaa-4000-8000-00000000000f', now()),
  ('10501050-0000-4000-8000-000000000002', 'Other Salon Ltd', 'Other Salon', 'CRAY-KGNQ33',
   'active', '10501050-aaaa-4000-8000-00000000000f', now());

insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
values ('10501050-1111-4000-8000-000000000001', '10501050-0000-4000-8000-000000000001',
        'owner', 'Owner', '9810501050', app.phone_hash('9810501050'), true);

create temp table stylist as
  select app_admin.add_salon_login('10501050-aaaa-4000-8000-00000000000f',
           '10501050-0000-4000-8000-000000000001', 'Priya', '+91 98105 01051', 'staff') as id;

select results_eq(
  $q$select role::text, name, phone, active from public.users where id = (select id from stylist)$q$,
  $q$values ('staff', 'Priya', '9810501051', true)$q$,
  'Crayora gives a stylist a login: the salon, their name, their own number');

select is(
  (select app.resolve_otp_sender('9810501051') ->> 'salon_id')::uuid,
  '10501050-0000-4000-8000-000000000001'::uuid,
  'and that number now signs in to that salon, like the owner''s does');

select throws_ok(
  $q$select app_admin.add_salon_login('10501050-aaaa-4000-8000-00000000000f',
       '10501050-0000-4000-8000-000000000002', 'Priya again', '9810501051', 'manager')$q$,
  null, null,
  'one number, one salon login - a second salon for the same number is refused');

select throws_ok(
  $q$select app_admin.add_salon_login('10501050-aaaa-4000-8000-00000000000f',
       '10501050-0000-4000-8000-000000000001', 'Usurper', '9810501059', 'owner')$q$,
  null, null,
  'an owner is never added here - the owner is set at provisioning');

select throws_ok(
  $q$select app_admin.set_salon_login_active('10501050-aaaa-4000-8000-00000000000f',
       '10501050-1111-4000-8000-000000000001', false, 'testing')$q$,
  null, null,
  'and the owner''s login is never switched off here');

select app_admin.set_salon_login_active('10501050-aaaa-4000-8000-00000000000f',
  (select id from stylist), false, 'Left the salon');

select is(
  (select active from public.users where id = (select id from stylist)),
  false,
  'a stylist who leaves is switched off, with a reason');

select is(
  (select count(*)::int from public.audit_log
    where actor_user_id = '10501050-aaaa-4000-8000-00000000000f'
      and action in ('login.added', 'login.deactivated')),
  2,
  'both acts are in the audit trail');

select is(
  (select app.resolve_otp_sender('9810501051') ->> 'salon_id'),
  null,
  'and their number no longer signs in to the salon');

select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_admin' and p.proname in ('add_salon_login', 'set_salon_login_active')
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0,
  'no salon user can call either - logins are Crayora''s to give');

select * from finish();
