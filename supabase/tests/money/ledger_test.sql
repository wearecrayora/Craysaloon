-- RELEASE GATE: money
--
-- Never skipped, never deleted, never narrowed to pass (RULES.md 12).
--
-- Every assertion here operates on REAL ROWS. An earlier probe of the
-- append-only trigger used `where false`, which touches no rows, so a
-- FOR EACH ROW trigger never fired and the probe proved nothing. A statement
-- that succeeds against zero rows is not evidence.

select plan(45);

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

-- ---------------------------------------------------------------------------
-- THE LEDGER IN MOTION (0048). Everything above is structure; this is behaviour.
-- ---------------------------------------------------------------------------

-- Only ONE function may write a ledger row, and only the documented callers may
-- call it. Asserted from the catalogue, so a sixth caller fails on the day it is
-- written rather than the day it double-charges someone.
select set_eq(
  $q$select p.proname::text
      from pg_proc p
     where p.pronamespace in ('app'::regnamespace, 'app_admin'::regnamespace)
       and pg_get_functiondef(p.oid) ~* 'insert into public[.]wallet_transactions'$q$,
  $q$values ('wallet_post')$q$,
  'exactly ONE function inserts a wallet ledger row - the single write path (RULES 5.1.3)'
);

select set_eq(
  $q$with fns as materialized (
      select p.proname::text as name, pg_get_functiondef(p.oid) as def
        from pg_proc p
       where p.pronamespace in ('app'::regnamespace, 'app_admin'::regnamespace)
         and p.proname <> 'wallet_post'
    )
    select name from fns where def ~* 'wallet_post'$q$,
  $q$values ('wallet_credit_from_payment'), ('wallet_debit_at_checkout'),
           ('wallet_expire_lot'), ('wallet_correct')$q$,
  'and only the permitted callers call it - four today, referral reward at M9 (RULES 5.2)'
);

select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace in ('app'::regnamespace, 'app_admin'::regnamespace)
      and p.proname in ('wallet_post', 'wallet_credit_from_payment',
                        'wallet_debit_at_checkout', 'wallet_expire_lot')
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0,
  'no device can call any ledger function - not an owner, not a customer (RULES 5.2)'
);

-- Fixtures: a salon with a 10% bonus over a Rs 500 top-up, expiring in 180 days.
insert into auth.users (id) values ('99999999-aaaa-4000-8000-00000000000f');
insert into public.platform_admins (id, email, name, is_super, active)
values ('99999999-aaaa-4000-8000-00000000000f', 'money@crayora.test', 'Money Super', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           wallet_rule, activated_by, activated_at)
values ('99999999-0000-4000-8000-000000000001', 'Money Salon Ltd', 'Money Salon',
        'CRAY-MNYQQQ', 'active',
        '{"bonus_percent": 10, "min_topup_paise": 50000, "bonus_expiry_days": 180}'::jsonb,
        '99999999-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, name, phone, phone_hash)
values ('99999999-1111-4000-8000-00000000000c', '99999999-0000-4000-8000-000000000001',
        'Meena', '9899900001', app.phone_hash('9899900001'));

-- Rs 1000 top-up, captured.
insert into public.payments (id, salon_id, customer_id, method, amount_paise, status, captured_at)
values ('99999999-7777-4000-8000-000000000001', '99999999-0000-4000-8000-000000000001',
        '99999999-1111-4000-8000-00000000000c', 'upi', 100000, 'captured', now());

create temp table credited as
select app.wallet_credit_from_payment('99999999-7777-4000-8000-000000000001') as r;

select results_eq(
  $q$select (r ->> 'paid_paise')::bigint, (r ->> 'bonus_paise')::bigint from credited$q$,
  $q$values (100000::bigint, 10000::bigint)$q$,
  'a Rs 1000 top-up credits Rs 1000 paid and Rs 100 bonus - 10 per cent, in whole paise'
);

select results_eq(
  $q$select kind::text, amount_paise, balance_after from public.wallet_transactions
     where customer_id = '99999999-1111-4000-8000-00000000000c' order by id$q$,
  $q$values ('credit_topup', 100000::bigint, 100000::bigint),
           ('credit_bonus', 10000::bigint, 110000::bigint)$q$,
  'two ledger rows, each carrying the running balance after it'
);

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '99999999-1111-4000-8000-00000000000c'),
  110000::bigint,
  'and the cached balance agrees with the ledger'
);

