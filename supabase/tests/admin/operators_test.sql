-- RELEASE GATE: switching a Crayora operator off (0115, from the first breach
-- rehearsal). Never skipped, never deleted, never narrowed to pass.
--
--   * only a super-admin does it, with a reason, and it is audited
--   * the operator's sessions end at once - and they can no longer act
--   * nobody switches themselves off

select plan(6);

insert into auth.users (id) values
  ('c0c0c0c0-aaaa-4000-8000-00000000000a'),   -- a super-admin
  ('c0c0c0c0-aaaa-4000-8000-00000000000b'),   -- an operator
  ('c0c0c0c0-aaaa-4000-8000-00000000000c');   -- another operator

insert into public.platform_admins (id, email, name, is_super, active) values
  ('c0c0c0c0-aaaa-4000-8000-00000000000a', 'super@crayora.test', 'Super', true, true),
  ('c0c0c0c0-aaaa-4000-8000-00000000000b', 'op@crayora.test', 'Operator', false, true),
  ('c0c0c0c0-aaaa-4000-8000-00000000000c', 'op2@crayora.test', 'Operator Two', false, true);

-- The operator is signed in - the stolen-phone case.
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('c0c0c0c0-5555-4000-8000-000000000001', 'c0c0c0c0-aaaa-4000-8000-00000000000b', now(), now());

select throws_ok(
  $q$select app_admin.set_operator_active('c0c0c0c0-aaaa-4000-8000-00000000000c',
       'c0c0c0c0-aaaa-4000-8000-00000000000b', false, 'not mine to do')$q$,
  '42501', NULL,
  'only a super-admin switches an operator off');

select throws_ok(
  $q$select app_admin.set_operator_active('c0c0c0c0-aaaa-4000-8000-00000000000a',
       'c0c0c0c0-aaaa-4000-8000-00000000000a', false, 'oops')$q$,
  'P0001', NULL,
  'nobody switches themselves off - an incident is not when to lose the person acting');

select is(
  (app_admin.set_operator_active('c0c0c0c0-aaaa-4000-8000-00000000000a',
     'c0c0c0c0-aaaa-4000-8000-00000000000b', false, 'Phone stolen, ticket 7') ->> 'sessions_ended')::int,
  1,
  'switching an operator off ends their live session at once');

select is((select count(*)::int from auth.sessions where user_id = 'c0c0c0c0-aaaa-4000-8000-00000000000b'),
  0, 'and no session of theirs is left');

select throws_ok(
  $q$select app_admin.assert_admin('c0c0c0c0-aaaa-4000-8000-00000000000b')$q$,
  '42501', NULL,
  'and they can no longer act in the console');

select is(
  (select reason from public.audit_log where action = 'operator.deactivated'),
  'Phone stolen, ticket 7',
  'and it is in the audit log, with its reason');

select * from finish();
