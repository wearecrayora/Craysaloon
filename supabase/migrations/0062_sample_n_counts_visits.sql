-- 0062 `sample_n >= 2` counts VISITS, not gaps
--
-- `customer_service_intervals` has carried `check (sample_n >= 2)` since M1, and
-- 0059-0061 wrote the number of *gaps* into it. Two visits produce one gap, so
-- the very first learned interval - the case ARCHITECTURE 6.7 describes as
-- "after >= 2 visits" - violated the constraint and threw.
--
-- The constraint is the authority, and it agrees with the document once the
-- units match: `sample_n` is how many visits the median was drawn from. Two
-- visits, one gap, `sample_n = 2`.
--
-- This is the third correction to the same function in one session, and all
-- three were the same mistake: a column or a constraint assumed instead of
-- read. What actually fixed it was running the gate - plpgsql validates nothing
-- at CREATE time, so an unexercised function is an untested guess.

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

  select coalesce(s.default_reminder_cycle_days, 30) into v_cycle
    from public.salons s where s.id = v_visit.salon_id;
  v_cycle := coalesce(v_cycle, 30);

  -- The learned interval (ARCHITECTURE 6.7). A clamped MEDIAN of this
  -- customer's own gaps for this service - deliberately not a model, because a
  -- median is explainable to a salon owner and a model is not.
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

  -- >= 2 VISITS, which is >= 1 gap. sample_n records the visits, because that is
  -- the unit the table's check constraint counts in.
  if coalesce(v_visits, 0) >= 2 and coalesce(v_gaps, 0) >= 1 and v_median is not null then
    insert into public.customer_service_intervals
      (salon_id, customer_id, service_id, median_days, sample_n, updated_at)
    values (v_visit.salon_id, v_visit.customer_id, v_service,
            greatest(round(v_median)::integer, 1), v_visits, now())
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
    'median_days', case when coalesce(v_visits, 0) >= 2 and coalesce(v_gaps, 0) >= 1
                        then round(v_median)::integer end,
    'sample_n', v_visits,
    'superseded', v_converted);
end;
$$;

comment on function app.on_visit_completed is
  'Automation A. Last visit, learned interval, exactly ONE reminder per cycle, today''s metrics. sample_n counts VISITS, which is the unit the table''s check constraint counts in (0062). No loyalty award: points and tiers are Tier 2 (PRD 10.3) and no document specifies the rule.';
