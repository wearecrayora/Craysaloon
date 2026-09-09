-- 0022 Catalogue and rules, through the admin plane
--
-- Services, add-ons, staff and the salon's operating rules. Every one of these
-- is an admin mutation, so every one goes through a function that writes
-- audit_log in the same transaction (RULES 6.5) rather than through a REST
-- upsert the console composes.
--
-- Upserts rather than separate create/update pairs: the console edits a row it
-- has already rendered, and a null id means "new". One function per entity
-- keeps the audit action names honest - `service.created` and `service.updated`
-- are different facts and are recorded as such.

-- ---------------------------------------------------------------------------
-- Services
-- ---------------------------------------------------------------------------

create or replace function app_admin.upsert_service(
  p_actor_admin_id    uuid,
  p_salon_id          uuid,
  p_service_id        uuid,
  p_name              text,
  p_price_paise       bigint,
  p_duration_minutes  integer,
  p_category          text default null,
  p_repeat_cycle_days integer default null,
  p_active            boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid := p_service_id;
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_name), '') = '' then
    raise exception 'app_admin: a service needs a name';
  end if;
  if p_price_paise < 0 then
    raise exception 'app_admin: a price cannot be negative';
  end if;
  if p_duration_minutes <= 0 then
    raise exception 'app_admin: a service must take some time';
  end if;

  if v_id is null then
    insert into public.services
      (salon_id, name, category, price_paise, duration_minutes, repeat_cycle_days, active)
    values
      (p_salon_id, p_name, p_category, p_price_paise, p_duration_minutes,
       p_repeat_cycle_days, p_active)
    returning id into v_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'service.created', 'services', v_id::text, null, null,
      jsonb_build_object('name', p_name, 'price_paise', p_price_paise,
                         'duration_minutes', p_duration_minutes));
  else
    select to_jsonb(s) into v_before
      from public.services s where s.id = v_id and s.salon_id = p_salon_id;

    if v_before is null then
      -- Naming another salon's service id must not silently create a row here.
      raise exception 'app_admin: service % does not belong to salon %', v_id, p_salon_id;
    end if;

    update public.services
       set name = p_name, category = p_category, price_paise = p_price_paise,
           duration_minutes = p_duration_minutes, repeat_cycle_days = p_repeat_cycle_days,
           active = p_active, updated_at = now()
     where id = v_id and salon_id = p_salon_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'service.updated', 'services', v_id::text, null,
      v_before,
      jsonb_build_object('name', p_name, 'price_paise', p_price_paise,
                         'duration_minutes', p_duration_minutes, 'active', p_active));
  end if;

  return v_id;
end;
$$;

comment on function app_admin.upsert_service is
  'Editing a price does NOT rewrite history: bookings snapshot price into booking_items at the time (PRD 8.2), so past revenue is unaffected by a change here.';

-- ---------------------------------------------------------------------------
-- Add-ons
-- ---------------------------------------------------------------------------

create or replace function app_admin.upsert_add_on(
  p_actor_admin_id         uuid,
  p_salon_id               uuid,
  p_add_on_id              uuid,
  p_name                   text,
  p_price_paise            bigint,
  p_extra_duration_minutes integer default 0,
  p_active                 boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid := p_add_on_id;
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_name), '') = '' then
    raise exception 'app_admin: an add-on needs a name';
  end if;
  if p_price_paise < 0 then
    raise exception 'app_admin: a price cannot be negative';
  end if;

  if v_id is null then
    insert into public.add_ons
      (salon_id, name, price_paise, extra_duration_minutes, active)
    values (p_salon_id, p_name, p_price_paise, coalesce(p_extra_duration_minutes, 0), p_active)
    returning id into v_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'add_on.created', 'add_ons', v_id::text, null, null,
      jsonb_build_object('name', p_name, 'price_paise', p_price_paise));
  else
    select to_jsonb(a) into v_before
      from public.add_ons a where a.id = v_id and a.salon_id = p_salon_id;
    if v_before is null then
      raise exception 'app_admin: add-on % does not belong to salon %', v_id, p_salon_id;
    end if;

    update public.add_ons
       set name = p_name, price_paise = p_price_paise,
           extra_duration_minutes = coalesce(p_extra_duration_minutes, 0),
           active = p_active, updated_at = now()
     where id = v_id and salon_id = p_salon_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'add_on.updated', 'add_ons', v_id::text, null,
      v_before, jsonb_build_object('name', p_name, 'price_paise', p_price_paise,
                                   'active', p_active));
  end if;

  return v_id;
end;
$$;

