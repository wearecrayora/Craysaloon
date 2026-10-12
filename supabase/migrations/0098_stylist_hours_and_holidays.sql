-- 0098 Stylist hours and salon holidays - so there are times to book at all.
--
-- available_slots offers a time only inside a stylist's weekly schedule
-- (staff_schedules) and outside their time off (staff_time_off). Found on
-- 12 Oct 2026, both while building the owner's Hours screen:
--
--   1. NOTHING WROTE staff_schedules. No app screen, no console page, no
--      function: the table was empty on the hosted project, so every salon
--      offered no free times, and the customer's booking flow could only ever
--      say "No free times on this day". The salon-level working_hours column
--      was the decoy - written once at provisioning, read by nothing.
--   2. A SALON HOLIDAY NEVER BLOCKED A BOOKING. staff_time_off with
--      staff_id null means "the whole salon closed" (0007), but
--      available_slots only matched time off for the stylist in question.
--
-- So: the owner or a manager sets each stylist's week and adds time off - for
-- one stylist, or for the whole salon - through three functions, and the slot
-- query honours a salon-wide closure.

-- ---------------------------------------------------------------------------
-- A stylist's week
-- ---------------------------------------------------------------------------

-- p_week: [{"day": 0-6 (0 = Sunday), "starts": "10:00", "ends": "20:00"}, ...]
-- Replaces the stylist's whole week in one transaction - so a half-saved week
-- never offers times nobody meant. More than one shift a day is allowed (a
-- lunch break is two shifts); overlapping shifts are refused.
create or replace function public.set_staff_week(p_staff_id uuid, p_week jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_role  text := app.current_app_role();
  v_shift jsonb;
  v_n     integer := 0;
begin
  if v_salon is null or v_role not in ('owner', 'manager') then
    raise exception 'set_staff_week: owners and managers set working hours'
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.staff s where s.id = p_staff_id and s.salon_id = v_salon) then
    raise exception 'set_staff_week: no such stylist here' using errcode = '42501';
  end if;
  if p_week is null or jsonb_typeof(p_week) <> 'array' then
    raise exception 'set_staff_week: the week must be a list of shifts' using errcode = '22023';
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  delete from public.staff_schedules where salon_id = v_salon and staff_id = p_staff_id;

  for v_shift in select * from jsonb_array_elements(p_week) loop
    if (v_shift ->> 'day') is null or (v_shift ->> 'day')::int not between 0 and 6
       or (v_shift ->> 'ends')::time <= (v_shift ->> 'starts')::time then
      raise exception 'set_staff_week: % is not a day 0-6 with an end after its start', v_shift
        using errcode = '22023';
    end if;
    if exists (
      select 1 from public.staff_schedules s
       where s.salon_id = v_salon and s.staff_id = p_staff_id
         and s.day_of_week = (v_shift ->> 'day')::smallint
         and s.starts_at < (v_shift ->> 'ends')::time
         and (v_shift ->> 'starts')::time < s.ends_at) then
      raise exception 'set_staff_week: shifts on day % overlap', v_shift ->> 'day'
        using errcode = '22023';
    end if;
    insert into public.staff_schedules (salon_id, staff_id, day_of_week, starts_at, ends_at)
    values (v_salon, p_staff_id, (v_shift ->> 'day')::smallint,
            (v_shift ->> 'starts')::time, (v_shift ->> 'ends')::time);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'shifts', v_n);
end;
$$;

-- ---------------------------------------------------------------------------
-- Time off: one stylist, or the whole salon (staff_id null)
-- ---------------------------------------------------------------------------

create or replace function public.add_time_off(
  p_staff_id uuid,
  p_starts   timestamptz,
  p_ends     timestamptz,
  p_reason   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_role  text := app.current_app_role();
  v_id    uuid;
begin
  if v_salon is null or v_role not in ('owner', 'manager') then
    raise exception 'add_time_off: owners and managers set time off' using errcode = '42501';
  end if;
  if p_staff_id is not null
     and not exists (select 1 from public.staff s where s.id = p_staff_id and s.salon_id = v_salon) then
    raise exception 'add_time_off: no such stylist here' using errcode = '42501';
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'add_time_off: the end must come after the start' using errcode = '22023';
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  insert into public.staff_time_off (salon_id, staff_id, starts_at, ends_at, reason)
  values (v_salon, p_staff_id, p_starts, p_ends, nullif(btrim(coalesce(p_reason, '')), ''))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.remove_time_off(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_role  text := app.current_app_role();
begin
  if v_salon is null or v_role not in ('owner', 'manager') then
    raise exception 'remove_time_off: owners and managers set time off' using errcode = '42501';
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;
  delete from public.staff_time_off where id = p_id and salon_id = v_salon;
  return jsonb_build_object('ok', true, 'removed', found);
end;
$$;

revoke all on function public.set_staff_week(uuid, jsonb) from public, anon;
revoke all on function public.add_time_off(uuid, timestamptz, timestamptz, text) from public, anon;
revoke all on function public.remove_time_off(uuid) from public, anon;
grant execute on function public.set_staff_week(uuid, jsonb) to authenticated;
grant execute on function public.add_time_off(uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.remove_time_off(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- A salon holiday closes the salon
-- ---------------------------------------------------------------------------

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'available_slots';
  v_new := replace(v_def,
    'where t.salon_id = v_salon and t.staff_id = c.staff_id',
    'where t.salon_id = v_salon and (t.staff_id = c.staff_id or t.staff_id is null)');
  if v_new = v_def then
    raise exception '0098: available_slots did not contain the time-off match it patches';
  end if;
  execute v_new;
end;
$patch$;