select results_eq(
  $q$select kind::text, (expires_at is null) as never_expires from public.wallet_lots
     where customer_id = '99999999-1111-4000-8000-00000000000c' order by kind::text$q$,
  $q$values ('bonus', false), ('paid', true)$q$,
  'the PAID lot has no expiry and the bonus lot has one (RULES 5.3.1, 5.3.3)'
);

-- A webhook redelivery must not credit twice.
select is(
  (app.wallet_credit_from_payment('99999999-7777-4000-8000-000000000001') ->> 'already'),
  'true',
  'crediting the same payment again is a no-op - webhooks redeliver'
);

select is(
  (select count(*)::int from public.wallet_transactions
    where customer_id = '99999999-1111-4000-8000-00000000000c'),
  2,
  'and writes no third row'
);

-- Spending: bonus first.
create temp table spent as
select app.wallet_debit_at_checkout(
  '99999999-0000-4000-8000-000000000001',
  '99999999-1111-4000-8000-00000000000c',
  15000) as r;

select is((select r ->> 'ok' from spent), 'true', 'Rs 150 is spent at checkout');

select results_eq(
  $q$select l.kind::text, l.remaining_paise from public.wallet_lots l
     where l.customer_id = '99999999-1111-4000-8000-00000000000c' order by l.kind::text$q$,
  $q$values ('bonus', 0::bigint), ('paid', 95000::bigint)$q$,
  'the BONUS lot is emptied first, then the paid one - the credit that cannot expire is kept'
);

select results_eq(
  $q$select a.amount_paise from public.payment_allocations a
     join public.wallet_lots l on l.id = a.wallet_lot_id
    where l.customer_id = '99999999-1111-4000-8000-00000000000c'
    order by case when l.kind = 'bonus' then 0 else 1 end$q$,
  $q$values (10000::bigint), (5000::bigint)$q$,
  'and each lot consumed is recorded, so a refund could unwind precisely (ARCH 6.3)'
);

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '99999999-1111-4000-8000-00000000000c'),
  95000::bigint,
  'the balance is what is left'
);

-- Overdrawing is refused, not clamped.
select is(
  (app.wallet_debit_at_checkout(
     '99999999-0000-4000-8000-000000000001',
     '99999999-1111-4000-8000-00000000000c',
     999999) ->> 'reason'),
  'insufficient_credit',
  'spending more than the balance is REFUSED - never partially applied'
);

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '99999999-1111-4000-8000-00000000000c'),
  95000::bigint,
  'and the refusal changed nothing'
);

-- Two debits in a row cannot together overdraw: the second sees the first.
select is(
  (app.wallet_debit_at_checkout(
     '99999999-0000-4000-8000-000000000001',
     '99999999-1111-4000-8000-00000000000c',
     90000) ->> 'ok'),
  'true',
  'a second debit of Rs 900 succeeds'
);

select is(
  (app.wallet_debit_at_checkout(
     '99999999-0000-4000-8000-000000000001',
     '99999999-1111-4000-8000-00000000000c',
     90000) ->> 'reason'),
  'insufficient_credit',
  'a third does not - concurrent spending cannot overdraw (the row lock decides)'
);

