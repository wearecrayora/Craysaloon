-- RELEASE GATE: age, and a guardian's consent for a child (0110).
--
-- Never skipped, never deleted, never narrowed to pass.
--
--   * an adult is recorded as an adult; a child is never recorded without a
--     named parent or guardian who confirmed
--   * a child gets no marketing - withdrawn at declaration, and refused from
--     every later path, including the customer's own toggle
--   * erasure takes the guardian's name with the rest of the identity

select plan(9);

insert into auth.users (id) values
  ('8b8b8b8b-aaaa-4000-8000-00000000000a'),
  ('8b8b8b8b-aaaa-4000-8000-00000000000b'),
  ('8b8b8b8b-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('8b8b8b8b-aaaa-4000-8000-00000000000f', 'age@crayora.test', 'Age Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('8b8b8b8b-0000-4000-8000-000000000001', 'Age Salon Ltd', 'Age Salon',
        'CRAY-AGESAN', 'active', 'Asia/Kolkata',
        '8b8b8b8b-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('8b8b8b8b-1111-4000-8000-00000000000a', '8b8b8b8b-0000-4000-8000-000000000001',
   '8b8b8b8b-aaaa-4000-8000-00000000000a', 'Adult', app.phone_hash('9788800011')),
  ('8b8b8b8b-1111-4000-8000-00000000000b', '8b8b8b8b-0000-4000-8000-000000000001',
   '8b8b8b8b-aaaa-4000-8000-00000000000b', 'Child', app.phone_hash('9788800012'));

select is(
  (public.record_age_declaration('8b8b8b8b-aaaa-4000-8000-00000000000a', '{"adult": true}') ->> 'minor'),
  'false',
  'an adult is recorded as an adult');

select is(
  (public.record_age_declaration('8b8b8b8b-aaaa-4000-8000-00000000000b', '{"adult": false}') ->> 'reason'),
  'guardian_required',
  'a child is never recorded without a parent or guardian');

select is(
  (public.record_age_declaration('8b8b8b8b-aaaa-4000-8000-00000000000b',
     '{"adult": false, "guardian_name": "Meena Rao"}') ->> 'reason'),
  'guardian_required',
  'and a name alone is not consent - the guardian must confirm');

select is(
  (public.record_age_declaration('8b8b8b8b-aaaa-4000-8000-00000000000b',
     '{"adult": false, "guardian_name": "Meena Rao", "guardian_confirms": true}') ->> 'minor'),
  'true',
  'a named guardian who confirms is recorded with the child');

select results_eq(
  $q$select purpose::text, granted from public.consents
      where customer_id = '8b8b8b8b-1111-4000-8000-00000000000b' order by purpose$q$,
  $q$values ('promotional', false), ('whatsapp', false)$q$,
  'and the child''s marketing consent is withdrawn on the record');

select throws_ok(
  $q$insert into public.consents (salon_id, customer_id, purpose, granted, source)
     values ('8b8b8b8b-0000-4000-8000-000000000001', '8b8b8b8b-1111-4000-8000-00000000000b',
             'promotional', true, 'app')$q$,
  '42501', NULL,
  'no path can grant a child offers or reminders - not even a direct insert');

select lives_ok(
  $q$insert into public.consents (salon_id, customer_id, purpose, granted, source)
     values ('8b8b8b8b-0000-4000-8000-000000000001', '8b8b8b8b-1111-4000-8000-00000000000a',
             'promotional', true, 'app')$q$,
  'while an adult still chooses freely');

select lives_ok(
  $q$insert into public.consents (salon_id, customer_id, purpose, granted, source)
     values ('8b8b8b8b-0000-4000-8000-000000000001', '8b8b8b8b-1111-4000-8000-00000000000b',
             'service_communication', true, 'app')$q$,
  'and a child still gets the messages that ARE the service');

select app_admin.anonymise_customer('8b8b8b8b-aaaa-4000-8000-00000000000f',
  '8b8b8b8b-1111-4000-8000-00000000000b', 'Guardian asked for the account to be deleted');

select is(
  (select guardian_name from public.customers where id = '8b8b8b8b-1111-4000-8000-00000000000b'),
  null,
  'erasure takes the guardian''s name with the rest of the identity');

select * from finish();
