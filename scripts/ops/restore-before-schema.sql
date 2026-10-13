-- Run on the NEW database immediately before schema.sql (docs/runbooks/restore.md,
-- restore-drill.yml).
--
-- A new Supabase project grants anon, authenticated and service_role on every
-- table, sequence and function postgres creates in `public` - by default
-- privilege. Our migrations REVOKE those after each CREATE; a dump, though,
-- records only the grants an object HAS, never the ones taken away. Restored
-- with these defaults on, every object comes back wider than the source: anon
-- holding privileges in public, authenticated with write grants on the
-- ledgers, the OTP and credential functions callable by tenants. The fourth
-- restore drill (13 Oct 2026) found exactly that, with every row restored
-- perfectly - the data was right and the security model was gone.
--
-- With the defaults off, each restored object gets exactly the grants the dump
-- lists, which are the source's. restore-after-data.sql turns them back on.

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