-- Expiry: bonus only, ever.
insert into public.wallet_lots
  (id, salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
values
  ('99999999-8888-4000-8000-000000000001', '99999999-0000-4000-8000-000000000001',
   '99999999-1111-4000-8000-00000000000c', 'bonus', 20000, 20000, now() - interval '1 day');

select throws_ok(
  $q$select app.wallet_expire_lot(
      (select id from public.wallet_lots
        where customer_id = '99999999-1111-4000-8000-00000000000c' and kind = 'paid' limit 1))$q$,
  '23514', null,
  'a PAID lot cannot be expired, even by the function whose job is expiring lots'
);

-- The bonus lot needs crediting first, or expiring it would overdraw the wallet.
select lives_ok(
  $q$select app.wallet_post(
      '99999999-0000-4000-8000-000000000001',
      '99999999-1111-4000-8000-00000000000c',
      'credit_bonus', 20000, '99999999-8888-4000-8000-000000000001')$q$,
  'a second bonus lot is credited'
);

select is(
  (app.wallet_expire_lot('99999999-8888-4000-8000-000000000001') ->> 'expired_paise')::bigint,
  20000::bigint,
  'an overdue BONUS lot expires, and the ledger records the removal'
);

select is(
  (select count(*)::int from public.wallet_transactions
    where customer_id = '99999999-1111-4000-8000-00000000000c' and kind = 'debit_expiry'),
  1,
  'as a new row - nothing was edited (RULES 5.1.1)'
);

select is(
  (app.wallet_expire_lot('99999999-8888-4000-8000-000000000001') ->> 'already'),
  'true',
  'expiring it again does nothing - the job may run twice'
);

-- The one human path.
-- Called ONCE, into a table. The first draft of this test put the call in a
-- WHERE clause, and Postgres evaluated the volatile function once per row it
-- scanned - writing several corrections. Never call a money function from a
-- predicate; that lesson cost this test a debugging session and would cost a
-- production wallet real rupees.
create temp table corrected as
select app_admin.wallet_correct(
  '99999999-aaaa-4000-8000-00000000000f',
  '99999999-1111-4000-8000-00000000000c',
  5000, 'Machine took the payment twice at the counter') as entry_id;

select is(
  (select count(*)::int from public.wallet_transactions
    where id = (select entry_id from corrected)),
  1,
  'a super-admin can correct a balance, with a reason'
);

select is(
  (select count(*)::int from public.audit_log
    where action = 'wallet.corrected'
      and actor_user_id = '99999999-aaaa-4000-8000-00000000000f'),
  1,
  'and it is audited - the only human path to money is also the most logged'
);

select is(
  (select kind::text from public.wallet_lots
    where customer_id = '99999999-1111-4000-8000-00000000000c'
      and amount_paise = 5000),
  'paid',
  'a correction in the customer''s favour never expires - it is PAID-kind credit'
);



-- ---------------------------------------------------------------------------
-- Automation B: a top-up that landed owes a receipt
-- ---------------------------------------------------------------------------
--
-- The event is emitted in the SAME transaction as the credit, so there is no
-- state where the money arrived and nobody was told. Its idempotency is the
-- credit's own: one credit, one receipt, however many times Razorpay redelivers.

insert into auth.users (id) values ('bbbbbbbb-aaaa-4000-8000-00000000000a');

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at, wallet_rule)
values ('bbbbbbbb-0000-4000-8000-000000000001', 'Bonus Salon Ltd', 'Bonus Salon',
        'CRAY-BNSAA2', 'active', '00000000-0000-4000-8000-00000000000a', now(),
        '{"bonus_percent": 10, "min_topup_paise": 10000, "bonus_expiry_days": 30}'::jsonb);

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values ('bbbbbbbb-1111-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001',
        'bbbbbbbb-aaaa-4000-8000-00000000000a', 'Bonus cust', app.phone_hash('9700000003'));

insert into public.payments (id, salon_id, customer_id, method, amount_paise, status, captured_at)
values ('bbbbbbbb-2222-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001',
        'bbbbbbbb-1111-4000-8000-000000000001', 'upi', 100000, 'captured', now());

create temp table receipted as
  select app.wallet_credit_from_payment('bbbbbbbb-2222-4000-8000-000000000001') as r;

select is((select r ->> 'bonus_paise' from receipted), '10000',
  'a 1000-rupee top-up at 10% issues a 100-rupee bonus lot');

