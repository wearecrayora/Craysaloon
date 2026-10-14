-- 0106 The salon owner adds their own staff logins, from the app.
--
-- Decided 14 Oct 2026. 0105 let Crayora give a manager or stylist a login in
-- the console; a salon that hires a stylist on Saturday should not have to wait
-- for Crayora. So the OWNER - not a manager, not a stylist - can do the same
-- from the app's Team screen, for their own salon only, with the same rules:
--
--   * manager or stylist only; the owner's own login is never created,
--     changed or switched off here;
--   * one number signs in to one salon (resolve_otp_sender picks a number's
--     salon from its active login);
--   * every act is in the audit trail as the owner's.
--
-- A login says who can OPEN the salon's screens; what each role may then do is
-- still decided row by row by the policies (RULES 3.8b) - a stylist cannot
-- change the menu however they got in.

create or replace function public.list_staff_logins()
returns table(id uuid, role text, name text, phone_last4 text, active boolean, signed_in boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
begin
  if v_salon is null or app.current_app_role() is distinct from 'owner' then
    raise exception 'list_staff_logins: only the salon''s owner manages logins'
      using errcode = '42501';
  end if;
  return query
    select u.id, u.role::text, u.name, right(u.phone, 4), u.active, (u.auth_user_id is not null)
      from public.users u
     where u.salon_id = v_salon
     order by (u.role = 'owner') desc, u.active desc, u.name;
end;
$$;

comment on function public.list_staff_logins() is
  'The owner''s view of who can sign in to their salon - numbers by their last four only (0106).';

create or replace function public.add_staff_login(p_name text, p_phone text, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_name  text := nullif(btrim(coalesce(p_name, '')), '');
  v_hash  bytea;
  v_phone text;
  v_id    uuid := extensions.gen_random_uuid();
begin
  if v_salon is null or app.current_app_role() is distinct from 'owner' then
    raise exception 'add_staff_login: only the salon''s owner adds logins'
      using errcode = '42501';
  end if;
  if p_role not in ('manager', 'staff') then
    return jsonb_build_object('ok', false, 'reason', 'bad_role');
  end if;
  if v_name is null then
    return jsonb_build_object('ok', false, 'reason', 'name_required');
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  begin
    v_hash := app.phone_hash(p_phone);
    v_phone := app.canonical_phone(p_phone);
  exception when others then
    return jsonb_build_object('ok', false, 'reason', 'bad_phone');
  end;

  if exists (select 1 from public.users u where u.phone_hash = v_hash and u.active) then
    -- Says THAT the number is taken, never where: the other salon is not this
    -- owner's to know about (RULES 4.4).
    return jsonb_build_object('ok', false, 'reason', 'number_in_use');
  end if;

  insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
  values (v_id, v_salon, p_role::public.user_role, v_name, v_phone, v_hash, true);

  insert into public.audit_log (salon_id, actor_user_id, actor_kind, action, entity,
                                entity_id, before_state, after_state)
  values (v_salon, auth.uid(), 'owner', 'login.added', 'users', v_id::text, null,
          jsonb_build_object('name', v_name, 'role', p_role, 'phone_last4', right(v_phone, 4)));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

comment on function public.add_staff_login(text, text, text) is
  'The OWNER gives a manager or stylist a login to their own salon (0106). Audited as the owner''s act.';

create or replace function public.set_staff_login_active(p_user_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_user  record;
begin
  if v_salon is null or app.current_app_role() is distinct from 'owner' then
    raise exception 'set_staff_login_active: only the salon''s owner manages logins'
      using errcode = '42501';
  end if;

  select u.id, u.role::text as role, u.active, u.phone_hash into v_user
    from public.users u
   where u.id = p_user_id and u.salon_id = v_salon;
  if not found then
    -- Another salon's login and no login at all look the same.
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_user.role = 'owner' then
    return jsonb_build_object('ok', false, 'reason', 'owner_login');
  end if;
  if p_active and exists (
    select 1 from public.users u
     where u.phone_hash = v_user.phone_hash and u.active and u.id <> p_user_id) then
    return jsonb_build_object('ok', false, 'reason', 'number_in_use');
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  update public.users set active = p_active, updated_at = now() where id = p_user_id;

  insert into public.audit_log (salon_id, actor_user_id, actor_kind, action, entity,
                                entity_id, before_state, after_state)
  values (v_salon, auth.uid(), 'owner',
          case when p_active then 'login.activated' else 'login.deactivated' end,
          'users', p_user_id::text,
          jsonb_build_object('active', v_user.active), jsonb_build_object('active', p_active));

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.set_staff_login_active(uuid, boolean) is
  'The OWNER switches a manager or stylist login off or back on - never their own (0106). Audited.';

revoke all on function public.list_staff_logins() from public, anon;
revoke all on function public.add_staff_login(text, text, text) from public, anon;
revoke all on function public.set_staff_login_active(uuid, boolean) from public, anon;
grant execute on function public.list_staff_logins() to authenticated;
grant execute on function public.add_staff_login(text, text, text) to authenticated;
grant execute on function public.set_staff_login_active(uuid, boolean) to authenticated;
