-- 0016 Grants, stated explicitly
--
-- FOUND BY REBUILDING THE SCHEMA FROM ZERO.
--
-- Every earlier migration relied on Supabase's DEFAULT privileges, which grant
-- all on new tables in `public` to anon and authenticated. 0014 then revoked
-- what should not have been there. The net result happened to be right - but
-- only because the tables were created into a schema that already carried
-- those defaults.
--
-- Drop and recreate `public`, as `supabase start` effectively does on a fresh
-- database, and the defaults are gone: tables arrive with NO grants, the
-- revokes remove nothing, and `authenticated` cannot read its own salon's
-- customers. RLS policies never even get consulted, because a missing SELECT
-- grant denies access first.
--
-- So the permission model is now DECLARED here rather than inherited. Revoke
-- everything, then grant exactly what each class of table needs. Idempotent,
-- reproducible on any database, and readable in one place.
--
-- The three classes mirror 0012 exactly:
--   FULL      select, insert, update      - tenant-owned operational data
--   READONLY  select                      - written only by security definer
--                                           functions and automations
--   NONE      nothing                     - cross-tenant, secrets, machinery

-- ---------------------------------------------------------------------------
-- Start from zero, so this file is the whole truth.
-- ---------------------------------------------------------------------------

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- anon keeps nothing, forever. Its only legitimate entry points are security
-- definer functions (resolve_join_code, start_join at M3), which need no
-- table grant at all.
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;

do $$
declare
  t text;

  -- Written only by security definer functions and automations. The ledgers
  -- are here: no write grant is what makes "no owner or manager path to a
  -- balance" true at the grant layer (RULES 5.2).
  readonly constant text[] := array[
    'wallet_accounts', 'wallet_lots', 'wallet_transactions', 'loyalty_ledger',
    'payments', 'payment_allocations',
    'audit_log', 'daily_salon_metrics', 'retention_cohorts',
    'notifications', 'notification_deliveries',
    'subscriptions', 'feature_flags', 'referrals',
    'customer_service_intervals', 'salon_branding'
  ];

  -- No tenant access of any kind. Forced RLS already denies them; removing the
  -- grant means two things must go wrong, not one.
  none constant text[] := array[
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
     where n.nspname = 'public'
       and c.relkind = 'r'
     order by c.relname
  loop
    if t = any(none) then
      continue;
    elsif t = any(readonly) then
      execute format('grant select on public.%I to authenticated', t);
    else
      execute format(
        'grant select, insert, update on public.%I to authenticated', t);
    end if;
  end loop;
end;
$$;

-- `consents` is append-only by design, so authenticated gets INSERT but never
-- UPDATE: withdrawing consent is a NEW ROW, never an edit (RULES 11.6).
revoke update on public.consents from authenticated;

-- Identity-column tables that tenants may write need their sequence. None
-- currently qualify - every writable table uses a uuid default - but state the
-- intent so a future identity PK on a writable table is a deliberate decision.
-- (No grant issued here on purpose.)

-- ---------------------------------------------------------------------------
-- Guard: the app must actually be able to read.
-- ---------------------------------------------------------------------------
--
-- A schema where authenticated can read nothing is not "secure", it is broken,
-- and the leak test would still pass because zero rows are visible either way.
-- Fail the migration instead.

do $$
declare
  v_missing int;
begin
  select count(*) into v_missing
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join information_schema.columns col
      on col.table_schema = 'public'
     and col.table_name = c.relname
     and col.column_name = 'salon_id'
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname not in (
       'customer_identities', 'binding_events', 'join_intents',
       'salon_integrations', 'domain_events', 'jobs',
       'idempotency_keys', 'webhook_events')
     and not has_table_privilege('authenticated', c.oid, 'SELECT');

  if v_missing > 0 then
    raise exception
      '% tenant table(s) are unreadable by authenticated - the app would be broken',
      v_missing;
  end if;
end;
$$;
