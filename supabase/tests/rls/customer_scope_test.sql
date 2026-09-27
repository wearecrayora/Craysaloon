-- RELEASE GATE: one customer cannot see another, inside the same salon
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- The cross-tenant leak test proves salon A cannot see salon B. It passed for
-- months while a customer could read every other customer of their OWN salon -
-- names, phone numbers, wallet balances - and every staff member's personal
-- mobile number, because every read policy said only `salon_id =
-- current_salon_id()` and was granted to `authenticated`, which includes
-- customers (fixed in 0038).
--
-- Two halves, and both matter:
--   * behavioural - as a real signed-in customer, count what is reachable
--   * catalogue   - every table that names a customer HAS the restrictive
--                   policy, so a table added next year fails here rather than
--                   leaking quietly

select plan(22);

-- ---------------------------------------------------------------------------
-- Catalogue: the rule exists everywhere it must
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname <> 'customer_identities'
      and exists (select 1 from pg_attribute a
                   where a.attrelid = c.oid and a.attname = 'customer_id'
                     and a.attnum > 0 and not a.attisdropped)
      and not exists (
        select 1 from pg_policy p
         where p.polrelid = c.oid
           and p.polpermissive = false
           and pg_get_expr(p.polqual, p.polrelid) like '%current_customer_id%')),
  0,
  'every table naming a customer has a RESTRICTIVE policy keyed on that customer'
);

select is(
  (select count(*)::int from pg_policy p
    where p.polrelid = 'public.customers'::regclass
      and p.polpermissive = false
      and pg_get_expr(p.polqual, p.polrelid) like '%current_customer_id%'),
  1,
  'customers itself is restricted to the caller''s own row'
);

select is(
  (select count(*)::int > 0 from pg_policy p
    where p.polrelid = 'public.users'::regclass
      and p.polpermissive = false
      and pg_get_expr(p.polqual, p.polrelid) like '%current_app_role%'),
  true,
  'the staff table - which holds staff PHONE NUMBERS - is closed to customers'
);

-- Restrictive, not permissive: a permissive policy beside a broad one grants
-- the UNION, which is precisely how the original bug worked.
select is(
  (select bool_and(p.polpermissive = false)
     from pg_policy p
    where p.polname in ('customer_scope', 'staff_scope')),
  true,
  'every scope policy is RESTRICTIVE - a permissive one would add access, not remove it'
);

-- ---------------------------------------------------------------------------
-- Behavioural: two customers of ONE salon, and a staff member
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('cccccccc-aaaa-4000-8000-00000000000a'),   -- customer A
  ('cccccccc-aaaa-4000-8000-00000000000b'),   -- customer B
  ('cccccccc-aaaa-4000-8000-00000000000f');   -- the owner

insert into public.platform_admins (id, email, name, is_super, active)
values ('cccccccc-aaaa-4000-8000-00000000000f', 'scope@crayora.test', 'Scope Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at)
values ('cccccccc-0000-4000-8000-000000000001', 'Scope Salon Ltd', 'Scope Salon',
        'CRAY-SSSQQQ', 'active', 'cccccccc-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, phone_hash, phone, name)
values
  ('cccccccc-1111-4000-8000-00000000000a', 'cccccccc-0000-4000-8000-000000000001',
   'cccccccc-aaaa-4000-8000-00000000000a', app.phone_hash('9855500001'), '9855500001', 'Ayesha'),
  ('cccccccc-1111-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-000000000001',
   'cccccccc-aaaa-4000-8000-00000000000b', app.phone_hash('9855500002'), '9855500002', 'Bhavna');

-- A staff member, with the personal number a customer was able to read.
insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
values ('cccccccc-5555-4000-8000-00000000000f', 'cccccccc-0000-4000-8000-000000000001',
        'owner', 'Scope Owner', '9855500009', app.phone_hash('9855500009'), true);

insert into public.wallet_accounts (customer_id, salon_id, balance_paise) values
  ('cccccccc-1111-4000-8000-00000000000a', 'cccccccc-0000-4000-8000-000000000001', 25000),
  ('cccccccc-1111-4000-8000-00000000000b', 'cccccccc-0000-4000-8000-000000000001', 99000);

insert into public.wallet_transactions (salon_id, customer_id, kind, amount_paise, balance_after) values
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-1111-4000-8000-00000000000a',
   'credit_topup', 25000, 25000),
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-1111-4000-8000-00000000000b',
   'credit_topup', 99000, 99000);

insert into public.consents (salon_id, customer_id, purpose, granted, source) values
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-1111-4000-8000-00000000000a',
   'service_communication', true, 'binding'),
  ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-1111-4000-8000-00000000000b',
   'service_communication', true, 'binding');