select is(
  (select count(*)::int from public.domain_events
    where type = 'wallet.topped_up'
      and aggregate_id = 'bbbbbbbb-2222-4000-8000-000000000001'),
  1,
  'Automation B: the credit emits exactly one wallet.topped_up');

select is(
  (select payload ->> 'bonus_paise' from public.domain_events
    where type = 'wallet.topped_up'
      and aggregate_id = 'bbbbbbbb-2222-4000-8000-000000000001'),
  '10000',
  'and it CARRIES the bonus, so a receipt never re-derives its own trigger');

select is(
  (select (payload ->> 'bonus_expires_at') is not null from public.domain_events
    where type = 'wallet.topped_up'
      and aggregate_id = 'bbbbbbbb-2222-4000-8000-000000000001'),
  true,
  'with the expiry date the disclosure promised at the pay button');

select is(
  (app.wallet_credit_from_payment('bbbbbbbb-2222-4000-8000-000000000001') ->> 'already'),
  'true',
  'a redelivered webhook credits nothing twice');

select is(
  (select count(*)::int from public.domain_events
    where type = 'wallet.topped_up'
      and aggregate_id = 'bbbbbbbb-2222-4000-8000-000000000001'),
  1,
  'and sends no second receipt - the event inherits the credit''s guard');

-- ---------------------------------------------------------------------------
-- Automation L: expiry, and one warning before it
-- ---------------------------------------------------------------------------

select is(
  (app.nudge_expiring_bonus('bbbbbbbb-0000-4000-8000-000000000001', 60) ->> 'nudged'),
  '1',
  'a bonus lot expiring inside the window is warned about');

select is(
  (app.nudge_expiring_bonus('bbbbbbbb-0000-4000-8000-000000000001', 60) ->> 'nudged'),
  '0',
  'and warned about ONCE, ever - a nightly sweep is not a nightly message');

-- Backdate the bonus lot: the expiry is due now.
update public.wallet_lots
   set expires_at = now() - interval '1 day'
 where customer_id = 'bbbbbbbb-1111-4000-8000-000000000001' and kind = 'bonus';

create temp table swept as
  select app.expire_due_bonus_lots('bbbbbbbb-0000-4000-8000-000000000001') as r;

select is((select r ->> 'lots_expired' from swept), '1',
  'Automation L expires the due bonus lot');

select is((select r ->> 'paise_expired' from swept), '10000',
  'for the whole of what was left in it');

select is(
  (app.expire_due_bonus_lots('bbbbbbbb-0000-4000-8000-000000000001') ->> 'lots_expired'),
  '0',
  'and a second run expires nothing - expired_at is the guard, not "we call it once"');

select is(
  (select count(*)::int from public.wallet_lots
    where customer_id = 'bbbbbbbb-1111-4000-8000-000000000001'
      and kind = 'paid' and expired_at is null),
  1,
  'the PAID lot is untouched by every sweep that will ever run (RULES 5.3.3)');

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = 'bbbbbbbb-1111-4000-8000-000000000001'),
  100000::bigint,
  'and the balance is back to what was actually paid');

-- ---------------------------------------------------------------------------
-- What the customer sees - as the customer, or it proves nothing
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-aaaa-4000-8000-00000000000a",'
  '"app_role":"customer",'
  '"salon_id":"bbbbbbbb-0000-4000-8000-000000000001"}',
  true
);

select is((select (public.my_wallet() ->> 'paid_paise')::bigint), 100000::bigint,
  'the wallet reports paid credit separately (DESIGN 6.2)');

select is((select (public.my_wallet() ->> 'bonus_paise')::bigint), 0::bigint,
  'and bonus separately - the summary is one number, the detail is honest');

select is(
  (select count(*)::int from public.my_wallet_history()),
  3,
  'the history is the customer''s OWN ledger: two credits and the expiry');

select is(
  (select count(*)::int from public.my_wallet_history()
    where kind not in ('credit_topup', 'credit_bonus', 'debit_expiry')),
  0,
  'and nothing that belongs to anybody else');

reset role;

select * from finish();
