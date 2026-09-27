-- 0045 Booking, slots and mark-complete (M6)
--
-- Three functions, and the guarantees each one carries.
--
-- app.available_slots  - ONE definition of availability, called by the customer
--                        app, the owner app and the server. The slot grid a
--                        customer sees is the grid the exclusion constraint will
--                        accept, because both come from here (ARCHITECTURE 6.5).
-- create_booking       - price and duration SNAPSHOTTED onto booking_items, so
--                        repricing a service never rewrites what a past booking
--                        cost. Idempotent on client_action_id (RULES 9.3), and a
--                        race is decided by the database, not by a check.
-- mark_visit_complete  - the single most important write in the product. An
--                        idempotent state transition (RULES 9.4): replays and
--                        out-of-order arrivals are no-ops, which is what makes
--                        the offline queue safe to drain more than once.
--
-- All three are SECURITY DEFINER, for a reason that is not convenience: visits
-- and booking_items are closed to every device (0042), and availability has to
-- read staff schedules, which customers cannot see (0041). So each one re-checks
-- the caller instead of inheriting RLS - salon from the token, role from the
-- token, and the CUSTOMER from the database via app.current_customer_id(), which
-- a forged claim cannot move.

-- ---------------------------------------------------------------------------
-- 1. Availability
-- ---------------------------------------------------------------------------
--
-- staff schedule  -  time off  -  existing bookings, at the salon's own local
-- time. Salon holidays are not modelled yet (there is no table); when they are,
-- they are subtracted here and everywhere gets them at once, which is the point
-- of having one definition.

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
  -- The caller's salon decides, never the argument. The argument stays in the
  -- signature because IMPLEMENTATION names it, and a mismatch is a bug worth
  -- shouting about rather than quietly ignoring.
  if v_salon is null or (p_salon_id is not null and p_salon_id <> v_salon) then
    raise exception 'available_slots: not your salon' using errcode = '42501';
  end if;

  select s.timezone into v_tz from public.salons s where s.id = v_salon;
  v_tz := coalesce(v_tz, 'Asia/Kolkata');
  v_date := coalesce(p_date, (now() at time zone v_tz)::date);

  -- Duration is the service plus every add-on the customer actually chose, so
  -- the grid matches the booking that will be attempted (ARCHITECTURE 6.5).
  select sv.duration_minutes
       + coalesce((select sum(a.extra_duration_minutes)
                     from public.add_ons a
                    where a.salon_id = v_salon
                      and a.id = any(coalesce(p_add_on_ids, '{}'::uuid[]))), 0)
    into v_minutes
    from public.services sv
   where sv.id = p_service_id and sv.salon_id = v_salon and sv.active;

  if v_minutes is null then
    return;  -- no such service here: no slots, and nothing said about why
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
       and sch.day_of_week = extract(isodow from v_date)::smallint
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
   where c.ends_at <= (select w.day_end from working w where w.staff_id = c.staff_id limit 1)
     -- A slot that has already started cannot be booked.
     and c.starts_at > now()
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
  'The ONE definition of availability (ARCHITECTURE 6.5): staff schedule - time off - existing bookings, in the salon''s own timezone, for the duration of the service plus the add-ons chosen. SECURITY DEFINER because customers cannot read staff schedules (0041) but must see when they can come in.';

