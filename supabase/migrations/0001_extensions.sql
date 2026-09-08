-- 0001 Extensions
--
-- Kept in `extensions`, not `public`, so nothing here is reachable through
-- PostgREST and the public schema stays exactly what we put in it.

create extension if not exists pgcrypto with schema extensions;

-- btree_gist lets an exclusion constraint mix equality (salon_id, staff_id)
-- with range overlap (&&). Without it the no-double-booking constraint in
-- 0011 cannot be expressed at all (ARCHITECTURE 6.5).
create extension if not exists btree_gist with schema extensions;

-- pgTAP runs the release gates: the cross-tenant leak test, the binding
-- exclusivity test and the money test (RULES.md 12).
create extension if not exists pgtap with schema extensions;

comment on extension pgtap is
  'Test framework for the release gates. Never remove - the leak test depends on it.';
