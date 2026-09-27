-- 0044 my_salon_id() is closed to anon
--
-- 0043 wrote `revoke all on function public.my_salon_id() from public`, which
-- removes the PUBLIC grant and looks complete. It is not: Supabase's default
-- privileges grant EXECUTE on new functions in `public` **directly to anon,
-- authenticated and service_role**, and a grant to a role survives a revoke from
-- PUBLIC. So the function stayed anon-callable.
--
-- The join-flow gate caught it - "the entire pre-auth surface is two functions
-- in public, and nothing else" - and caught it in CI while the hosted project
-- looked clean, because the two databases disagree about those default
-- privileges (the same disagreement that produced 0020's close_privileges()).
-- The gate is right either way: the pre-auth surface is a list, not a shape, and
-- nothing joins it by default.
--
-- Nothing was exposed by this in practice: the function returns the caller's own
-- salon out of the caller's own token, and an anon caller has no token, so it
-- returns null. The rule still holds - what is reachable before login is
-- enumerated deliberately, and this was not on that list.

revoke all on function public.my_salon_id() from anon;

-- The lesson, in the place it will be needed again: revoking from PUBLIC is not
-- revoking from the roles PostgREST serves.
comment on function public.my_salon_id is
  'The caller''s own salon, from their own token, so `salon_id` columns can default to it (0043). Closed to anon (0044): revoking from PUBLIC does NOT remove the direct grants Supabase''s default privileges hand to anon/authenticated/service_role - revoke from the role by name.';
