-- RELEASE GATE: money
--
-- Never skipped, never deleted, never narrowed to pass (RULES.md 12).
--
-- Every assertion here operates on REAL ROWS. An earlier probe of the
-- append-only trigger used `where false`, which touches no rows, so a
-- FOR EACH ROW trigger never fired and the probe proved nothing. A statement
-- that succeeds against zero rows is not evidence.

select plan(13);

select set_config('app.phone_hash_pepper', 'money-test-pepper', true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values
  ('cccccccc-0000-4000-8000-000000000001', 'Money A', 'Money A',
   'CRAY-MMMAAA', 'active', '00000000-0000-4000-8000-00000000000a', now()),
  ('dddddddd-0000-4000-8000-000000000002', 'Money B', 'Money B',
   'CRAY-MMMBBB', 'active', '00000000-0000-4000-8000-00000000000b', now());

insert into public.customers (id, salon_id, name, phone_hash)
values
  ('cccccccc-1111-4000-8000-000000000001',
   'cccccccc-0000-4000-8000-000000000001', 'A cust', app.phone_hash('9700000001')),
  ('dddddddd-1111-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000002', 'B cust', app.phone_hash('9700000002'));

insert into public.wallet_transactions
  (id, salon_id, customer_id, kind, amount_paise, balance_after)
overriding system value
values
  (900001, 'cccccccc-0000-4000-8000-000000000001',
   'cccccccc-1111-4000-8000-000000000001', 'credit_topup', 50000, 50000);

-- ---------------------------------------------------------------------------
-- Append-only, on real rows, as the OWNER - the strongest case
-- ---------------------------------------------------------------------------
--
-- postgres has rolbypassrls, so RLS would not stop it. The trigger does, and
-- that is precisely why the trigger exists alongside the revoked grants.

select throws_ok(
  $$update public.wallet_transactions set amount_paise = 999 where id = 900001$$,
  null,
  null,
  'UPDATE on wallet_transactions is blocked, even for the owner'
);

select throws_ok(
  $$delete from public.wallet_transactions where id = 900001$$,
  null,
  null,
  'DELETE on wallet_transactions is blocked, even for the owner'
);

select is(
  (select count(*)::int from public.wallet_transactions where id = 900001), 1,
  'the row survived both attempts - reversals are new rows, not edits'
);

-- ---------------------------------------------------------------------------
-- Paid credit can never expire
-- ---------------------------------------------------------------------------
--
-- Expiring money the customer actually paid is an unfair contract term under
-- the Consumer Protection Act 2019, and it weakens the closed-loop position
-- that keeps this outside PPI licensing. The capability is ABSENT, not
-- defaulted off - so no setting, code path or migration can reintroduce it.

select throws_ok(
  $$insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
    values ('cccccccc-0000-4000-8000-000000000001',
            'cccccccc-1111-4000-8000-000000000001',
            'paid', 50000, 50000, now() + interval '180 days')$$,
  null, null,
  'a PAID lot with an expiry is rejected by the database'
);

select lives_ok(
  $$insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
    values ('cccccccc-0000-4000-8000-000000000001',
            'cccccccc-1111-4000-8000-000000000001',
            'bonus', 5000, 5000, now() + interval '180 days')$$,
  'a BONUS lot with an expiry is accepted - bonus is a gift and may expire'
);

select lives_ok(
  $$insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise)
    values ('cccccccc-0000-4000-8000-000000000001',
            'cccccccc-1111-4000-8000-000000000001',
            'paid', 50000, 50000)$$,
  'a PAID lot with no expiry is accepted'
);

-- ---------------------------------------------------------------------------
-- Credit is redeemable only at the salon that issued it
-- ---------------------------------------------------------------------------
--
-- This is a licensing boundary, not a preference: credit spendable across
-- salons would make the wallet a semi-closed PPI requiring authorisation.

select throws_ok(
  $$insert into public.wallet_transactions
      (salon_id, customer_id, kind, amount_paise, balance_after)
    values ('cccccccc-0000-4000-8000-000000000001',
            'dddddddd-1111-4000-8000-000000000002', 'credit_topup', 1000, 1000)$$,
  null, null,
  'a ledger row claiming salon A for a customer of salon B is rejected'
);

-- ---------------------------------------------------------------------------
-- No owner or manager path to a balance
-- ---------------------------------------------------------------------------
--
-- Not a permission set to off - an absence. The five callers in RULES 5.2 are
-- security definer and bypass RLS; tenant roles have no write grant at all.

select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('wallet_transactions', 'loyalty_ledger',
                         'wallet_lots', 'wallet_accounts')
      and grantee in ('authenticated', 'anon')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'authenticated and anon hold NO write grant on any ledger table'
);

-- Broadened after the narrow version passed while every OTHER read-only table
-- still carried Supabase's default write grants. Naming four tables tested
-- four tables; this tests the rule.
select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
      and table_name in (
        'wallet_accounts', 'wallet_lots', 'wallet_transactions', 'loyalty_ledger',
        'payments', 'payment_allocations', 'audit_log', 'daily_salon_metrics',
        'retention_cohorts', 'notifications', 'notification_deliveries',
        'subscriptions', 'feature_flags', 'referrals',
        'customer_service_intervals', 'customer_identities', 'binding_events',
        'join_intents', 'salon_integrations', 'platform_admins')),
  0,
  'authenticated holds no write grant on ANY read-only or restricted table'
);

-- anon's only legitimate entry points are security definer functions, which
-- need no table grant. It should hold nothing at all.
select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'),
  0,
  'anon holds no privilege on any table in public'
);

select is(
  (select count(*)::int
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
    where c.relname in ('wallet_transactions', 'loyalty_ledger',
                        'wallet_lots', 'wallet_accounts')
      and p.polcmd in ('a', 'w')),
  0,
  'no INSERT or UPDATE policy exists on any ledger table'
);

-- ---------------------------------------------------------------------------
-- Money is integer paise, never floating point
-- ---------------------------------------------------------------------------
--
-- Removes an entire class of rounding bug before it can exist.

select is(
  (select count(*)::int
     from information_schema.columns
    where table_schema = 'public'
      and column_name like '%_paise'
      and data_type not in ('bigint', 'integer')),
  0,
  'every *_paise column is an integer type - no float, no numeric'
);

select is(
  (select count(*)::int
     from information_schema.columns
    where table_schema = 'public'
      and data_type in ('double precision', 'real')),
  0,
  'no floating-point column exists anywhere in the schema'
);

select * from finish();
