-- GATE: "Activate anyway" (0116). The normal activation still refuses an
-- incomplete salon; only a super-admin, with a reason, can switch one on
-- before setup is done - and the audit says what was skipped.

select plan(6);

insert into auth.users (id) values
  ('d1d1d1d1-aaaa-4000-8000-00000000000a'),
  ('d1d1d1d1-aaaa-4000-8000-00000000000b');

insert into public.platform_admins (id, email, name, is_super, active) values
  ('d1d1d1d1-aaaa-4000-8000-00000000000a', 'super@crayora.test', 'Super', true, true),
  ('d1d1d1d1-aaaa-4000-8000-00000000000b', 'op@crayora.test', 'Operator', false, true);

-- A salon in setup: no setup fee recorded, no privacy contact, no Message Central.
insert into public.salons (id, legal_name, display_name, join_code, status, timezone)
values ('d1d1d1d1-0000-4000-8000-000000000001', 'Early Salon Ltd', 'Early Salon',
        'CRAY-EARYSN', 'setup', 'Asia/Kolkata');

select throws_ok(
  $q$select app_admin.activate_salon('d1d1d1d1-aaaa-4000-8000-00000000000b',
       'd1d1d1d1-0000-4000-8000-000000000001', null)$q$,
  'P0001', NULL,
  'the normal activation still refuses a salon whose setup is incomplete');

select throws_ok(
  $q$select app_admin.activate_salon_anyway('d1d1d1d1-aaaa-4000-8000-00000000000b',
       'd1d1d1d1-0000-4000-8000-000000000001', 'pilot')$q$,
  '42501', NULL,
  'activating anyway is for a super-admin only');

select throws_ok(
  $q$select app_admin.activate_salon_anyway('d1d1d1d1-aaaa-4000-8000-00000000000a',
       'd1d1d1d1-0000-4000-8000-000000000001', '  ')$q$,
  'P0001', NULL,
  'and never without a reason');

select is(
  (app_admin.activate_salon_anyway('d1d1d1d1-aaaa-4000-8000-00000000000a',
     'd1d1d1d1-0000-4000-8000-000000000001', 'Pilot salon, fee and contact this week') -> 'skipped'),
  '["setup_fee", "privacy_contact", "message_central"]'::jsonb,
  'a super-admin switches it on, and is told exactly what was skipped');

select is((select status::text from public.salons where id = 'd1d1d1d1-0000-4000-8000-000000000001'),
  'active', 'the salon is live');

select is(
  (select after_state -> 'skipped' from public.audit_log
    where action = 'salon.activated_anyway'
      and salon_id = 'd1d1d1d1-0000-4000-8000-000000000001'),
  '["setup_fee", "privacy_contact", "message_central"]'::jsonb,
  'and the audit log records what was skipped, with the reason');

select * from finish();
