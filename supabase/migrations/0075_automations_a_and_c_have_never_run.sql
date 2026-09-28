-- 0075 Automations A and C had no caller
--
-- `app.on_visit_completed` and `app.on_booking_confirmed` are M8's Automations
-- A and C. Both are built, both are gated, and **nothing has ever called
-- either**. In production, marking a visit complete schedules no reminder,
-- learns no interval and writes no metric; confirming a booking sends no
-- confirmation and stops no reminder. The entire M8 reminder loop has been
-- reachable only from its own test.
--
-- This is the fourth instance of the same shape in three days - the reminder
-- that was scheduled and never sent (0066), the dispatcher calling functions
-- PostgREST cannot see (0068), the wallet that could not be spent (0069). Each
-- piece correct, each piece gated, the seam between pieces unexamined. The
-- difference this time is that it was found by going looking, with a query over
-- `pg_proc.prosrc` for functions nothing calls, rather than by tripping over it.
--
-- **Idempotency matters here more than anywhere.** `mark_visit_complete` is
-- idempotent through `idempotency_keys`, and the automation is called only on
-- the path that actually created the visit - so a replayed offline
-- mark-complete, which is the normal case on salon wifi, does not count the
-- revenue twice. That ordering is the whole reason this is not a trigger.

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
  v_result  jsonb;
begin
  if v_role not in ('owner', 'manager', 'staff') then
    raise exception 'mark_visit_complete: only the salon may complete a visit'
      using errcode = '42501';
  end if;

  select r.result into v_result
    from public.idempotency_keys r
   where r.salon_id = v_salon and r.key = p_client_action_id;
  if v_result is not null then
    return v_result;
  end if;

  select b.id, b.status, b.customer_id, b.staff_id, b.total_paise
    into v_booking
    from public.bookings b
   where b.id = p_booking_id and b.salon_id = v_salon
   for update;

  if v_booking.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_booking');
  end if;

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

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'visit.completed', v_visit,
          jsonb_build_object('booking_id', p_booking_id,
                             'customer_id', v_booking.customer_id,
                             'final_amount_paise', v_amount));

  -- **Automation A.** Reached only from here, only on the path that created the
  -- visit. It sets last_visit_at itself - the hand-rolled update that used to
  -- live here has gone, because two writers of one column is how they disagree.
  perform app.on_visit_completed(v_visit);

  v_result := jsonb_build_object('ok', true, 'visit_id', v_visit, 'already', false);

  insert into public.idempotency_keys (salon_id, key, operation, result)
  values (v_salon, p_client_action_id, 'mark_visit_complete', v_result);

  return v_result;
end;
$$;

comment on function public.mark_visit_complete is
  'The owner''s one-tap action (RULES 13). Idempotent through idempotency_keys, and Automation A runs ONLY on the path that created the visit - so a replayed offline mark-complete does not count the revenue twice or schedule a second reminder (0075).';

-- ---------------------------------------------------------------------------
-- Automation C, same treatment
-- ---------------------------------------------------------------------------
--
-- 0045's body with one added line. A booking that nobody is told about is a
-- booking the customer turns up to on faith, and the reminder that would have
-- nagged them about the same service is never stopped.

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

  -- **Automation C.** Reached only from here, only on the path that created the
  -- booking, so a replay does not send a second confirmation or count a second
  -- booking in the day's metrics (0075).
  perform app.on_booking_confirmed(v_booking);

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
  'Books a slot. The EXCLUSION CONSTRAINT decides a race, not an application lock. Idempotent through idempotency_keys, and Automation C runs only on the path that created the booking (0075).';
