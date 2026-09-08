-- GATE: tenant-scoped indexes lead with salon_id
--
-- RULES.md 3.1 requires salon_id to lead every composite index on a tenant
-- table. The reason is not tidiness: forced RLS adds an implicit
-- `salon_id = app.current_salon_id()` to every tenant query, so an index that
-- does not lead with salon_id cannot serve that query and Postgres falls back
-- to a scan that gets slower with every salon onboarded.
--
-- Written after an audit found four composite indexes breaking the rule as
-- stated - and concluded that all four were correct and the RULE was wrong.
-- Two of them MUST NOT lead with salon_id:
--
--   * a global uniqueness constraint (webhook idempotency) would stop being
--     global, and the same provider event could be replayed under a second
--     salon;
--   * a partial unique index over the global defaults is defined precisely
--     where salon_id IS NULL, so there is nothing to lead with.
--
-- So this gate enforces the rule WITH its exceptions named and justified,
-- catalogue-driven like the leak test: an index added tomorrow is covered
-- tomorrow, and a new violation must be argued for in this file rather than
-- discovered in production.

select plan(3);

-- ---------------------------------------------------------------------------
-- 1. No undocumented violations
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
     from pg_index ix
     join pg_class i on i.oid = ix.indexrelid
     join pg_class c on c.oid = ix.indrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and array_length(ix.indkey, 1) > 1
      -- only tables that are actually tenant-scoped
      and exists (
        select 1 from information_schema.columns col
         where col.table_schema = 'public'
           and col.table_name = c.relname
           and col.column_name = 'salon_id')
      -- leading column is not salon_id
      and (select a.attname from pg_attribute a
            where a.attrelid = c.oid and a.attnum = ix.indkey[0])
          is distinct from 'salon_id'
      -- EXCEPTION A: a partial index defined over the global rows. salon_id is
      -- NULL across the whole index, so it cannot lead and would not help.
      and coalesce(pg_get_expr(ix.indpred, ix.indrelid), '') !~* 'salon_id IS NULL'
      -- EXCEPTION B: documented, justified, and asserted to still exist below.
      and i.relname not in (
        -- Global by design: idempotency must hold across every salon, or the
        -- same provider event can be replayed under a different tenant.
        'webhook_events_provider_event_id_key',
        -- Natural-key primary key of a join table. salon_id is implied by
        -- service_id, and service_addons_salon_idx (salon_id, service_id)
        -- already serves the tenant-scoped lookups.
        'service_addons_pkey',
        -- Serves the Crayora admin plane ("what did this operator do"), which
        -- is deliberately cross-tenant. Tenant reads use
        -- audit_log_salon_idx (salon_id, created_at desc).
        'audit_log_actor_idx'
      )),
  0,
  'every composite index on a tenant table leads with salon_id, or is documented here'
);

-- ---------------------------------------------------------------------------
-- 2. The exemption list has no dead entries
-- ---------------------------------------------------------------------------
--
-- A stale exemption is worse than none: it is a name sitting in an allow-list,
-- waiting for a future index to be created with the same name and inherit a
-- permission nobody granted it.

select is(
  (select count(*)::int
     from unnest(array[
       'webhook_events_provider_event_id_key',
       'service_addons_pkey',
       'audit_log_actor_idx'
     ]) as wanted(name)
    where not exists (
      select 1 from pg_class i
        join pg_namespace n on n.oid = i.relnamespace
       where n.nspname = 'public' and i.relname = wanted.name)),
  0,
  'every documented exemption still names an index that exists'
);

-- ---------------------------------------------------------------------------
-- 3. Webhook idempotency stays global
-- ---------------------------------------------------------------------------
--
-- Stated as its own assertion because "fixing" this index to satisfy rule 3.1
-- is a plausible, well-intentioned change that would open a replay hole. If
-- someone adds salon_id to it, they should be told why not.

select is(
  (select count(*)::int
     from pg_index ix
     join pg_class i on i.oid = ix.indexrelid
     join pg_attribute a on a.attrelid = ix.indrelid
    where i.relname = 'webhook_events_provider_event_id_key'
      and a.attnum = any(ix.indkey)
      and a.attname = 'salon_id'),
  0,
  'webhook idempotency is GLOBAL - salon_id must never enter that unique index'
);

select * from finish();
