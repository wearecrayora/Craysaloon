-- 0090 A purged salon stays closed - enforced at the door that exists.
--
-- 0089 added a "purged" refusal to activate_salon, after its setup check. A
-- purged salon is always suspended, so activate_salon refused it anyway and the
-- new line could never run: dead code that read like a guarantee. The door a
-- purged salon could actually be moved through is set_salon_status (grace,
-- suspended), so the refusal belongs there. The dead line is removed.

do $$
declare
  v_def text;
  v_new text;
begin
  -- Remove the unreachable check from activate_salon.
  select pg_get_functiondef(
           'app_admin.activate_salon(uuid, uuid, text)'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$  if exists (select 1 from public.salons where id = p_salon_id and purged_at is not null) then
    raise exception 'app_admin: this salon was purged - it cannot be activated again';
  end if;

$x$, '');
  if v_new = v_def then raise exception '0090: activate_salon shape'; end if;
  execute v_new;

  -- Refuse any status change on a purged salon.
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p
   where p.proname = 'set_salon_status' and p.pronamespace = 'app_admin'::regnamespace;
  v_new := replace(v_def,
    $x$  perform app_admin.assert_admin(p_actor_admin_id);
$x$,
    $x$  perform app_admin.assert_admin(p_actor_admin_id);

  -- 0090: nothing personal is left to come back to. A purged salon's status is
  -- final; its books are reachable only through the console.
  if exists (select 1 from public.salons where id = p_salon_id and purged_at is not null) then
    raise exception 'app_admin: this salon was purged - its status cannot change';
  end if;
$x$);
  if v_new = v_def then raise exception '0090: set_salon_status shape'; end if;
  execute v_new;
end;
$$;

select app_admin.close_privileges();
