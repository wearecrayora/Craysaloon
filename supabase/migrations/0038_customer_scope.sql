-- 0038 A customer sees THEIR OWN rows, not their salon's
--
-- THE BUG. Every tenant table's read policy was `salon_id =
-- app.current_salon_id()`, granted to `authenticated`. `authenticated` is every
-- logged-in principal - owner, manager, staff AND customer. So a customer who
-- signed in could read every other customer of their salon: names, phone
-- numbers, wallet balances, ledger rows, visits, bookings, consents. And every
-- staff member's personal mobile number, from `public.users`.
--
-- Policies named `..._customer_own` existed on bookings, visits and
-- wallet_transactions and looked like the answer. They are not: **RLS policies
-- are PERMISSIVE by default and OR'd together**, so a narrow policy beside a
-- broad one grants the union. They were adding access, not restricting it.
--
-- Found on 2026-09-27 by reading, as a real signed-in customer on the hosted
-- project, what PostgREST would return. The cross-tenant leak test passes and
-- always did: it proves salon A cannot see salon B. Nothing proved that one
-- customer cannot see another INSIDE a salon. A gate that was never written
-- cannot go red.
--
-- THE FIX, and why this shape. Each rule below is RESTRICTIVE: Postgres ANDs
-- restrictive policies with the permissive set, so they cannot be undone by
-- adding another permissive policy later - which is exactly how this happened.
-- The predicate is `role <> 'customer' OR the row is theirs`, so staff keep the
-- salon-wide view their job needs, and a customer is confined to their own row
-- without every future table having to remember.
--
-- Ownership is NOT read from the token: app.current_customer_id() is SECURITY
-- DEFINER and resolves the customers row from auth.uid() and the salon, so a
-- forged claim buys nothing.

-- ---------------------------------------------------------------------------
-- 1. Every table that names a customer
-- ---------------------------------------------------------------------------
--
-- Catalogue-driven, so today's tables are all covered and none was missed by
-- hand. A table added LATER is caught by the gate
-- (supabase/tests/rls/customer_scope_test.sql), which fails the build if a
-- table with customer_id has no restrictive policy.

do $$
declare
  v_table text;
begin
  for v_table in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       -- customer_identities is the one deliberately cross-tenant table, has
       -- ZERO policies, and is reachable only through SECURITY DEFINER
       -- functions (ARCHITECTURE 5.4). Nothing to restrict.
       and c.relname <> 'customer_identities'
       and exists (
         select 1 from pg_attribute a
          where a.attrelid = c.oid and a.attname = 'customer_id'
            and a.attnum > 0 and not a.attisdropped
       )
     order by c.relname
  loop
    execute format($f$
      create policy customer_scope on public.%I
        as restrictive for all to authenticated
        using (app.current_app_role() <> 'customer'
               or customer_id = app.current_customer_id())
        with check (app.current_app_role() <> 'customer'
               or customer_id = app.current_customer_id())
    $f$, v_table);
  end loop;
end;
$$;

-- customers keys its own identity as `id`, not `customer_id`.
create policy customer_scope on public.customers
  as restrictive for all to authenticated
  using (app.current_app_role() <> 'customer' or id = app.current_customer_id())
  with check (app.current_app_role() <> 'customer' or id = app.current_customer_id());

-- ---------------------------------------------------------------------------
-- 2. Tables that name a customer only through their parent
-- ---------------------------------------------------------------------------

create policy customer_scope on public.booking_items
  as restrictive for all to authenticated
  using (
    app.current_app_role() <> 'customer'
    or exists (
      select 1 from public.bookings b
       where b.id = booking_items.booking_id
         and b.customer_id = app.current_customer_id()
    )
  );

create policy customer_scope on public.payment_allocations
  as restrictive for all to authenticated
  using (
    app.current_app_role() <> 'customer'
    or exists (
      select 1 from public.payments p
       where p.id = payment_allocations.payment_id
         and p.customer_id = app.current_customer_id()
    )
  );

create policy customer_scope on public.notification_deliveries
  as restrictive for all to authenticated
  using (
    app.current_app_role() <> 'customer'
    or exists (
      select 1 from public.notifications nt
       where nt.id = notification_deliveries.notification_id
         and nt.customer_id = app.current_customer_id()
    )
  );

-- A referral has two customers, and each may see their own side of it.
create policy customer_scope on public.referrals
  as restrictive for all to authenticated
  using (
    app.current_app_role() <> 'customer'
    or referrer_id = app.current_customer_id()
    or referred_customer_id = app.current_customer_id()
  );

-- ---------------------------------------------------------------------------
-- 3. Tables a customer has no business reading at all
-- ---------------------------------------------------------------------------
--
-- `users` is the staff-accounts table: names, roles and PERSONAL MOBILE
-- NUMBERS. A customer was able to read all of it. Stylist names for booking
-- come from `public.staff`, which carries no phone number, so nothing the
-- customer app needs is lost.
--
-- The rest is the salon's own business: what Crayora billed it, what its
-- metrics are, when its staff take time off, what an operator did and why.

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'users', 'audit_log', 'subscriptions', 'feature_flags',
    'daily_salon_metrics', 'retention_cohorts', 'message_templates',
    'staff_schedules', 'staff_time_off'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format($f$
        create policy staff_scope on public.%I
          as restrictive for all to authenticated
          using (app.current_app_role() <> 'customer')
          with check (app.current_app_role() <> 'customer')
      $f$, v_table);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. What a customer SHOULD still see
-- ---------------------------------------------------------------------------
--
-- Deliberately left unrestricted for every tenant role, because the customer
-- app cannot work without them and none of them is personal data:
--   services, add_ons, service_addons  - the menu and its prices
--   staff                              - who they can book with, names only
--   salon_branding                     - the salon's own look
--
-- If one of these ever gains a customer_id or a phone number, section 1 and the
-- gate will start applying to it, which is the intended behaviour.

comment on policy customer_scope on public.customers is
  'RESTRICTIVE (0038): a customer reads only their own row. Staff keep the salon-wide view. Restrictive because a permissive policy added later would otherwise re-open the salon - which is the bug this fixes.';
