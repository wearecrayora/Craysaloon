-- RELEASE GATE: the admin plane
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- RULES 6 makes four promises that are only worth anything if they are
-- mechanical: provisioning is one transaction, activation is a deliberate
-- human action, every admin mutation is audited in the same transaction, and
-- no credential can be read back. Each is asserted here against the catalogue,
-- so a function added tomorrow is covered tomorrow.

select plan(19);

select set_config('app.phone_hash_pepper', 'admin-test-pepper', true);

-- platform_admins.id references auth.users: a Crayora operator is an Auth
-- account like anyone else, it just never carries a salon_id claim (RULES 6.7).
insert into auth.users (id) values
  ('11111111-aaaa-4000-8000-000000000001'),
  ('11111111-aaaa-4000-8000-000000000002');

insert into public.platform_admins (id, email, name, is_super, active) values
  ('11111111-aaaa-4000-8000-000000000001', 'op@crayora.test',   'Operator', false, true),
  ('11111111-aaaa-4000-8000-000000000002', 'gone@crayora.test', 'Departed', false, false);

-- ---------------------------------------------------------------------------
-- Separation: the admin plane is not reachable from a tenant role
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_admin'
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0,
  'no app_admin function is executable by anon or authenticated'
);

select is(
  (select count(*)::int
     from pg_namespace n
    where n.nspname = 'app_admin'
      and (has_schema_privilege('authenticated', n.oid, 'USAGE')
        or has_schema_privilege('anon', n.oid, 'USAGE'))),
  0,
  'no tenant role has USAGE on the app_admin schema either'
);

-- The admin plane must not leak into PostgREST's schema. A provisioning
-- function in `public` would be one missing grant away from being callable.
select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~* 'provision|activate_salon|set_integration_secret'),
  0,
  'no admin-plane function has been defined in the public schema'
);

-- ---------------------------------------------------------------------------
-- RULES 6.5: the audit cannot be forgotten
-- ---------------------------------------------------------------------------
--
-- Catalogue-driven against the function source. A new mutating function that
-- does not audit fails here on the day it is written.

-- `as materialized` is load-bearing, not style. Without it the planner pushes
-- the pg_get_functiondef() filter down to the pg_proc scan and evaluates it
-- BEFORE the namespace join - which means calling it on every function in the
-- catalogue, including aggregates, and failing with
-- `"array_agg" is an aggregate function`. The CTE fences the namespace
-- restriction so the expensive call only ever sees app_admin rows.
select is(
  (with admin_fns as materialized (
     select p.oid, p.proname
       from pg_proc p
      where p.pronamespace = 'app_admin'::regnamespace
   )
   select count(*)::int
     from admin_fns
    where proname not in (
        -- The audit writer itself.
        'audit',
        -- Read-only: they inspect or generate, they mutate nothing.
        'assert_admin', 'generate_join_code',
        -- Infrastructure: it changes grants, not tenant data, and is called
        -- from migrations rather than from the console (0020).
        'close_privileges'
      )
      and pg_get_functiondef(oid) !~ 'app_admin[.]audit'),
  0,
  'every mutating app_admin function writes audit_log in the same transaction'
);

-- A stale exemption is a hole waiting for a name collision.
select is(
  (select count(*)::int
     from unnest(array['audit', 'assert_admin', 'generate_join_code',
                 'close_privileges']) as e(name)
    where not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'app_admin' and p.proname = e.name)),
  0,
  'every documented audit exemption still names a function that exists'
);

-- ---------------------------------------------------------------------------
-- ARCHITECTURE 8.2: write-only credentials
-- ---------------------------------------------------------------------------

select is(
  (with admin_fns as materialized (
     select p.oid from pg_proc p where p.pronamespace = 'app_admin'::regnamespace
   )
   select count(*)::int from admin_fns
    where pg_get_functiondef(oid) ~* 'decrypted_secret'),
  0,
  'no app_admin function reads a decrypted secret - there is no read path'
);

-- ---------------------------------------------------------------------------
-- RULES 6.2: provisioning is ONE transaction
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_admin.provision_salon(
      '11111111-aaaa-4000-8000-000000000001',
      'Provision Test Pvt Ltd', 'Provision Test',
      'Owner Name', '9811111111', 'starter', 1500000)$$,
  'an operator can provision a salon in one call'
);

