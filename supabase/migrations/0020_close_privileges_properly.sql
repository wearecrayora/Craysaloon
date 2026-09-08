-- 0020 The admin plane is closed by CALLING something, not by declaring it
--
-- 0019 IS WRONG. This corrects it.
--
-- 0019 ran:
--
--     alter default privileges in schema app_admin revoke execute on functions from public;
--
-- and claimed, in a comment on the schema, that a function added to app_admin
-- is therefore closed the moment it is created. That claim was never tested.
-- It is false on this database:
--
--     create function app_admin.probe_fn() returns int language sql as 'select 1';
--     select has_function_privilege('authenticated', 'app_admin.probe_fn()', 'EXECUTE');
--     -- t
--     select count(*) from pg_default_acl d
--       join pg_namespace n on n.oid = d.defaclnamespace
--      where n.nspname = 'app_admin';
--     -- 0
--
-- The ALTER records no pg_default_acl row and has no effect, so a new function
-- in the admin plane is EXECUTE-able by PUBLIC, and therefore by every
-- authenticated tenant user, exactly as before. (`postgres` is not a superuser
-- on Supabase; an event trigger, which would be the other way to do this,
-- needs superuser and is not available either.)
--
-- This is the same mistake this repository keeps finding: a protection that
-- was asserted rather than verified. It was caught immediately, by the
-- negative control added earlier today - the canary function it creates tripped
-- BOTH the audit assertion it was designed to trip and
-- `no app_admin function is executable by anon or authenticated`.
--
-- So: stop trying to make it automatic, and make it explicit and checkable.
-- Any migration that adds a function to app_admin must call
-- app_admin.close_privileges() afterwards. If it forgets:
--
--   * the guard at the end of this file and of 0017 fails that migration, and
--   * the admin-plane release gate goes red,
--
-- both of which are loud. What is NOT relied on any more is a silent default.

create or replace function app_admin.close_privileges()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  f    record;
  v_open int;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app_admin'
  loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('revoke all on function %s from anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;

  -- Verify rather than assume. That distinction is the entire point of this
  -- migration existing.
  select count(*) into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_admin'
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
       or has_function_privilege('anon', p.oid, 'EXECUTE'));

  if v_open > 0 then
    raise exception
      'app_admin.close_privileges: % function(s) are still tenant-executable', v_open;
  end if;
end;
$$;

comment on function app_admin.close_privileges is
  'Call this at the end of EVERY migration that adds a function to app_admin. CREATE FUNCTION grants EXECUTE to PUBLIC, and ALTER DEFAULT PRIVILEGES does not stick on this database (see 0020) - so closing the plane is an action, not a property.';

select app_admin.close_privileges();

-- Correct the false claim 0019 left on the schema.
comment on schema app_admin is
  'The Crayora admin plane. Not exposed through PostgREST; callable only by service_role. A function added here is PUBLIC-executable until app_admin.close_privileges() is called - which every migration adding one must do, and which the admin-plane release gate verifies.';
