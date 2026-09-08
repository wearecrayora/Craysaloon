-- RELEASE GATE: binding exclusivity
--
-- Never skipped, never deleted, never narrowed to pass (RULES.md 12).
--
-- "One phone number has exactly one active salon binding" is the second most
-- important invariant in the product, after tenant isolation. It is enforced
-- by a PRIMARY KEY, not by application code that could be bypassed, forgotten,
-- or worked around by a future session in a hurry - so this test exercises the
-- constraint directly rather than any function that happens to call it.

select plan(13);

select set_config('app.phone_hash_pepper', 'binding-test-pepper', true);

insert into auth.users (id) values
  ('eeeeeeee-1111-4000-8000-00000000000a'),
  ('eeeeeeee-1111-4000-8000-00000000000b');

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values
  ('eeeeeeee-0000-4000-8000-000000000001', 'Bind A', 'Bind A',
   'CRAY-NNNAAA', 'active', '00000000-0000-4000-8000-00000000000a', now()),
  ('ffffffff-0000-4000-8000-000000000002', 'Bind B', 'Bind B',
   'CRAY-NNNBBB', 'active', '00000000-0000-4000-8000-00000000000b', now());

insert into public.customers (id, salon_id, name, phone_hash) values
  ('eeeeeeee-2222-4000-8000-000000000001',
   'eeeeeeee-0000-4000-8000-000000000001', 'At A', app.phone_hash('9600000001')),
  ('ffffffff-2222-4000-8000-000000000002',
   'ffffffff-0000-4000-8000-000000000002', 'At B', app.phone_hash('9600000001'));

-- ---------------------------------------------------------------------------
-- The invariant itself
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into public.customer_identities
      (phone_hash, auth_user_id, salon_id, customer_id)
    values (app.phone_hash('9600000001'),
            'eeeeeeee-1111-4000-8000-00000000000a',
            'eeeeeeee-0000-4000-8000-000000000001',
            'eeeeeeee-2222-4000-8000-000000000001')$$,
  'a phone with no existing binding can bind'
);

-- THE test. Same human, second salon, different auth user - refused.
select throws_ok(
  $$insert into public.customer_identities
      (phone_hash, auth_user_id, salon_id, customer_id)
    values (app.phone_hash('9600000001'),
            'eeeeeeee-1111-4000-8000-00000000000b',
            'ffffffff-0000-4000-8000-000000000002',
            'ffffffff-2222-4000-8000-000000000002')$$,
  '23505', null,
  'a phone already bound to salon A CANNOT bind to salon B'
);

-- The bug this repo actually had: phone_hash only stripped non-digits, so
-- '+91 98765 43210' and '9876543210' produced different hashes and the same
-- person could bind twice. Every accepted format must collapse to one hash or
-- the primary key above protects nothing.
select throws_ok(
  $$insert into public.customer_identities
      (phone_hash, auth_user_id, salon_id, customer_id)
    values (app.phone_hash('+91 96000 00001'),
            'eeeeeeee-1111-4000-8000-00000000000b',
            'ffffffff-0000-4000-8000-000000000002',
            'ffffffff-2222-4000-8000-000000000002')$$,
  '23505', null,
  'the SAME number in +91 format is still refused - formats collapse to one hash'
);

-- Every prefix form a real person might type. The 0091 case was missing until
-- this test was written, and it would have produced a second identity for the
-- same human (migration 0015).
select is(
  app.phone_hash('9600000001'), app.phone_hash('0091 9600000001'),
  'the 0091 international prefix reduces to the same canonical hash'
);

select is(
  app.phone_hash('9600000001'), app.phone_hash('091-9600000001'),
  'the 091 prefix and hyphens reduce to the same canonical hash'
);

select throws_ok(
  $$select app.phone_hash('1234567890')$$,
  null, null,
  'an invalid number RAISES rather than becoming a silent second identity'
);

-- One auth user cannot hold two bindings either, from the other direction.
select throws_ok(
  $$insert into public.customer_identities
      (phone_hash, auth_user_id, salon_id, customer_id)
    values (app.phone_hash('9600000009'),
            'eeeeeeee-1111-4000-8000-00000000000a',
            'ffffffff-0000-4000-8000-000000000002',
            'ffffffff-2222-4000-8000-000000000002')$$,
  '23505', null,
  'one auth user cannot hold two bindings'
);

-- ---------------------------------------------------------------------------
-- The audit trail cannot be edited or left incomplete
-- ---------------------------------------------------------------------------

-- acknowledged_balance_paise is REQUIRED on a transfer. That requirement is
-- what forces support to look the balance up and tell the customer before
-- moving them - a policy enforced by a column, not by a training document.
select throws_ok(
  $$insert into public.binding_events
      (phone_hash, kind, from_salon_id, to_salon_id, actor_admin_id, reason)
    values (app.phone_hash('9600000001'), 'transfer',
            'eeeeeeee-0000-4000-8000-000000000001',
            'ffffffff-0000-4000-8000-000000000002',
            null, 'customer asked')$$,
  '23514', null,
  'a transfer without the acknowledged balance is rejected'
);

select lives_ok(
  $$insert into public.binding_events
      (phone_hash, kind, from_salon_id, to_salon_id, reason,
       acknowledged_balance_paise)
    values (app.phone_hash('9600000001'), 'transfer',
            'eeeeeeee-0000-4000-8000-000000000001',
            'ffffffff-0000-4000-8000-000000000002',
            'customer asked', 55000)$$,
  'a transfer WITH the acknowledged balance is accepted'
);

select throws_ok(
  $$update public.binding_events set reason = 'edited' where kind = 'transfer'$$,
  null, null,
  'binding history is append-only - an editable history is not a history'
);

-- ---------------------------------------------------------------------------
-- No tenant-reachable path to change a binding
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname in ('customer_identities', 'binding_events', 'join_intents')),
  0,
  'the binding tables have no policies, so no tenant role can reach them'
);

select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('customer_identities', 'binding_events', 'join_intents')
      and grantee in ('authenticated', 'anon')),
  0,
  'and no grant either - denied at both the grant and policy layers'
);

-- Catalogue-driven: a future `public.switch_salon()` trips this the day it is
-- written, rather than the day a customer uses it.
select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname ~* 'unbind|transfer_customer|switch_salon|change_salon')),
  0,
  'no unbind, transfer or switch function is exposed in the public schema'
);

select * from finish();