select is(
  (select status::text from public.salons where display_name = 'Provision Test'),
  'setup',
  'a provisioned salon starts in setup - provisioning does not switch it on'
);

select is(
  (select count(*)::int from public.salon_integrations si
     join public.salons s on s.id = si.salon_id
    where s.display_name = 'Provision Test' and si.status = 'missing'),
  4,
  'all four integrations exist as `missing`, so readiness is driven by real rows'
);

select is(
  (select auth_user_id is null from public.users u
     join public.salons s on s.id = u.salon_id
    where s.display_name = 'Provision Test'),
  true,
  'the owner is invited but not yet attached to an Auth user'
);

-- THE atomicity test. An invalid owner phone raises inside app.phone_hash,
-- AFTER the salon and subscription rows have been inserted. If provisioning
-- were a sequence of separate calls, the salon would survive.
select throws_ok(
  $$select app_admin.provision_salon(
      '11111111-aaaa-4000-8000-000000000001',
      'Half Provisioned Ltd', 'Half Provisioned',
      'Owner', '12345', 'starter', 100000)$$,
  'P0001', null,
  'provisioning with a bad owner phone raises'
);

select is(
  (select count(*)::int from public.salons where display_name = 'Half Provisioned'),
  0,
  'and leaves NOTHING behind - no salon, no join code, no subscription'
);

-- ---------------------------------------------------------------------------
-- RULES 6.3: activation is a deliberate human action, through one door
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_admin.set_salon_status(
      '11111111-aaaa-4000-8000-000000000001',
      (select id from public.salons where display_name = 'Provision Test'),
      'active', 'trying the back door')$$,
  'P0001', null,
  'set_salon_status cannot reach `active` - activate_salon is the only door'
);

select throws_ok(
  $$select app_admin.provision_salon(
      '11111111-aaaa-4000-8000-000000000002',
      'Ghost Ltd', 'Ghost', 'Owner', '9822222222', 'starter', 0)$$,
  '42501', null,
  'a deactivated platform admin cannot provision'
);

-- ---------------------------------------------------------------------------
-- RULES 6.4: the setup fee is collected offline, so the reference is the only
-- evidence it was collected at all
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_admin.record_setup_fee(
      '11111111-aaaa-4000-8000-000000000001',
      (select id from public.salons where display_name = 'Provision Test'),
      'paid', null)$$,
  'P0001', null,
  'a paid setup fee without a reference is refused'
);

-- ---------------------------------------------------------------------------
-- PRD 6.3: the join code alphabet is unambiguous in print
-- ---------------------------------------------------------------------------
--
-- The constraint written in 0003 excluded I and O but allowed L, which a
-- customer reading a printed sticker cannot reliably tell from 1.

select is(
  (select count(*)::int
     from generate_series(1, 200) as g
    where app_admin.generate_join_code() !~ '^CRAY-[A-HJKMNP-Z2-9]{6}$'),
  0,
  '200 generated codes all avoid 0, 1, I, L and O'
);

-- ---------------------------------------------------------------------------
-- Branding publish: the version is what re-themes installed apps
-- ---------------------------------------------------------------------------

select is(
  app_admin.publish_branding(
    '11111111-aaaa-4000-8000-000000000001',
    (select id from public.salons where display_name = 'Provision Test'),
    '{"displayName":"Provision Test","brand":{"light":{"primary":"#1f6f5c"}}}'::jsonb),
  1,
  'the first publish is version 1'
);

-- Monotonic on purpose: an app that has seen version 7 must never be handed a
-- different version 7.
select is(
  app_admin.publish_branding(
    '11111111-aaaa-4000-8000-000000000001',
    (select id from public.salons where display_name = 'Provision Test'),
    '{"displayName":"Provision Test","brand":{"light":{"primary":"#123456"}}}'::jsonb),
  2,
  'republishing bumps the version rather than overwriting it'
);

select throws_ok(
  $$select app_admin.publish_branding(
      '11111111-aaaa-4000-8000-000000000001',
      (select id from public.salons where display_name = 'Provision Test'),
      '{"brand":{}}'::jsonb)$$,
  'P0001', null,
  'branding without a displayName is refused - every message renders it'
);

select * from finish();