insert into public.services (id, salon_id, name, price_paise, duration_minutes, active) values
  ('cccccccc-2222-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001',
   'Haircut', 40000, 30, true);

-- Become customer A, exactly as PostgREST would present them.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-aaaa-4000-8000-00000000000a",'
  '"app_role":"customer",'
  '"salon_id":"cccccccc-0000-4000-8000-000000000001"}',
  true
);

-- Guard the test's own validity BEFORE asserting anything with it.
select is((select current_user)::text, 'authenticated',
  'the test runs as authenticated, not as a role that bypasses RLS');
select is((select rolbypassrls from pg_roles where rolname = current_user), false,
  'the current role cannot bypass RLS - so these assertions mean something');
-- The identity is resolved from the DATABASE, not taken from the token: the
-- only row visible is the one whose auth_user_id is this session's. (app.* is
-- deliberately unreachable by tenant roles - 0025 - so this is asserted the way
-- the app would see it.)
select results_eq(
  $$select id::text from public.customers order by 1$$,
  $$values ('cccccccc-1111-4000-8000-00000000000a')$$,
  'the session resolves to customer A, from the database rather than the token'
);

select is((select count(*)::int from public.customers), 1,
  'a customer sees ONE customer row: their own');

select is(
  (select count(*)::int from public.customers where name = 'Bhavna'),
  0,
  'the other customer of the same salon is invisible - name and number both'
);

select is((select count(*)::int from public.wallet_accounts), 1,
  'one wallet: theirs');

select is(
  (select coalesce(sum(balance_paise), 0)::int from public.wallet_accounts),
  25000,
  'and the balance they can read is their OWN, not the salon''s total'
);

select is((select count(*)::int from public.wallet_transactions), 1,
  'one ledger row: theirs');

select is((select count(*)::int from public.consents), 1,
  'one consent record: theirs');

select is((select count(*)::int from public.users), 0,
  'the staff table is unreadable - a customer never sees a stylist''s mobile number'
);

-- The strongest statement: nothing belonging to customer B is reachable by any
-- query customer A can express.
select is(
  (select (select count(*) from public.customers
            where id = 'cccccccc-1111-4000-8000-00000000000b')
        + (select count(*) from public.wallet_accounts
            where customer_id = 'cccccccc-1111-4000-8000-00000000000b')
        + (select count(*) from public.wallet_transactions
            where customer_id = 'cccccccc-1111-4000-8000-00000000000b')
        + (select count(*) from public.consents
            where customer_id = 'cccccccc-1111-4000-8000-00000000000b'))::int,
  0,
  'ZERO rows of the OTHER customer are reachable, in any seeded table'
);

-- What the customer app still needs must still work.
select is((select count(*)::int from public.services), 1,
  'the salon''s menu is still readable - a customer cannot book from nothing'
);

-- ...but reading the menu is not editing it. The catalogue tables carry write
-- policies granted to `authenticated`, which includes customers, so without a
-- restriction a customer could reprice the salon's services.
select throws_ok(
  $$insert into public.services (salon_id, name, price_paise, duration_minutes, active)
    values ('cccccccc-0000-4000-8000-000000000001', 'Free Haircut', 0, 30, true)$$,
  '42501', null,
  'a customer cannot add a service to their salon''s menu'
);

-- An UPDATE a policy forbids does not raise: it simply matches nothing. Which
-- is why this asserts the PRICE, not an error - a silent no-op that left the
-- price changed would be the actual disaster.
update public.services set price_paise = 1
 where salon_id = 'cccccccc-0000-4000-8000-000000000001';

select is(
  (select price_paise from public.services
    where id = 'cccccccc-2222-4000-8000-000000000001'),
  40000::bigint,
  'and cannot reprice one - the price is untouched after they try'
);

select throws_ok(
  $$insert into public.staff (salon_id, name, active)
    values ('cccccccc-0000-4000-8000-000000000001', 'Ghost Stylist', true)$$,
  '42501', null,
  'nor invent a member of the team'
);

-- ---------------------------------------------------------------------------
-- The same salon, seen by its owner: nothing was taken from staff
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"cccccccc-0000-4000-8000-000000000001"}',
  true
);

select is((select count(*)::int from public.customers), 2,
  'the owner still sees both customers - the salon runs on that');

select is((select count(*)::int from public.wallet_accounts), 2,
  'and both wallets');

select is((select count(*)::int from public.users), 1,
  'and their own staff record');

reset role;
select * from finish();
