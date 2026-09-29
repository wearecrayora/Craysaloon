-- 0076 "Today" is the salon's today, not Greenwich's
--
-- Every metrics writer bucketed its row by `(... at time zone 'UTC')::date`.
-- The salon is Asia/Kolkata. A visit completed at 00:30 IST is 19:00 UTC the
-- day before, so everything between midnight and 05:30 IST was counted on
-- YESTERDAY's card - "today's revenue" wrong for five and a half hours of every
-- day, and the day-close totals an owner checks against the till wrong on
-- every late night.
--
-- It matters more now than it did: M10's reconciliation recomputes each day
-- from source and ALERTS on a mismatch (PRD 9.5). A reconciler that buckets by
-- the salon's timezone against writers that bucket by UTC would have alerted on
-- phantom drift forever, and an alert that is always firing is an alert nobody
-- reads.
--
-- So there is ONE definition of a salon's day, `app.salon_day`, and every writer
-- and the reconciler call it. The same lesson as `app.wallet_bonus_for` (0058):
-- two copies of a rule is how the copies come to disagree.
--
-- The three writer bodies below are the LIVE definitions (pg_get_functiondef),
-- each with its one UTC expression swapped - generated, not retyped, because
-- retyping a function from memory is how 0054 dropped a line nobody noticed.

create or replace function app.salon_day(p_salon_id uuid, p_at timestamptz)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone coalesce(
            (select s.timezone from public.salons s where s.id = p_salon_id),
            'Asia/Kolkata'))::date
$$;

comment on function app.salon_day is
  'THE definition of which day something happened on, for a salon: its own timezone, not UTC. Every metrics writer and the reconciler call this, so they cannot disagree about where midnight is (0076).';

revoke all on function app.salon_day(uuid, timestamptz) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION app.on_visit_completed(p_visit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_visit     record;
  v_service   uuid;
  v_median    numeric;
  v_gaps      integer;
  v_visits    integer;
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

  -- Today's numbers, reconciled nightly by Automation E, which ALERTS on a
  -- mismatch rather than healing it (6.8).
  --
  -- NOTE: this is NOT idempotent, and cannot be here - a metrics row has no
  -- natural key for "this visit was already counted". Automation E's nightly
  -- recompute from source is what makes a double count visible; the drift is
  -- meant to surface rather than hide.
  insert into public.daily_salon_metrics (salon_id, day, revenue_paise, completed)
  values (v_visit.salon_id, app.salon_day(v_visit.salon_id, v_visit.completed_at),
          coalesce(v_visit.final_amount_paise, 0), 1)
  on conflict (salon_id, day) do update
     set revenue_paise = public.daily_salon_metrics.revenue_paise
                         + coalesce(v_visit.final_amount_paise, 0),
         completed = public.daily_salon_metrics.completed + 1,
         updated_at = now();

  if v_service is null then
    return jsonb_build_object('ok', true, 'reminder_id', null, 'reason', 'no_service');
  end if;

  select coalesce(s.default_reminder_cycle_days, 30) into v_cycle
    from public.salons s where s.id = v_visit.salon_id;
  v_cycle := coalesce(v_cycle, 30);

  -- The learned interval (ARCHITECTURE 6.7): a clamped MEDIAN of this
  -- customer's own gaps, which is explainable to a salon owner in a way a model
  -- is not. sample_n counts VISITS, the unit the table's constraint counts in.
  with visits as (
    select v.completed_at
      from public.visits v
      join public.booking_items bi
        on bi.booking_id = v.booking_id and bi.kind = 'service'
     where v.customer_id = v_visit.customer_id
       and bi.ref_id = v_service
       and v.completed_at is not null
  ), gaps as (
    select extract(epoch from (completed_at - lag(completed_at) over (order by completed_at)))
           / 86400.0 as days
      from visits
  )
  select percentile_cont(0.5) within group (order by g.days),
         count(g.days)::integer,
         (select count(*)::integer from visits)
    into v_median, v_gaps, v_visits
    from gaps g
   where g.days is not null and g.days > 0;

  if coalesce(v_visits, 0) >= 2 and coalesce(v_gaps, 0) >= 1 and v_median is not null then
    insert into public.customer_service_intervals
      (salon_id, customer_id, service_id, median_days, sample_n, updated_at)
    values (v_visit.salon_id, v_visit.customer_id, v_service,
            greatest(round(v_median)::integer, 1), v_visits, now())
    on conflict (salon_id, customer_id, service_id) do update
       set median_days = excluded.median_days,
           sample_n = excluded.sample_n,
           updated_at = now();

    v_due := v_visit.completed_at
             + make_interval(days => greatest(v_cycle / 2,
                                     least(round(v_median)::integer, v_cycle * 2)));
  else
    v_due := v_visit.completed_at + make_interval(days => v_cycle);
  end if;

  -- **`and cycle_key <> this visit`** is the whole of 0063. Without it a replay
  -- converts the row it just created, frees the partial unique index, and
  -- inserts a duplicate - so the customer gets two reminders for one haircut and
  -- the salon pays to send both.
  update public.reminders
     set status = 'converted'
   where salon_id = v_visit.salon_id
     and customer_id = v_visit.customer_id
     and service_id = v_service
     and cycle_key <> p_visit_id::text
     and status in ('scheduled', 'sent', 'delivered');
  get diagnostics v_converted = row_count;

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
    'median_days', case when coalesce(v_visits, 0) >= 2 and coalesce(v_gaps, 0) >= 1
                        then round(v_median)::integer end,
    'sample_n', v_visits,
    'superseded', v_converted);
end;
$function$;

CREATE OR REPLACE FUNCTION app.on_booking_confirmed(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  values (v_booking.salon_id, app.salon_day(v_booking.salon_id, v_booking.starts_at), 1)
  on conflict (salon_id, day) do update
     set bookings = public.daily_salon_metrics.bookings + 1,
         updated_at = now();

  return jsonb_build_object('ok', true, 'notification_id', v_notification,
                            'reminders_converted', v_stopped);
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_send(p_delivery_id uuid, p_status text, p_provider_message_id text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text, p_cost_paise bigint DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_notification uuid;
begin
  update public.notification_deliveries
     set provider_status = p_status,
         provider_message_id = p_provider_message_id,
         failure_reason = p_failure_reason,
         cost_paise = greatest(coalesce(p_cost_paise, 0), 0),
         sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_delivery_id
  returning notification_id into v_notification;

  if v_notification is null then
    return;
  end if;

  -- `sent` is not `delivered` and is certainly not `acked`. The notification
  -- only leaves `sent` when the app says the message arrived, or when the sweep
  -- gives up on the window (12.3).
  if p_status = 'sent' then
    update public.notifications
       set status = 'sent'
     where id = v_notification and status = 'pending';
  end if;

  -- The salon's cost, not Crayora's (12.4). Reported to the owner beside the
  -- conversion it bought, never as a number on its own.
  if coalesce(p_cost_paise, 0) > 0 then
    insert into public.daily_salon_metrics (salon_id, day, messaging_cost_paise)
    select d.salon_id, app.salon_day(d.salon_id, now()), p_cost_paise
      from public.notification_deliveries d where d.id = p_delivery_id
    on conflict (salon_id, day) do update
       set messaging_cost_paise = public.daily_salon_metrics.messaging_cost_paise + p_cost_paise,
           updated_at = now();
  end if;
end;
$function$;
