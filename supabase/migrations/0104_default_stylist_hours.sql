-- 0104 A new stylist works 10:00 to 17:00, every day, until the owner says otherwise.
--
-- Decided 13 Oct 2026. Before this a stylist was added with NO hours, and a
-- stylist with no hours has no bookable time - so a salon that had just added
-- its team still could not take a single booking until the owner found Team ->
-- the clock icon (0098). Now every stylist starts bookable on a sensible week
-- and the owner narrows it: lunch breaks, days off, holidays.
--
-- A trigger, because a stylist is created two ways - by Crayora in the console
-- (app_admin.upsert_staff) and by the owner in the app, which inserts the row
-- directly under its write policy - and a default that only one of them applied
-- would be a default half the salons never got. Times are the salon's own
-- local time, as every staff_schedules row is (0007, available_slots).
--
-- Only when the stylist has no week yet: anything already set is the owner's.

create or replace function app.default_staff_week()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.staff_schedules s where s.staff_id = new.id) then
    insert into public.staff_schedules (salon_id, staff_id, day_of_week, starts_at, ends_at)
    select new.salon_id, new.id, d::smallint, time '10:00', time '17:00'
      from generate_series(0, 6) d;
  end if;
  return new;
end;
$$;

comment on function app.default_staff_week() is
  'Every new stylist starts on 10:00-17:00, every day, salon local time - bookable from the moment they are added. The owner changes it in Team (0104).';

revoke all on function app.default_staff_week() from public, anon, authenticated;

drop trigger if exists staff_default_week on public.staff;
create trigger staff_default_week
  after insert on public.staff
  for each row execute function app.default_staff_week();

-- Stylists who already exist with no week at all get the same default.
insert into public.staff_schedules (salon_id, staff_id, day_of_week, starts_at, ends_at)
select st.salon_id, st.id, d::smallint, time '10:00', time '17:00'
  from public.staff st
 cross join generate_series(0, 6) d
 where not exists (select 1 from public.staff_schedules s where s.staff_id = st.id);
