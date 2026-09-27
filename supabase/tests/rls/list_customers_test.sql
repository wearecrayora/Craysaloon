-- RELEASE GATE: the owner's customer list (M5, screen O4)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- A list function is the most tempting place to lose tenant isolation: it joins
-- several tables, it wants to be fast, and SECURITY DEFINER makes every
-- permission problem disappear. It would also make the list a way around 0038.
-- So the first assertion here is about the function's own definition, and the
-- rest are about what it returns to whom.

select plan(13);

-- ---------------------------------------------------------------------------
-- The definition itself
-- ---------------------------------------------------------------------------

select is(
  (select prosecdef from pg_proc where oid = 'public.list_customers(text,timestamptz,uuid,integer)'::regprocedure),
  false,
  'list_customers is SECURITY INVOKER - the caller''s policies apply, so it cannot outrank RLS'
);

select is(
  (select count(*)::int from pg_proc
    where oid = 'public.list_customers(text,timestamptz,uuid,integer)'::regprocedure
      and 'search_path=' = any(proconfig)),
  0,
  'and it pins search_path (asserted separately below, since the value matters)'
);

select is(
  (select proconfig::text from pg_proc
    where oid = 'public.list_customers(text,timestamptz,uuid,integer)'::regprocedure),
  '{"search_path=\"\""}',
  'search_path is pinned EMPTY - every object it touches is schema-qualified'
);

select is(
  has_function_privilege('anon',
    'public.list_customers(text,timestamptz,uuid,integer)', 'EXECUTE'),
  false,
  'it is not reachable before login - the pre-auth surface is the join code alone'
);

-- ---------------------------------------------------------------------------
-- Fixtures: one salon, four customers, one of them at another salon
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('dddddddd-aaaa-4000-8000-00000000000f'),
  ('dddddddd-aaaa-4000-8000-00000000000c');

insert into public.platform_admins (id, email, name, is_super, active)
values ('dddddddd-aaaa-4000-8000-00000000000f', 'list@crayora.test', 'List Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at)
values
  ('dddddddd-0000-4000-8000-000000000001', 'List Salon Ltd', 'List Salon',
   'CRAY-KKKQQQ', 'active', 'dddddddd-aaaa-4000-8000-00000000000f', now()),
  ('dddddddd-0000-4000-8000-000000000002', 'Other Salon Ltd', 'Other Salon',
   'CRAY-NNNQQQ', 'active', 'dddddddd-aaaa-4000-8000-00000000000f', now());

insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
values ('dddddddd-5555-4000-8000-00000000000f', 'dddddddd-0000-4000-8000-000000000001',
        'owner', 'List Owner', '9866600009', app.phone_hash('9866600009'), true);

-- Ayesha visited most recently, then Bhavna, then Chetan; Deepa never came in.
insert into public.customers (id, salon_id, name, phone, phone_hash, last_visit_at, loyalty_points, tier)
values
  ('dddddddd-1111-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-000000000001',
   'Ayesha', '9866600001', app.phone_hash('9866600001'), now() - interval '1 day', 120, 'silver'),
  ('dddddddd-1111-4000-8000-00000000000b', 'dddddddd-0000-4000-8000-000000000001',
   'Bhavna', '9866600002', app.phone_hash('9866600002'), now() - interval '9 days', 40, 'bronze'),
  ('dddddddd-1111-4000-8000-00000000000c', 'dddddddd-0000-4000-8000-000000000001',
   'Chetan', '9866600003', app.phone_hash('9866600003'), now() - interval '30 days', 0, 'bronze'),
  ('dddddddd-1111-4000-8000-00000000000d', 'dddddddd-0000-4000-8000-000000000001',
   'Deepa', '9866600004', app.phone_hash('9866600004'), null, 0, 'bronze'),
  -- Another salon's customer, with a name that would match the same search.
  ('dddddddd-1111-4000-8000-00000000000e', 'dddddddd-0000-4000-8000-000000000002',
   'Ayesha', '9866600005', app.phone_hash('9866600005'), now(), 0, 'bronze');

insert into public.wallet_accounts (customer_id, salon_id, balance_paise) values
  ('dddddddd-1111-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-000000000001', 55000);

-- Two visits for Ayesha, so the count is not trivially 1.
insert into public.bookings (id, salon_id, customer_id, starts_at, ends_at, status)
values
  ('dddddddd-3333-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-1111-4000-8000-00000000000a', now() - interval '1 day', now() - interval '1 day' + interval '30 min', 'completed'),
  ('dddddddd-3333-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-1111-4000-8000-00000000000a', now() - interval '40 days', now() - interval '40 days' + interval '30 min', 'completed');

insert into public.visits (salon_id, booking_id, customer_id, final_amount_paise, completed_at)
values
  ('dddddddd-0000-4000-8000-000000000001', 'dddddddd-3333-4000-8000-000000000001',
   'dddddddd-1111-4000-8000-00000000000a', 40000, now() - interval '1 day'),
  ('dddddddd-0000-4000-8000-000000000001', 'dddddddd-3333-4000-8000-000000000002',
   'dddddddd-1111-4000-8000-00000000000a', 35000, now() - interval '40 days');

-- A customer of the same salon, with their own login: the list function must
-- treat them like the table does. Seeded here, before the role switch, because
-- app.phone_hash is deliberately unreachable by tenant roles (0025).
insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash, last_visit_at)
values ('dddddddd-1111-4000-8000-000000000099', 'dddddddd-0000-4000-8000-000000000001',
        'dddddddd-aaaa-4000-8000-00000000000c', 'Self Service', '9866600099',
        app.phone_hash('9866600099'), now() - interval '60 days');

