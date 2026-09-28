-- 0063 A replay was converting its own reminder, and so defeating the index
--
-- The gate caught the one thing it exists to catch.
--
-- `on_visit_completed` converts any outstanding reminder for the service before
-- inserting the new one - that is what lets a SECOND visit move the schedule
-- instead of colliding with the partial unique index and losing. But it
-- converted **every** outstanding reminder, including the one the same visit had
-- created a moment earlier. The partial index only covers
-- `scheduled | sent | delivered`, so converting that row freed the slot and the
-- replay inserted a duplicate.
--
-- The effect in production: a replayed offline mark-complete - the normal case
-- for an owner marking visits done on salon wifi (RULES 13) - would give the
-- customer two reminders for one haircut, and the salon would pay to send both.
--
-- The fix is one predicate: never convert a reminder that belongs to THIS
-- visit. A replay then finds its own row still scheduled, hits the index, and
-- becomes the no-op ARCHITECTURE 6.6 promises. A genuine second visit carries a
-- different cycle_key, converts the old row, and takes the slot.

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
$$;

comment on function app.on_visit_completed is
  'Automation A. Exactly one reminder per cycle, enforced by the index: a replay never converts its OWN reminder (0063), so it collides and becomes a no-op, while a genuine second visit carries a different cycle_key and moves the schedule. sample_n counts visits. No loyalty award - Tier 2 (PRD 10.3).';