-- Which add-ons are offered with which service. A join table rather than an
-- array, so a link cannot point at a deleted or cross-tenant service.
create or replace function app_admin.set_service_add_on(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_service_id     uuid,
  p_add_on_id      uuid,
  p_linked         boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if not exists (select 1 from public.services
                  where id = p_service_id and salon_id = p_salon_id) then
    raise exception 'app_admin: service % does not belong to salon %', p_service_id, p_salon_id;
  end if;
  if not exists (select 1 from public.add_ons
                  where id = p_add_on_id and salon_id = p_salon_id) then
    raise exception 'app_admin: add-on % does not belong to salon %', p_add_on_id, p_salon_id;
  end if;

  if p_linked then
    insert into public.service_addons (salon_id, service_id, add_on_id)
    values (p_salon_id, p_service_id, p_add_on_id)
    on conflict do nothing;
  else
    delete from public.service_addons
     where salon_id = p_salon_id and service_id = p_service_id and add_on_id = p_add_on_id;
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id,
    case when p_linked then 'add_on.linked' else 'add_on.unlinked' end,
    'service_addons', p_service_id::text, null, null,
    jsonb_build_object('service_id', p_service_id, 'add_on_id', p_add_on_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff
-- ---------------------------------------------------------------------------

create or replace function app_admin.upsert_staff(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_staff_id       uuid,
  p_name           text,
  p_skills         text[] default '{}',
  p_active         boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid := p_staff_id;
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_name), '') = '' then
    raise exception 'app_admin: a staff member needs a name';
  end if;

  if v_id is null then
    insert into public.staff (salon_id, name, skills, active)
    values (p_salon_id, p_name, coalesce(p_skills, '{}'), p_active)
    returning id into v_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'staff.created', 'staff', v_id::text, null, null,
      jsonb_build_object('name', p_name, 'skills', p_skills));
  else
    select to_jsonb(st) into v_before
      from public.staff st where st.id = v_id and st.salon_id = p_salon_id;
    if v_before is null then
      raise exception 'app_admin: staff % does not belong to salon %', v_id, p_salon_id;
    end if;

    update public.staff
       set name = p_name, skills = coalesce(p_skills, '{}'),
           active = p_active, updated_at = now()
     where id = v_id and salon_id = p_salon_id;

    perform app_admin.audit(
      p_salon_id, p_actor_admin_id, 'staff.updated', 'staff', v_id::text, null,
      v_before, jsonb_build_object('name', p_name, 'active', p_active));
  end if;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Operating rules
-- ---------------------------------------------------------------------------
--
-- BONUS EXPIRY IS NOT SETTABLE HERE, AND THAT IS ENFORCED, NOT DOCUMENTED.
--
-- RULES 5.3.3 and CLAUDE.md rule 7: bonus expiry is set by the OWNER, in the
-- app, and captured onto each lot at issue. PRD 6.2 listed it as a console
-- field, which contradicted every other document; the PRD was corrected in the
-- same change as this migration.
--
-- Rather than leave that as prose, this function refuses a payload carrying
-- any expiry key. A console form that grows the field by accident fails
-- immediately instead of quietly moving a decision away from the person whose
-- money it is. Paid credit cannot expire at all - there is no field for it
-- anywhere (RULES 7).

create or replace function app_admin.set_salon_rules(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_rules          jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
  v_key    text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_rules is null or jsonb_typeof(p_rules) <> 'object' then
    raise exception 'app_admin: rules must be a JSON object';
  end if;

  foreach v_key in array array(select jsonb_object_keys(p_rules)) loop
    if v_key !~ '^(wallet_rule|reward_rule|loyalty_rule|default_reminder_cycle_days|cancellation_policy)$' then
      raise exception
        'app_admin: % is not a rule the console may set. Bonus expiry belongs to '
        'the owner, in the app (RULES 5.3.3), and paid credit never expires.', v_key;
    end if;
  end loop;

  -- Belt and braces: catch an expiry smuggled INSIDE wallet_rule.
  if p_rules::text ~* 'expir' then
    raise exception
      'app_admin: the rules payload mentions expiry. Bonus expiry is the owner''s '
      'setting in the app, and paid credit never expires (RULES 7).';
  end if;

  select jsonb_build_object(
           'wallet_rule', s.wallet_rule,
           'reward_rule', s.reward_rule,
           'loyalty_rule', s.loyalty_rule,
           'default_reminder_cycle_days', s.default_reminder_cycle_days,
           'cancellation_policy', s.cancellation_policy)
    into v_before
    from public.salons s where s.id = p_salon_id;

  if v_before is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  update public.salons
     set wallet_rule  = coalesce(p_rules -> 'wallet_rule', wallet_rule),
         reward_rule  = coalesce(p_rules -> 'reward_rule', reward_rule),
         loyalty_rule = coalesce(p_rules -> 'loyalty_rule', loyalty_rule),
         default_reminder_cycle_days =
           coalesce((p_rules ->> 'default_reminder_cycle_days')::int,
                    default_reminder_cycle_days),
         cancellation_policy =
           coalesce(p_rules ->> 'cancellation_policy', cancellation_policy),
         updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.rules_changed', 'salons', p_salon_id::text,
    null, v_before, p_rules);
end;
$$;

-- 0020: a function added here is PUBLIC-executable until this is called.
select app_admin.close_privileges();
