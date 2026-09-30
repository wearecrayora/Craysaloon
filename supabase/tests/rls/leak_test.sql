-- RELEASE GATE: cross-tenant isolation
--
-- Never skipped, never deleted, never narrowed to pass (RULES.md 12).
--
-- Three halves, and the first two are what make this test survive the future:
-- they are generated FROM THE CATALOGUE, so a table added tomorrow is covered
-- tomorrow. Hand-written per-table tests rot the moment someone adds a table
-- and forgets, which is exactly when you need them.
--
-- The runner wraps this in a transaction and rolls it back, so the seeded
-- salons never persist in the shared hosted database.
--
-- A TRAP THIS TEST GUARDS AGAINST. On Supabase both `postgres` and
-- `service_role` have rolbypassrls = true, so a behavioural leak test written
-- WITHOUT `set local role authenticated` bypasses RLS entirely and passes
-- trivially - proving nothing while looking green. Test 4 below asserts the
-- test is running under a role that genuinely cannot bypass RLS, so removing
-- the role switch fails loudly instead of silently.

select plan(13);

-- ---------------------------------------------------------------------------
-- STRUCTURAL: every tenant table is protected
-- ---------------------------------------------------------------------------

-- `enable` alone is not enough: without `force`, the table OWNER bypasses RLS,
-- and a migration or a mis-scoped connection silently reads every salon.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     join information_schema.columns col
       on col.table_schema = 'public'
      and col.table_name = c.relname
      and col.column_name = 'salon_id'
    where n.nspname = 'public'
      and c.relkind = 'r'
      and (c.relrowsecurity = false or c.relforcerowsecurity = false)),
  0,
  'every table with salon_id has RLS both ENABLED and FORCED'
);

-- Every tenant table either has policies, or is on the documented list of
-- tables that deliberately have none. A new table with no policy and no
-- documented reason fails here.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     join information_schema.columns col
       on col.table_schema = 'public'
      and col.table_name = c.relname
      and col.column_name = 'salon_id'
    where n.nspname = 'public'
      and c.relkind = 'r'
      and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
      and c.relname not in (
        'customer_identities', 'binding_events', 'join_intents',
        'salon_integrations', 'domain_events', 'jobs',
        'idempotency_keys', 'webhook_events',
        -- ADR-36: in-flight Message Central verifications. Cross-tenant
        -- machinery like join_intents - touched only by the OTP Edge
        -- Functions as service_role, never by a tenant.
        'otp_challenges',
        -- 0084: service start codes. Staff must NEVER read one, or typing it
        -- proves nothing - so no policy, and only two definer functions.
        'booking_start_codes',
        -- 0087: Crayora's own billing records. A salon's staff read their
        -- state through my_salon_billing; only app_admin reads these.
        'subscription_payments', 'billing_notices',
        -- 0089: who looked at which salon's customers, for how long, and why.
        'support_sessions',
        -- 0094: the last receipt/invoice number issued. Only the two issuing
        -- functions touch it; a tenant who could write it could skip or
        -- reuse a statutory invoice number.
        'document_series'
      )),
  0,
  'every tenant table has policies, or is a documented no-policy table'
);

-- The cross-tenant and secret tables must have EXACTLY zero policies. Under
-- forced RLS that means no tenant role can touch them at all.
select is(
  (select count(*)::int
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
    where c.relname in ('customer_identities', 'binding_events',
                        'join_intents', 'salon_integrations',
                        'otp_challenges',
                        -- A policy here would let staff read a code (0084).
                        'booking_start_codes',
                        -- Crayora's revenue and lapse notices (0087).
                        'subscription_payments', 'billing_notices',
                        -- Support-mode sessions (0089).
                        'support_sessions',
                        -- Invoice numbering (0094).
                        'document_series')),
  0,
  'cross-tenant and secret tables have NO policies at all'
);

