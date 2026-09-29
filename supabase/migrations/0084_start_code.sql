-- 0084 The start code: the customer proves they are in the chair
--
-- Requested 29 Sep 2026. Before a service starts, the customer reads a 4-digit
-- code from their app and the stylist types it in. Decisions taken the same day:
--
--   * **Required when possible.** Whenever the customer has the app and the
--     stylist is online, the code is how a service starts. When it cannot be -
--     no app, a phone offline, a code locked by wrong guesses - the stylist
--     starts WITHOUT it, and the booking records that and why. Nobody is turned
--     away, and the owner sees every exception on the dashboard (0086).
--   * The code is shown in the CUSTOMER's app, never sent by SMS: it is free,
--     and Message Central's OTP is reserved for login (RULES 16, ADR-36).
--
-- The property the whole feature rests on: **staff can never read the code.**
-- If they could, typing it would prove nothing. So the codes live in a table
-- with RLS forced and NO policies - like customer_identities - and only two
-- definer functions touch it: one shows the customer their own code, the other
-- checks what the stylist typed. The leak test lists it among the tables that
-- must have exactly zero policies, so a future "helpful" policy fails CI.
--
-- The new `in_progress` status (0083) also had to be taught to the two places
-- that decide whether a chair is free. The double-booking constraint and the
-- slot finder both covered `pending` and `confirmed` only - so without this, a
-- chair would have been BOOKABLE WHILE SOMEONE WAS SITTING IN IT.

-- ---------------------------------------------------------------------------
-- 1. An occupied chair is not free
-- ---------------------------------------------------------------------------

alter table public.bookings drop constraint bookings_no_staff_overlap;

alter table public.bookings add constraint bookings_no_staff_overlap
  exclude using gist (
    salon_id with =,
    staff_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  )
  where (status in ('pending', 'confirmed', 'in_progress'));

-- The slot finder, rewritten from its LIVE definition: one fragment swapped,
-- and the migration refuses if the fragment is not exactly where expected.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'available_slots';

  v_new := replace(v_def,
    $x$b.status in ('pending', 'confirmed')$x$,
    $x$b.status in ('pending', 'confirmed', 'in_progress')$x$);

  if v_new = v_def then
    raise exception '0084: the slot finder''s status filter was not where expected';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. How a service started
-- ---------------------------------------------------------------------------

alter table public.bookings
  add column started_at   timestamptz,
  add column start_method text check (start_method in ('code', 'without_code')),
  -- Why it started without the code. Shown to the owner (0086).
  add column start_note   text check (start_note in (
    'customer_has_no_app', 'no_code_given', 'code_locked', 'completed_without_start'));

comment on column public.bookings.start_method is
  '"code": the customer read their start code to the stylist. "without_code": it could not be used, and start_note says why. Every exception is visible to the owner (0084, 0086).';

-- ---------------------------------------------------------------------------
-- 3. The codes themselves - readable by NO tenant role
-- ---------------------------------------------------------------------------

create table public.booking_start_codes (
  salon_id   uuid not null references public.salons(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  code       text not null check (code ~ '^[0-9]{4}$'),
  -- Five wrong guesses and it locks: 10,000 codes, 5 tries, a 1-in-2,000
  -- chance of guessing - for a code that only proves someone is in the chair.
  attempts   integer not null default 0,
  locked_at  timestamptz,
  created_at timestamptz not null default now(),
  primary key (salon_id, booking_id)
);

alter table public.booking_start_codes enable row level security;
alter table public.booking_start_codes force row level security;
-- No policies, on purpose, and no grants: only the two definer functions below.
revoke all on public.booking_start_codes from public, anon, authenticated;

comment on table public.booking_start_codes is
  'One code per booking. RLS forced with NO policies: staff must never be able to read a code, or typing it proves nothing. Only my_visits_today (the customer''s own) and start_service (the check) touch it.';

create or replace function app.booking_start_code(p_salon_id uuid, p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  select c.code into v_code
    from public.booking_start_codes c
   where c.salon_id = p_salon_id and c.booking_id = p_booking_id;

  if v_code is null then
    -- From the CSPRNG, not random(): a guessable sequence would let someone
    -- predict tomorrow's codes from today's.
    v_code := lpad(((('x' || encode(extensions.gen_random_bytes(2), 'hex'))::bit(16)::int)
                    % 10000)::text, 4, '0');
    insert into public.booking_start_codes (salon_id, booking_id, code)
    values (p_salon_id, p_booking_id, v_code)
    on conflict (salon_id, booking_id) do nothing;

    select c.code into v_code
      from public.booking_start_codes c
     where c.salon_id = p_salon_id and c.booking_id = p_booking_id;
  end if;

  return v_code;
end;
$$;

revoke all on function app.booking_start_code(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. The customer's view of today
-- ---------------------------------------------------------------------------

create or replace function public.my_visits_today()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
begin
  if v_salon is null or v_customer is null then
    raise exception 'my_visits_today: no customer in this session' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'booking_id', b.id,
             'starts_at', b.starts_at,
             'status', b.status,
             'services', (select string_agg(bi.name_snapshot, ', ' order by bi.created_at)
                            from public.booking_items bi
                           where bi.booking_id = b.id and bi.kind = 'service'),
             'staff', (select s.name from public.staff s where s.id = b.staff_id),
             -- The code only while it can still be used. Once the service has
             -- started it has done its job.
             'start_code', case when b.status in ('pending', 'confirmed')
                                then app.booking_start_code(v_salon, b.id) end)
           order by b.starts_at)
      from public.bookings b
     where b.salon_id = v_salon
       and b.customer_id = v_customer
       and b.status in ('pending', 'confirmed', 'in_progress')
       and app.salon_day(v_salon, b.starts_at) = app.salon_day(v_salon, now())
  ), '[]'::jsonb);
