-- 0105 Managers and stylists can be given a login.
--
-- Found 13 Oct 2026: the app has owner, manager and stylist roles, the database
-- has a policy for each, and nothing could create a manager or a stylist LOGIN -
-- the only row public.users ever got was the owner's, at provisioning. So a
-- stylist had no way into the app at all.
--
-- Crayora adds them in the console (audited), like everything else that decides
-- who can do what in a salon. A login is a salon, a name, a number and a role;
-- the person signs in exactly as the owner does - the salon's code, then their
-- own number and its one-time code - and otp_finish_login already turns any
-- active row here into a staff session with that role.
--
-- One number signs in to ONE salon: resolve_otp_sender picks a number's salon
-- from its active login, so a second salon for the same number would make the
-- login ambiguous. A deactivated login stops the next sign-in; the owner's
-- login is changed through a transfer, never switched off here.

create or replace function app_admin.add_salon_login(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_name           text,
  p_phone          text,
  p_role           text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text := nullif(btrim(coalesce(p_name, '')), '');
  v_hash  bytea;
  v_phone text;
  v_id    uuid := extensions.gen_random_uuid();
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_role not in ('manager', 'staff') then
    raise exception 'app_admin: a login added here is a manager or a stylist - the owner is set at provisioning';
  end if;
  if v_name is null then
    raise exception 'app_admin: the person''s name is required - the salon sees it on every action they take';
  end if;
  if not exists (select 1 from public.salons where id = p_salon_id) then
    raise exception 'app_admin: no such salon';
  end if;

  -- Raises a readable error for anything that is not an Indian mobile number.
  v_hash := app.phone_hash(p_phone);
  v_phone := app.canonical_phone(p_phone);

  if exists (select 1 from public.users u where u.phone_hash = v_hash and u.active) then
    raise exception 'app_admin: that number already signs in to a salon - one number, one salon login. Switch the other login off first';
  end if;

  insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
  values (v_id, p_salon_id, p_role::public.user_role, v_name, v_phone, v_hash, true);

  -- The audit names the person and the role, and only the number's last four.
  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'login.added', 'users', v_id::text, null, null,
    jsonb_build_object('name', v_name, 'role', p_role, 'phone_last4', right(v_phone, 4)));

  return v_id;
end;
$$;

comment on function app_admin.add_salon_login is
  'Crayora only: gives a manager or a stylist a login to one salon - they sign in with the salon code and their own number (0105). Audited.';

create or replace function app_admin.set_salon_login_active(
  p_actor_admin_id uuid,
  p_user_id        uuid,
  p_active         boolean,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user record;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: say why - it is kept in the audit trail';
  end if;

  select id, salon_id, role::text as role, active, phone_hash into v_user
    from public.users where id = p_user_id;
  if not found then
    raise exception 'app_admin: no such login';
  end if;
  if v_user.role = 'owner' then
    raise exception 'app_admin: the owner''s login is not switched off here - change the owner through a transfer';
  end if;
  if p_active and exists (
    select 1 from public.users u
     where u.phone_hash = v_user.phone_hash and u.active and u.id <> p_user_id) then
    raise exception 'app_admin: that number already signs in to another salon - switch that login off first';
  end if;

  update public.users set active = p_active, updated_at = now() where id = p_user_id;

  perform app_admin.audit(
    v_user.salon_id, p_actor_admin_id,
    case when p_active then 'login.activated' else 'login.deactivated' end,
    'users', p_user_id::text, p_reason,
    jsonb_build_object('active', v_user.active), jsonb_build_object('active', p_active));
end;
$$;

comment on function app_admin.set_salon_login_active is
  'Crayora only: switches a manager or stylist login off (or back on), with a reason. Never the owner''s (0105). Audited.';

select app_admin.close_privileges();
