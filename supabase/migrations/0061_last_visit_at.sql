-- 0061 The column is last_visit_at
--
-- 0059 wrote `last_visit`, and 0060 - rewriting the same body for a different
-- reason - carried the mistake forward without looking. The column has been
-- `last_visit_at` since 0004.
--
-- Two bugs in two migrations, both of them a column name assumed rather than
-- read, both invisible until the gate ran because plpgsql bodies are not
-- validated at CREATE time. The lesson is not "be careful": it is that a
-- function touching a table should be written with that table's definition on
-- screen, and that the gate belongs in the same session as the function.

create or replace function app.on_visit_completed(p_visit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit     record;
  v_service   uuid;
  v_median    numeric;
  v_sample    integer;
  v_cycle     integer;
  v_due       timestamptz;
  v_reminder  uuid;
  v_converted integer := 0;
begin
  select v.id, v.salon_id, v.customer_id, v.booking_id, v.final_amount_paise, v.completed_at
    into v_visit
    from public.visits v
   where v.id = p_visit_id;

  if v_visit.id is null then
    raise exception 'on_visit_completed: no such visit';
  end if;

  -- The service this visit was for. A booking can carry several items; the
  -- reminder follows the first SERVICE, not an add-on.
  select bi.ref_id into v_service
    from public.booking_items bi
   where bi.booking_id = v_visit.booking_id
     and bi.kind = 'service'
   order by bi.created_at
   limit 1;

  update public.customers
     set last_visit_at = v_visit.completed_at,
         updated_at = now()
   where id = v_visit.customer_id
     and (last_visit_at is null or last_visit_at < v_visit.completed_at);

  -- Today's numbers. Written incrementally here and reconciled nightly by
  -- Automation E, which ALERTS on a mismatch rather than healing it (6.8).
  insert into public.daily_salon_metrics (salon_id, day, revenue_paise, completed)
  values (v_visit.salon_id, (v_visit.completed_at at time zone 'UTC')::date,
          coalesce(v_visit.final_amount_paise, 0), 1)
  on conflict (salon_id, day) do update
     set revenue_paise = public.daily_salon_metrics.revenue_paise
                         + coalesce(v_visit.final_amount_paise, 0),
         completed = public.daily_salon_metrics.completed + 1,
         updated_at = now();

  if v_service is null then
    return jsonb_build_object('ok', true, 'reminder_id', null, 'reason', 'no_service');
  end if;

  -- The learned interval (ARCHITECTURE 6.7). A clamped MEDIAN of this
  -- customer's own gaps for this service - deliberately not a model, because a
  -- median is explainable to a salon owner and a model is not.
  with gaps as (
    select extract(epoch from (v.completed_at - lag(v.completed_at)
             over (order by v.completed_at))) / 86400.0 as days
      from public.visits v
      join public.booking_items bi
        on bi.booking_id = v.booking_id and bi.kind = 'service'
     where v.customer_id = v_visit.customer_id
       and bi.ref_id = v_service
       and v.completed_at is not null
  )
  select percentile_cont(0.5) within group (order by days), count(*)::integer
    into v_median, v_sample
    from gaps where days is not null and days > 0;

  select s.default_reminder_cycle_days into v_cycle
    from public.salons s where s.id = v_visit.salon_id;
  v_cycle := coalesce(v_cycle, 30);

  if coalesce(v_sample, 0) >= 1 and v_median is not null then
    insert into public.customer_service_intervals
      (salon_id, customer_id, service_id, median_days, sample_n, updated_at)
    values (v_visit.salon_id, v_visit.customer_id, v_service,
            round(v_median)::integer, v_sample, now())
    on conflict (salon_id, customer_id, service_id) do update
       set median_days = excluded.median_days,
           sample_n = excluded.sample_n,
           updated_at = now();

    -- Clamped to half and double the salon's cycle. An unclamped median turns
    -- one unusual gap into a reminder six months late, or one tomorrow.
    v_due := v_visit.completed_at
             + make_interval(days => greatest(v_cycle / 2,
                                     least(round(v_median)::integer, v_cycle * 2)));
  else
    v_due := v_visit.completed_at + make_interval(days => v_cycle);
  end if;

  -- The customer came in, so any reminder still waiting for this service did its
  -- job or was overtaken. Converting it frees the partial unique index for the
  -- new cycle - which is how a SECOND visit updates the schedule instead of
  -- racing the index and losing.
  update public.reminders
     set status = 'converted'
   where salon_id = v_visit.salon_id
     and customer_id = v_visit.customer_id
     and service_id = v_service
     and status in ('scheduled', 'sent', 'delivered');
  get diagnostics v_converted = row_count;

  -- cycle_key is the VISIT (ARCHITECTURE 6.6). A replayed offline
  -- mark-complete, a retried job and a duplicate event all carry the same visit
  -- and collide here, becoming no-ops with no application coordination.
  insert into public.reminders
    (salon_id, customer_id, service_id, cycle_key, type, scheduled_for, status)
  values
    (v_visit.salon_id, v_visit.customer_id, v_service, p_visit_id::text,
     'service_due', v_due, 'scheduled')
  on conflict do nothing
  returning id into v_reminder;

  return jsonb_build_object(
    'ok', true,
    'reminder_id', v_reminder,
    'scheduled_for', v_due,
    'median_days', case when coalesce(v_sample, 0) >= 1 then round(v_median)::integer end,
    'superseded', v_converted);
end;
$$;

comment on function app.on_visit_completed is
  'Automation A. Last visit, learned interval, exactly ONE reminder per cycle, today''s metrics. Reads booking_items.kind/ref_id and customers.last_visit_at - 0059 assumed a service_id column and a last_visit column, and neither exists (0060, 0061). No loyalty award: points and tiers are Tier 2 (PRD 10.3) and no document specifies the rule.';

create or replace function app.on_booking_confirmed(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking record;
  v_service uuid;
  v_notification uuid;
  v_stopped integer := 0;
begin
  select b.id, b.salon_id, b.customer_id, b.starts_at, b.total_paise
    into v_booking
    from public.bookings b
   where b.id = p_booking_id;

  if v_booking.id is null then
    raise exception 'on_booking_confirmed: no such booking';
  end if;

  select bi.ref_id into v_service
    from public.booking_items bi
   where bi.booking_id = p_booking_id and bi.kind = 'service'
   order by bi.created_at
   limit 1;

  -- They have booked, so the reminder that would have nagged them about this
  -- service has done its job. `converted` is the word the schema already has for
  -- it, and it is what makes the reminder's conversion rate measurable later.
  if v_service is not null then
    update public.reminders
       set status = 'converted', booking_id = p_booking_id
     where salon_id = v_booking.salon_id
       and customer_id = v_booking.customer_id
       and service_id = v_service
       and status in ('scheduled', 'sent', 'delivered');
    get diagnostics v_stopped = row_count;
  end if;

  v_notification := app.notify(
    v_booking.salon_id, v_booking.customer_id,
    'booking_confirmed', 'transactional', 'booking_confirmed',
    jsonb_build_object('starts_at', v_booking.starts_at,
                       'total_paise', v_booking.total_paise,
                       'booking_id', p_booking_id));

  insert into public.daily_salon_metrics (salon_id, day, bookings)
  values (v_booking.salon_id, (v_booking.starts_at at time zone 'UTC')::date, 1)
  on conflict (salon_id, day) do update
     set bookings = public.daily_salon_metrics.bookings + 1,
         updated_at = now();

  return jsonb_build_object('ok', true, 'notification_id', v_notification,
                            'reminders_converted', v_stopped);
end;
$$;

comment on function app.on_booking_confirmed is
  'Automation C. Confirms, and stops the reminder that would otherwise nag a customer who has already booked - marked `converted`, which is also what makes reminder conversion measurable. Reads booking_items.kind/ref_id (0060).';
