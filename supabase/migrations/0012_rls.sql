-- 0012 Row-Level Security
--
-- The most important file in the database. Three principles:
--
--   1. RLS is ENABLED AND FORCED on every table. `force` matters: without it
--      the table owner bypasses RLS entirely, and a migration or a mis-scoped
--      connection silently reads everything (RULES 3.2).
--
--   2. Policies are generated in a LOOP over the catalogue, not hand-written
--      per table. Hand-written policies rot: someone adds a table and forgets.
--      A loop cannot forget, and the leak test then checks the catalogue too.
--
--   3. Three classes of table:
--        FULL      tenant reads and writes, writes gated on salon_writable()
--        READONLY  tenant reads; writes only via security definer functions
--        NONE      no policies at all - forced RLS then denies everyone
--
-- Nothing here grants anything to `anon`. The only public entry points are
-- security definer functions (resolve_join_code, start_join), added at M3.

-- ---------------------------------------------------------------------------
-- Step 1: enable AND force on every base table, without exception.
-- ---------------------------------------------------------------------------

do $$
declare
  t record;
begin
  for t in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
  loop
    execute format('alter table public.%I enable row level security', t.relname);
    execute format('alter table public.%I force  row level security', t.relname);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Step 2: tenant policies, generated from the catalogue.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
  -- Tenants may read but NEVER write these directly. The ledgers are the
  -- point: only the five callers in RULES 5.2 may post, and they are
  -- security definer, so they bypass RLS. Removing write policies here is
  -- what makes "no owner or manager path exists" true at the database.
  readonly constant text[] := array[
    'wallet_accounts', 'wallet_lots', 'wallet_transactions', 'loyalty_ledger',
    'payments', 'payment_allocations',
    'audit_log', 'daily_salon_metrics', 'retention_cohorts',
    'notifications', 'notification_deliveries',
    'subscriptions', 'feature_flags', 'referrals',
    'customer_service_intervals'
  ];
  -- No policies at all. Forced RLS then denies every tenant role.
  --   cross-tenant : customer_identities, binding_events, join_intents
  --   secrets      : salon_integrations
  --   platform     : platform_admins
  --   machinery    : reachable only by the service role
  no_policy constant text[] := array[
    'customer_identities', 'binding_events', 'join_intents',
    'salon_integrations', 'platform_admins',
    'domain_events', 'jobs', 'idempotency_keys', 'webhook_events',
    'rate_limit_counters', 'schema_migrations'
  ];
begin
  for t in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join information_schema.columns col
        on col.table_schema = 'public'
       and col.table_name = c.relname
       and col.column_name = 'salon_id'
     where n.nspname = 'public'
       and c.relkind = 'r'
     order by c.relname
  loop
    if t = any(no_policy) then
      continue;
    end if;

    -- Read: anything inside my salon.
    execute format($p$
      create policy %1$I on public.%1$I
        for select to authenticated
        using (salon_id = app.current_salon_id())
    $p$, t);

    if not (t = any(readonly)) then
      -- Write: inside my salon AND the salon is active. A suspended or
      -- past-due tenant keeps SELECT and loses INSERT/UPDATE at the
      -- database, not by hiding buttons (ARCHITECTURE 5.5).
      execute format($p$
        create policy %1$I_insert on public.%1$I
          for insert to authenticated
          with check (salon_id = app.current_salon_id()
                      and app.salon_writable(salon_id))
      $p$, t);

      execute format($p$
        create policy %1$I_update on public.%1$I
          for update to authenticated
          using (salon_id = app.current_salon_id())
          with check (salon_id = app.current_salon_id()
                      and app.salon_writable(salon_id))
      $p$, t);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Step 3: salons and salon_branding key on `id`, not `salon_id`.
-- ---------------------------------------------------------------------------

create policy salons_select on public.salons
  for select to authenticated
  using (id = app.current_salon_id());

-- Deliberately no insert policy: salons are created ONLY through the console,
-- by app_admin.provision_salon (RULES 1.6).
create policy salons_update on public.salons
  for update to authenticated
  using (id = app.current_salon_id())
  with check (id = app.current_salon_id() and app.salon_writable(id));

create policy salon_branding_select on public.salon_branding
  for select to authenticated
  using (salon_id = app.current_salon_id());

-- ---------------------------------------------------------------------------
-- Step 4: narrower policies WITHIN a salon.
-- ---------------------------------------------------------------------------
--
-- Permissive policies are OR-ed, so these ADD access for customers; they do
-- not restrict staff. A customer sees their own rows, a staff principal sees
-- the whole salon, and neither can express a query that crosses salon_id.

create policy bookings_customer_own on public.bookings
  for select to authenticated
  using (salon_id = app.current_salon_id()
         and customer_id = app.current_customer_id());

create policy visits_customer_own on public.visits
  for select to authenticated
  using (salon_id = app.current_salon_id()
         and customer_id = app.current_customer_id());

create policy wallet_transactions_customer_own on public.wallet_transactions
  for select to authenticated
  using (salon_id = app.current_salon_id()
         and customer_id = app.current_customer_id());

-- A customer may withdraw consent themselves. Withdrawal must be as easy as
-- consent (RULES 11.6), and it is an append: a new row, never an update.
create policy consents_customer_insert on public.consents
  for insert to authenticated
  with check (salon_id = app.current_salon_id()
              and customer_id = app.current_customer_id());

-- ---------------------------------------------------------------------------
-- Step 5: message_templates - platform defaults are readable by everyone.
-- ---------------------------------------------------------------------------

create policy message_templates_platform_defaults on public.message_templates
  for select to authenticated
  using (salon_id is null);
