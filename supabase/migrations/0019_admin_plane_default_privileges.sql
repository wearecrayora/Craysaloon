-- 0019 The admin plane is closed by default, not closed by remembering
--
-- FOUND BY THE NEGATIVE CONTROL.
--
-- 0017 ends with a loop that revokes EXECUTE from public/anon/authenticated on
-- every app_admin function and grants it to service_role. That correctly closed
-- the functions that existed when it ran.
--
-- Then the audit negative control created one more function in app_admin - a
-- canary that mutates without auditing - and TWO assertions went red, not one.
-- The expected one (no audit) and this one:
--
--     not ok 1 - no app_admin function is executable by anon or authenticated
--
-- because `create function` grants EXECUTE to PUBLIC by default. So any
-- function a future migration adds to this schema is callable by every
-- authenticated tenant user from the moment it is created until somebody
-- remembers to re-run 0017's loop. Provisioning, activation and credential
-- writing would be one forgotten loop away from being tenant-reachable.
--
-- The 0017 guard would have caught it at migration time, which is good. Making
-- it impossible is better: default privileges apply to functions that do not
-- exist yet.

alter default privileges in schema app_admin revoke execute on functions from public;

-- And re-close anything already created, so this file does not depend on the
-- order it happened to be applied in.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app_admin'
  loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end;
$$;

comment on schema app_admin is
  'The Crayora admin plane. Not exposed through PostgREST; callable only by service_role. Default privileges revoke EXECUTE from PUBLIC, so a function added here is closed the moment it is created rather than when someone remembers to close it (RULES 6.6).';
