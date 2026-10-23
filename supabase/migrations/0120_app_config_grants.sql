-- 0120 The app config tables are read-only to the app - by grant, not only by
-- the absence of a write policy (found by CI, 23 Oct 2026).
--
-- On a fresh Supabase stack, new public tables are granted to anon and
-- authenticated by default; on the hosted project those defaults do not hold
-- (0020). So 0119's tables could be UPDATEd by a signed-in user in CI - RLS
-- then matched no row, but "nothing happened" is not "refused". Close it the
-- way the rest of the schema is closed: revoke everything, grant the read.

revoke all on public.salon_app_config from anon, authenticated;
revoke all on public.salon_announcements from anon, authenticated;
grant select on public.salon_app_config to authenticated;
grant select on public.salon_announcements to authenticated;
