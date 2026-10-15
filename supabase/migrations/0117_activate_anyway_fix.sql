-- 0117 0116's activate_salon_anyway appended to its "skipped" list with
-- `text[] || 'literal'`, which Postgres reads as two arrays and refuses as a
-- malformed array literal - the first call failed. Caught by
-- admin/activate_anyway_test.sql before anyone used it. array_append is the
-- unambiguous form.

create or replace function app_admin.activate_salon_anyway(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   record;
  v_fee_ok  boolean;
  v_skipped text[] := '{}';
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: activating before setup is complete needs a reason - it is the audit entry';
  end if;

  select status, grievance_name, grievance_email, grievance_phone into v_salon
    from public.salons where id = p_salon_id for update;
  if v_salon.status is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;
  if v_salon.status <> 'setup' then
    raise exception 'app_admin: only a salon in setup can be activated (this one is %)', v_salon.status;
  end if;

  select exists (select 1 from public.subscriptions s
                  where s.salon_id = p_salon_id and s.setup_fee_status in ('paid', 'waived'))
    into v_fee_ok;
  if not v_fee_ok then
    v_skipped := array_append(v_skipped, 'setup_fee');
  end if;
  if coalesce(btrim(coalesce(v_salon.grievance_name, '')), '') = ''
     or (coalesce(btrim(coalesce(v_salon.grievance_email, '')), '') = ''
         and coalesce(btrim(coalesce(v_salon.grievance_phone, '')), '') = '') then
    v_skipped := array_append(v_skipped, 'privacy_contact');
  end if;
  if not exists (select 1 from public.salon_integrations i
                  where i.salon_id = p_salon_id and i.provider = 'message_central'
                    and i.vault_secret_id is not null) then
    v_skipped := array_append(v_skipped, 'message_central');
  end if;

  update public.salons
     set status       = 'active'::public.salon_status,
         activated_by = p_actor_admin_id,
         activated_at = now(),
         updated_at   = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.activated_anyway', 'salons', p_salon_id::text,
    btrim(p_reason), jsonb_build_object('status', v_salon.status),
    jsonb_build_object('status', 'active', 'skipped', to_jsonb(v_skipped)));

  return jsonb_build_object('ok', true, 'skipped', to_jsonb(v_skipped));
end;
$$;

select app_admin.close_privileges();