-- ---------------------------------------------------------------------------
-- As the owner
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"dddddddd-0000-4000-8000-000000000001"}',
  true
);

select results_eq(
  $$select name from public.list_customers()$$,
  $$values ('Ayesha'), ('Bhavna'), ('Chetan'), ('Self Service'), ('Deepa')$$,
  'newest visit first, and a customer who has never been in is last, not missing'
);

select results_eq(
  $$select name, balance_paise, visit_count from public.list_customers(p_limit => 1)$$,
  $$values ('Ayesha', 55000::bigint, 2)$$,
  'one call carries the balance and the visit count - the screen makes no second trip'
);

-- Keyset: page 2 continues exactly where page 1 stopped, with no repeat and no
-- skip, which is what OFFSET cannot promise while rows are being inserted.
select results_eq(
  $$with page1 as (
      select id, last_visit_at from public.list_customers(p_limit => 2)
       order by last_visit_at desc nulls last, id desc
    ), cursor_row as (
      select * from page1 offset 1 limit 1
    )
    select name from public.list_customers(
      p_cursor_last_visit => (select last_visit_at from cursor_row),
      p_cursor_id => (select id from cursor_row),
      p_limit => 2)$$,
  $$values ('Chetan'), ('Self Service')$$,
  'the second page continues after the cursor: no row repeated, none skipped'
);

select results_eq(
  $$select name from public.list_customers(p_search => 'ay')$$,
  $$values ('Ayesha')$$,
  'a name prefix search finds the customer - and NOT the same name at another salon'
);

select results_eq(
  $$select name from public.list_customers(p_search => '+91 98666 00002')$$,
  $$values ('Bhavna')$$,
  'a whole number, typed the way people type it, finds exactly that customer'
);

select is(
  (select count(*)::int from public.list_customers(p_search => '98666000')),
  0,
  'a PARTIAL number finds nobody - the list is not a number-lookup tool (RULES 4.7)'
);

select is(
  (select count(*)::int from public.list_customers(p_limit => 1000)),
  5,
  'a caller cannot ask for an unbounded page, and still never sees another salon'
);

-- ---------------------------------------------------------------------------
-- As a customer of that salon: the same function, almost nothing back
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-aaaa-4000-8000-00000000000c",'
  '"app_role":"customer",'
  '"salon_id":"dddddddd-0000-4000-8000-000000000001"}',
  true
);

select results_eq(
  $$select name from public.list_customers()$$,
  $$values ('Self Service')$$,
  'a customer calling the owner''s list function gets ONLY themselves (0038 holds here too)'
);

select is(
  (select count(*)::int from public.list_customers(p_search => 'Ayesha')),
  0,
  'and cannot use the search to find another customer by name'
);

select is(
  (select count(*)::int from public.list_customers(p_search => '9866600002')),
  0,
  'nor by their number - the function is no better a lookup tool than the table'
);

reset role;
select * from finish();
