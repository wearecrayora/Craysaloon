-- 0005 Tenancy helpers that depend on tables
--
-- These could not live in 0002: Postgres validates `language sql` function
-- bodies at CREATE time (check_function_bodies is on), so a helper that reads
-- public.customers cannot be defined before that table exists. Splitting them
-- out is cleaner than turning the check off.
--
-- Same rules as 0002: `stable` so each is an InitPlan evaluated once per
-- statement, `security definer` with a pinned empty search_path.

-- The caller's own customer row inside their salon.
--
-- Deliberately a separate function rather than a subquery inlined into each
-- policy: `stable` means it is evaluated once per statement, and having one
-- definition means one place to audit.
create or replace function app.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
    from public.customers c
   where c.auth_user_id = (select auth.uid())
     and c.salon_id = app.current_salon_id()
     and c.deleted_at is null
   limit 1
$$;

-- ---------------------------------------------------------------------------
-- Write gating
-- ---------------------------------------------------------------------------

-- Suspended and past-due tenants keep SELECT and lose INSERT/UPDATE, enforced
-- HERE rather than by hiding buttons (ARCHITECTURE 5.5). A business rule that
-- exists only in the UI is not a business rule.
--
-- 'setup' is deliberately NOT writable: a salon that has been provisioned but
-- not yet activated by an operator cannot take bookings, even if its QR code
-- has leaked (ARCHITECTURE 5.7).
create or replace function app.salon_writable(p_salon uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.salons s
     where s.id = p_salon
       and s.status = 'active'
  )
$$;

comment on function app.salon_writable(uuid) is
  'False for setup, grace and suspended salons. Gates every with-check.';
