-- 0115 Found by the first breach-runbook rehearsal (15 Oct 2026).
--
-- The runbook's containment for "console access by someone who should not have
-- it" said: deactivate the operator's row in platform_admins, then rotate their
-- credentials. There was no function and no console action for it - in a real
-- incident, the first containment step would have been hand-written SQL on
-- production, at night, under pressure. Now it is a super-admin action:
--
--   * audited, with a reason;
--   * it ends the operator's sessions at once (a stolen phone with a live
--     console session is exactly the case it exists for);
--   * nobody deactivates themselves (an incident is not when to lock out the
--     only person able to act), and the last active super-admin stays.

create or replace function app_admin.list_operators(p_actor_admin_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'email', a.email,
                                        'is_super', a.is_super, 'active', a.active)
                     order by a.active desc, a.name)
      from public.platform_admins a), '[]'::jsonb);
end;
$$;

create or replace function app_admin.set_operator_active(
  p_actor_admin_id uuid,
  p_admin_id       uuid,
  p_active         boolean,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before boolean;
  v_super  boolean;
  v_ended  integer := 0;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a reason is required - it is the audit entry';
  end if;
  if p_admin_id = p_actor_admin_id then
    raise exception 'app_admin: you cannot change your own access - ask another super-admin';
  end if;

  select active, is_super into v_before, v_super
    from public.platform_admins where id = p_admin_id for update;
  if v_before is null then
    raise exception 'app_admin: no such operator';
  end if;

  if not p_active and v_super and (
       select count(*) from public.platform_admins where active and is_super and id <> p_admin_id
     ) = 0 then
    raise exception 'app_admin: this is the last active super-admin - make another one first';
  end if;

  update public.platform_admins set active = p_active where id = p_admin_id;

  if not p_active then
    -- Their sessions end now: the refresh tokens go with the sessions.
    delete from auth.sessions where user_id = p_admin_id;
    get diagnostics v_ended = row_count;
  end if;

  perform app_admin.audit(
    null, p_actor_admin_id,
    case when p_active then 'operator.reactivated' else 'operator.deactivated' end,
    'platform_admins', p_admin_id::text, btrim(p_reason),
    jsonb_build_object('active', v_before),
    jsonb_build_object('active', p_active, 'sessions_ended', v_ended));

  return jsonb_build_object('ok', true, 'active', p_active, 'sessions_ended', v_ended);
end;
$$;

select app_admin.close_privileges();
