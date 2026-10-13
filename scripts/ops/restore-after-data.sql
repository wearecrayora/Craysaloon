-- Run on the NEW database after the data is loaded (docs/runbooks/restore.md,
-- restore-drill.yml): Supabase's stock default privileges back on, so every
-- migration applied after the restore behaves exactly as it does on the
-- original project - create, then revoke what must not be granted.
-- The restored objects themselves are not touched: defaults apply only to
-- objects created from now on.

alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;