-- ---------------------------------------------------------------------------
-- BEHAVIOURAL: seed two salons, look as salon A, see nothing of salon B
-- ---------------------------------------------------------------------------

select set_config('app.phone_hash_pepper', 'leak-test-pepper', true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'Salon A Ltd', 'Salon A',
   'CRAY-AAAAAA', 'active', '00000000-0000-4000-8000-00000000000a', now()),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'Salon B Ltd', 'Salon B',
   'CRAY-BBBBBB', 'active', '00000000-0000-4000-8000-00000000000b', now());

insert into public.customers (id, salon_id, name, phone_hash)
values
  ('aaaaaaaa-1111-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000001', 'Customer of A',
   app.phone_hash('9800000001')),
  ('bbbbbbbb-1111-4000-8000-000000000002',
   'bbbbbbbb-0000-4000-8000-000000000002', 'Customer of B',
   app.phone_hash('9800000002'));

insert into public.services (salon_id, name, price_paise, duration_minutes)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'Haircut A', 30000, 30),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'Haircut B', 40000, 30);

insert into public.wallet_transactions
  (salon_id, customer_id, kind, amount_paise, balance_after)
values
  ('aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-1111-4000-8000-000000000001', 'credit_topup', 50000, 50000),
  ('bbbbbbbb-0000-4000-8000-000000000002',
   'bbbbbbbb-1111-4000-8000-000000000002', 'credit_topup', 70000, 70000);

-- Become an owner of salon A, exactly as PostgREST would present them.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000000a",'
  '"app_role":"owner",'
  '"salon_id":"aaaaaaaa-0000-4000-8000-000000000001"}',
  true
);

-- Guard the test's own validity BEFORE asserting anything with it.
select is(
  (select current_user)::text, 'authenticated',
  'the test is running as authenticated, not as a role that bypasses RLS'
);

select is(
  (select rolbypassrls from pg_roles where rolname = current_user), false,
  'the current role cannot bypass RLS - so these assertions mean something'
);

select is((select count(*)::int from public.customers), 1,
  'owner of A sees exactly their own customer, not B''s');

select is((select count(*)::int from public.services), 1,
  'owner of A sees exactly their own service, not B''s');

select is((select count(*)::int from public.wallet_transactions), 1,
  'owner of A sees exactly their own ledger row, not B''s');

-- The strongest statement: not one row of salon B is reachable, in any of the
-- seeded tables, by any query this principal can express.
select is(
  (select (select count(*) from public.customers
            where salon_id = 'bbbbbbbb-0000-4000-8000-000000000002')
        + (select count(*) from public.services
            where salon_id = 'bbbbbbbb-0000-4000-8000-000000000002')
        + (select count(*) from public.wallet_transactions
            where salon_id = 'bbbbbbbb-0000-4000-8000-000000000002'))::int,
  0,
  'ZERO rows of salon B are reachable by an owner of salon A'
);

-- The app re-reads its branding on every open (0093). It takes no parameter, so
-- the only salon it can ever describe is the one in the caller's token.
select is(public.my_branding() ->> 'salon_id', 'aaaaaaaa-0000-4000-8000-000000000001',
  'my_branding describes the caller''s own salon');

select is(public.my_branding() ->> 'display_name', 'Salon A',
  'my_branding never names salon B to an owner of salon A');

-- Signed in, bound to nothing: no salon, so no branding - not someone else's.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000cc","app_role":"customer_unbound"}',
  true
);

select is(public.my_branding(), null,
  'a caller bound to no salon gets no branding at all');

reset role;

-- The dispatcher's read takes a salon id, so it must be closed to everyone a
-- token can make you: granted to authenticated it would describe any salon.
select ok(
  not has_function_privilege('authenticated', 'public.salon_push_brand(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.salon_push_brand(uuid)', 'execute'),
  'salon_push_brand is service_role only - no signed-in caller can name a salon to it'
);
select * from finish();