create or replace function public.available_slots(
  p_salon_id     uuid,
  p_service_id   uuid,
  p_staff_id     uuid default null,
  p_date         date default null,
  p_add_on_ids   uuid[] default '{}',
  p_step_minutes integer default 15
)
returns table (staff_id uuid, starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select * from app.available_slots(
    p_salon_id, p_service_id, p_staff_id, p_date, p_add_on_ids, p_step_minutes)
$$;

revoke all on function public.available_slots(uuid, uuid, uuid, date, uuid[], integer)
  from public, anon;
grant execute on function public.available_slots(uuid, uuid, uuid, date, uuid[], integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Booking
-- ---------------------------------------------------------------------------

create or replace function public.create_booking(
  p_client_action_id uuid,
  p_service_id       uuid,
  p_starts_at        timestamptz,
  p_staff_id         uuid default null,
  p_customer_id      uuid default null,
  p_add_on_ids       uuid[] default '{}',
  p_source           text default 'app',
  p_notes            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_role     text := app.current_app_role();
  v_customer uuid;
  v_service  record;
  v_minutes  integer;
  v_total    bigint;
  v_booking  uuid;
  v_prior    jsonb;
  v_result   jsonb;
  v_add_on   record;
begin
  if v_salon is null then
    raise exception 'create_booking: no salon in session' using errcode = '42501';
  end if;
  if p_client_action_id is null then
    raise exception 'create_booking: a client_action_id is required (RULES 9.3)';
  end if;

  -- A replay returns the ORIGINAL result rather than a second booking. This is
  -- what makes the offline queue safe to drain twice (RULES 9.3).
  select k.result into v_prior
    from public.idempotency_keys k
   where k.salon_id = v_salon and k.key = p_client_action_id;
  if v_prior is not null then
    return v_prior;
  end if;

  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  -- WHO this booking is for. A customer books for themselves and cannot name
  -- anyone else; the id comes from the database, not from the request.
  if v_role = 'customer' then
    v_customer := app.current_customer_id();
    if p_customer_id is not null and p_customer_id <> v_customer then
      raise exception 'create_booking: a customer can only book for themselves'
        using errcode = '42501';
    end if;
  elsif v_role in ('owner', 'manager', 'staff') then
    v_customer := p_customer_id;
    if v_customer is null then
      raise exception 'create_booking: which customer is this for?';
    end if;
    if not exists (select 1 from public.customers c
                    where c.id = v_customer and c.salon_id = v_salon
                      and c.deleted_at is null) then
      raise exception 'create_booking: no such customer at this salon' using errcode = '42501';
    end if;
  else
    raise exception 'create_booking: this account cannot book' using errcode = '42501';
  end if;

  select sv.id, sv.name, sv.price_paise, sv.duration_minutes
    into v_service
    from public.services sv
   where sv.id = p_service_id and sv.salon_id = v_salon and sv.active;
  if v_service.id is null then
    raise exception 'create_booking: no such service at this salon' using errcode = '42501';
  end if;

  if p_staff_id is not null and not exists (
    select 1 from public.staff st
     where st.id = p_staff_id and st.salon_id = v_salon and st.active
  ) then
    raise exception 'create_booking: no such team member at this salon' using errcode = '42501';
  end if;

  v_minutes := v_service.duration_minutes;
  v_total := v_service.price_paise;

  insert into public.bookings
    (salon_id, customer_id, staff_id, starts_at, ends_at, status, source,
     total_paise, notes, client_action_id)
  values
    (v_salon, v_customer, p_staff_id, p_starts_at,
     p_starts_at + make_interval(mins => v_minutes),
     'confirmed',
     case when v_role = 'customer' then coalesce(nullif(p_source, ''), 'app')::public.booking_source
          else coalesce(nullif(p_source, ''), 'walk_in')::public.booking_source end,
     0, nullif(btrim(coalesce(p_notes, '')), ''), p_client_action_id)
  returning id into v_booking;

  -- The service, as it is priced TODAY. booking_items exists so that repricing
  -- tomorrow does not rewrite what this cost (ARCHITECTURE 6.2).
  insert into public.booking_items
    (salon_id, booking_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
  values
    (v_salon, v_booking, 'service', v_service.id, v_service.name,
     v_service.price_paise, v_service.duration_minutes);

  -- Add-ons, each one checked against the service it is offered with. An add-on
  -- that is not on this service's list is not a typo to tolerate.
  for v_add_on in
    select a.id, a.name, a.price_paise, a.extra_duration_minutes
      from public.add_ons a
      join public.service_addons sa
        on sa.add_on_id = a.id and sa.service_id = v_service.id and sa.salon_id = v_salon
     where a.salon_id = v_salon and a.active
       and a.id = any(coalesce(p_add_on_ids, '{}'::uuid[]))
  loop
    insert into public.booking_items
      (salon_id, booking_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
    values
      (v_salon, v_booking, 'add_on', v_add_on.id, v_add_on.name,
       v_add_on.price_paise, v_add_on.extra_duration_minutes);

    v_minutes := v_minutes + v_add_on.extra_duration_minutes;
    v_total := v_total + v_add_on.price_paise;
  end loop;

  if (select count(*) from public.booking_items bi
       where bi.booking_id = v_booking and bi.kind = 'add_on')
     <> coalesce(array_length(p_add_on_ids, 1), 0) then
    raise exception 'create_booking: an add-on is not offered with this service'
      using errcode = '42501';
  end if;

  update public.bookings
     set ends_at = starts_at + make_interval(mins => v_minutes),
         total_paise = v_total,
         updated_at = now()
   where id = v_booking;

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'booking.created', v_booking,
          jsonb_build_object('customer_id', v_customer, 'staff_id', p_staff_id));

  v_result := jsonb_build_object(
    'ok', true, 'booking_id', v_booking, 'total_paise', v_total, 'minutes', v_minutes);

  insert into public.idempotency_keys (salon_id, key, operation, result)
  values (v_salon, p_client_action_id, 'create_booking', v_result);

  return v_result;

exception
  -- The exclusion constraint decided, which is the whole point: two phones can
  -- race for the same chair and exactly one wins, with no application lock.
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'reason', 'slot_taken');
  when unique_violation then
    -- A replay that arrived while the first was still in flight.
    select k.result into v_prior
      from public.idempotency_keys k
     where k.salon_id = v_salon and k.key = p_client_action_id;
    return coalesce(v_prior, jsonb_build_object('ok', false, 'reason', 'slot_taken'));
end;
$$;

comment on function public.create_booking is
  'Books, with price and duration SNAPSHOTTED onto booking_items. Idempotent on client_action_id (RULES 9.3); a race is decided by the exclusion constraint, never by a check-then-insert. A customer can only ever book for themselves, resolved from the database.';

revoke all on function public.create_booking(uuid, uuid, timestamptz, uuid, uuid, uuid[], text, text)
  from public, anon;
grant execute on function public.create_booking(uuid, uuid, timestamptz, uuid, uuid, uuid[], text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Mark complete
-- ---------------------------------------------------------------------------
--
-- RULES 9.4: an idempotent state transition. The offline queue may deliver this
-- twice, out of order, days later; each of those is a no-op after the first.
-- RULES 9.5: an offline completion records INTENT - the wallet debit, the
-- loyalty award and the package decrement run server-side when they exist (M7),
-- and this function is where they will be added, inside this transaction.

create or replace function public.mark_visit_complete(
  p_client_action_id   uuid,
  p_booking_id         uuid,
  p_final_amount_paise bigint default null,
  p_tip_paise          bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   uuid := app.current_salon_id();
  v_role    text := app.current_app_role();
  v_booking record;
  v_visit   uuid;
  v_amount  bigint;
  v_prior   jsonb;
  v_result  jsonb;
begin
  if v_salon is null then
    raise exception 'mark_visit_complete: no salon in session' using errcode = '42501';
  end if;
  if v_role not in ('owner', 'manager', 'staff') then
    -- A customer completing their own visit would be writing the record that
    -- loyalty, reminders and the dashboard are computed from (0042).
    raise exception 'mark_visit_complete: only the salon can complete a visit'
      using errcode = '42501';
  end if;
  if p_client_action_id is null then
    raise exception 'mark_visit_complete: a client_action_id is required (RULES 9.3)';
  end if;

  select k.result into v_prior
    from public.idempotency_keys k
   where k.salon_id = v_salon and k.key = p_client_action_id;
  if v_prior is not null then
    return v_prior;
  end if;

  select b.id, b.customer_id, b.staff_id, b.status, b.total_paise
    into v_booking
    from public.bookings b
   where b.id = p_booking_id and b.salon_id = v_salon
   for update;

  if v_booking.id is null then
    raise exception 'mark_visit_complete: no such booking here' using errcode = '42501';
  end if;

  -- Already completed: return the visit that exists. Not an error - it is the
  -- same instruction arriving twice, which offline guarantees will happen.
  if v_booking.status = 'completed' then
    select v.id into v_visit from public.visits v where v.booking_id = p_booking_id;
    return jsonb_build_object('ok', true, 'visit_id', v_visit, 'already', true);
  end if;

  if v_booking.status in ('cancelled', 'no_show') then
    return jsonb_build_object('ok', false, 'reason', 'not_completable');
  end if;

  v_amount := coalesce(p_final_amount_paise, v_booking.total_paise);
  if v_amount < 0 or coalesce(p_tip_paise, 0) < 0 then
    raise exception 'mark_visit_complete: an amount cannot be negative';
  end if;

  update public.bookings
     set status = 'completed', updated_at = now()
   where id = p_booking_id;

  insert into public.visits
    (salon_id, booking_id, customer_id, staff_id, final_amount_paise, tip_paise,
     completed_at, client_action_id)
  values
    (v_salon, p_booking_id, v_booking.customer_id, v_booking.staff_id, v_amount,
     coalesce(p_tip_paise, 0), now(), p_client_action_id)
  returning id into v_visit;

  -- What the owner's list is sorted by, and what "not visited yet" means.
  update public.customers
     set last_visit_at = now(), updated_at = now()
   where id = v_booking.customer_id;

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'visit.completed', v_visit,
          jsonb_build_object('booking_id', p_booking_id,
                             'customer_id', v_booking.customer_id,
                             'final_amount_paise', v_amount));

  v_result := jsonb_build_object('ok', true, 'visit_id', v_visit, 'already', false);

  insert into public.idempotency_keys (salon_id, key, operation, result)
  values (v_salon, p_client_action_id, 'mark_visit_complete', v_result);

  return v_result;
end;
$$;

comment on function public.mark_visit_complete is
  'The most important write in the product (RULES 9.4). An idempotent transition confirmed -> completed: a replay returns the first result and writes nothing. Only the salon may call it - a customer completing their own visit would be writing their own history (0042).';

revoke all on function public.mark_visit_complete(uuid, uuid, bigint, bigint) from public, anon;
grant execute on function public.mark_visit_complete(uuid, uuid, bigint, bigint) to authenticated;
