-- 0046 available_slots reads the weekday the schedule was written in
--
-- 0045 matched `staff_schedules.day_of_week` with `extract(isodow from date)`,
-- which numbers Monday 1 through Sunday 7. The column is constrained to 0-6,
-- which is Postgres's `dow`: **Sunday 0** through Saturday 6.
--
-- So the function asked for the wrong day, every day. Monday's grid would have
-- come from Tuesday's rota, and Sunday - isodow 7, outside the constraint - could
-- never match anything at all, quietly showing a salon that opens on Sunday as
-- closed. Caught by the check constraint when the gate's fixture tried to write
-- a rota the way the function read it, which is the useful direction for a
-- mismatch to be found in.
--
-- Only the extract changes. Everything else is 0045's definition.

create or replace function app.available_slots(
  p_salon_id     uuid,
  p_service_id   uuid,
  p_staff_id     uuid default null,
  p_date         date default null,
  p_add_on_ids   uuid[] default '{}',
  p_step_minutes integer default 15
)
returns table (staff_id uuid, starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_tz       text;
  v_date     date;
  v_minutes  integer;
  v_step     integer := least(greatest(coalesce(p_step_minutes, 15), 5), 60);
begin
  if v_salon is null or (p_salon_id is not null and p_salon_id <> v_salon) then
    raise exception 'available_slots: not your salon' using errcode = '42501';
  end if;

  select s.timezone into v_tz from public.salons s where s.id = v_salon;
  v_tz := coalesce(v_tz, 'Asia/Kolkata');
  v_date := coalesce(p_date, (now() at time zone v_tz)::date);

  select sv.duration_minutes
       + coalesce((select sum(a.extra_duration_minutes)
                     from public.add_ons a
                    where a.salon_id = v_salon
                      and a.id = any(coalesce(p_add_on_ids, '{}'::uuid[]))), 0)
    into v_minutes
    from public.services sv
   where sv.id = p_service_id and sv.salon_id = v_salon and sv.active;

  if v_minutes is null then
    return;
  end if;

  return query
  with working as (
    select sch.staff_id,
           ((v_date + sch.starts_at) at time zone v_tz) as day_start,
           ((v_date + sch.ends_at)   at time zone v_tz) as day_end
      from public.staff_schedules sch
      join public.staff st on st.id = sch.staff_id and st.active
     where sch.salon_id = v_salon
       and st.salon_id = v_salon
       -- dow, not isodow: the column is 0-6 with Sunday at 0 (0046).
       and sch.day_of_week = extract(dow from v_date)::smallint
       and (p_staff_id is null or sch.staff_id = p_staff_id)
  ),
  candidate as (
    select w.staff_id,
           gs as starts_at,
           gs + make_interval(mins => v_minutes) as ends_at
      from working w
      cross join lateral generate_series(
        w.day_start,
        w.day_end - make_interval(mins => v_minutes),
        make_interval(mins => v_step)
      ) as gs
  )
  select c.staff_id, c.starts_at, c.ends_at
    from candidate c
   where c.starts_at > now()
     and not exists (
       select 1 from public.staff_time_off t
        where t.salon_id = v_salon and t.staff_id = c.staff_id
          and tstzrange(t.starts_at, t.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)')
     )
     and not exists (
       select 1 from public.bookings b
        where b.salon_id = v_salon and b.staff_id = c.staff_id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)')
     )
   order by c.staff_id, c.starts_at;
end;
$$;

comment on function app.available_slots is
  'The ONE definition of availability (ARCHITECTURE 6.5): staff schedule - time off - existing bookings, in the salon''s own timezone, for the service plus the add-ons chosen. Weekdays are `dow` (Sunday 0), matching staff_schedules.day_of_week (0046).';