end;
$$;

comment on function public.my_visits_today is
  'The customer''s bookings for today, each with its START CODE while it can still be used. The only way anyone reads a code - and only the booking''s own customer.';

revoke all on function public.my_visits_today() from public, anon;
grant execute on function public.my_visits_today() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Starting a service
-- ---------------------------------------------------------------------------

create or replace function public.start_service(
  p_client_action_id uuid,
  p_booking_id       uuid,
  p_code             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   uuid := app.current_salon_id();
  v_booking record;
  v_code    record;
  v_method  text;
  v_note    text;
  v_result  jsonb;
begin
  if app.current_app_role() not in ('owner', 'manager', 'staff') then
    raise exception 'start_service: only the salon starts a service' using errcode = '42501';
  end if;

  -- Replays are no-ops, like every write that can be queued offline (RULES 9).
  select k.result into v_result
    from public.idempotency_keys k
   where k.salon_id = v_salon and k.key = p_client_action_id;
  if v_result is not null then
    return v_result;
  end if;

  select b.id, b.status, b.customer_id,
         (select c.auth_user_id is not null from public.customers c
           where c.id = b.customer_id) as has_app
    into v_booking
    from public.bookings b
   where b.id = p_booking_id and b.salon_id = v_salon
   for update;

  if v_booking.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_booking');
  end if;
  if v_booking.status = 'in_progress' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if v_booking.status not in ('pending', 'confirmed') then
    return jsonb_build_object('ok', false, 'reason', 'not_startable');
  end if;

  select c.code, c.attempts, c.locked_at
    into v_code
    from public.booking_start_codes c
   where c.salon_id = v_salon and c.booking_id = p_booking_id
   for update;

  if p_code is not null then
    if v_code.code is null then
      -- The customer has not opened the booking in their app, so no code was
      -- ever issued. Nothing typed can match; start without it instead.
      v_result := jsonb_build_object('ok', false, 'reason', 'no_code_issued');
    elsif v_code.locked_at is not null then
      v_result := jsonb_build_object('ok', false, 'reason', 'code_locked');
    elsif btrim(p_code) <> v_code.code then
      update public.booking_start_codes
         set attempts = attempts + 1,
             locked_at = case when attempts + 1 >= 5 then now() end
       where salon_id = v_salon and booking_id = p_booking_id;
      v_result := jsonb_build_object(
        'ok', false,
        'reason', case when v_code.attempts + 1 >= 5 then 'code_locked' else 'wrong_code' end,
        'attempts_left', greatest(5 - (v_code.attempts + 1), 0));
    else
      v_method := 'code';
    end if;

    if v_method is null then
      -- A refusal is recorded against the action id too, so a replayed wrong
      -- attempt cannot spend a second guess.
      insert into public.idempotency_keys (salon_id, key, operation, result)
      values (v_salon, p_client_action_id, 'start_service', v_result);
      return v_result;
    end if;
  else
    -- Without the code. Allowed, never silent: the reason is recorded, and the
    -- owner sees it (0086).
    v_method := 'without_code';
    v_note := case
      when v_booking.customer_id is null or not coalesce(v_booking.has_app, false)
        then 'customer_has_no_app'
      when v_code.locked_at is not null then 'code_locked'
      else 'no_code_given'
    end;
  end if;

  update public.bookings
     set status = 'in_progress',
         started_at = now(),
         start_method = v_method,
         start_note = v_note,
         updated_at = now()
   where id = p_booking_id;

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'booking.started', p_booking_id,
          jsonb_build_object('method', v_method, 'note', v_note));

  v_result := jsonb_build_object('ok', true, 'already', false,
                                 'method', v_method, 'note', v_note);

  insert into public.idempotency_keys (salon_id, key, operation, result)
  values (v_salon, p_client_action_id, 'start_service', v_result);

  return v_result;
end;
$$;

comment on function public.start_service is
  'Moves a booking to in_progress. With the customer''s code (verified here; five wrong guesses lock it) or without it - allowed, never silent: start_note records why, and the owner sees every exception. Idempotent on the action id, including refusals, so a replayed wrong guess cannot spend a second attempt.';

revoke all on function public.start_service(uuid, uuid, text) from public, anon;
grant execute on function public.start_service(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Completing a booking that was never started still records how it began
-- ---------------------------------------------------------------------------
--
-- Mark-complete stays one tap and still accepts a confirmed booking (RULES 13).
-- But a completion that skipped the start is, by definition, a start without
-- the code - so it is recorded as one, and the owner's count stays honest.

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mark_visit_complete';

  v_new := replace(v_def,
    $x$     set status = 'completed', updated_at = now()$x$,
    $x$     set status = 'completed', updated_at = now(),
         -- A completion that skipped the start began WITHOUT the code (0084).
         started_at = coalesce(started_at, now()),
         start_method = coalesce(start_method, 'without_code'),
         start_note = case when start_method is null
                           then 'completed_without_start' else start_note end$x$);

  if v_new = v_def then
    raise exception '0084: mark_visit_complete''s status update was not where expected';
  end if;
  execute v_new;
end;
$$;
