-- 0043 A tenant insert cannot name the wrong salon, or forget to name one
--
-- THE BUG. The owner app's "add a service" sent no `salon_id`, because I assumed
-- the column defaulted to the caller's salon. It does not: `salon_id` is NOT
-- NULL with no default, so every create from the app would have failed with a
-- not-null violation. Found by reading the catalogue in the schema rather than
-- trusting the comment I had written next to the insert.
--
-- Neither test caught it, and that is the more useful lesson:
--   * the pgTAP write-scope test inserts with an explicit salon_id, so it
--     exercised a payload the app never sends;
--   * the widget test used a fake write implementation, which cannot know what
--     the real table requires.
-- The gate added below inserts EXACTLY what the app sends - no salon_id at all.
--
-- THE FIX, and why a default rather than sending it from the client. The client
-- could send `salon_id` and the policy's WITH CHECK would refuse a wrong one, so
-- that would be safe. A default is better: the value the client cannot send is
-- the value the client cannot get wrong, and every future insert - bookings,
-- consents, anything M6 adds - inherits the same protection without anyone
-- remembering to.
--
-- `public.my_salon_id()` exists because column defaults are evaluated as the
-- INSERTING role, and tenant roles have no USAGE on `app` (0025, the phone_hash
-- oracle). It exposes nothing: the caller's own salon, out of the caller's own
-- token, which they already hold.

create or replace function public.my_salon_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select app.current_salon_id()
$$;

comment on function public.my_salon_id is
  'The caller''s own salon, from their own token. Exists so `salon_id` columns can default to it: a value the client never sends is a value the client cannot get wrong (0043). Discloses nothing - the caller already holds the token it reads.';

revoke all on function public.my_salon_id() from public;
grant execute on function public.my_salon_id() to authenticated, service_role;

-- The tables the app inserts into today. The console passes salon_id explicitly
-- through app_admin, and an explicit value always wins, so nothing there changes.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['services', 'add_ons', 'service_addons', 'staff'] loop
    execute format(
      'alter table public.%I alter column salon_id set default public.my_salon_id()', v_table);
  end loop;
end;
$$;
