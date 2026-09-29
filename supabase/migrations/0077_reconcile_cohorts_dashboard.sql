-- 0077 M10: the numbers, checked against the money
--
-- Three pieces, and one rule that shapes all of them (PRD 9.5 AC):
--
--   **card totals must equal the sum of completed transactions, verified by a
--   nightly reconciliation that ALERTS on mismatch rather than silently
--   correcting.**
--
-- `daily_salon_metrics` has two kinds of column, and they are treated
-- differently on purpose:
--
--   * INCREMENTAL - revenue, completed, bookings, messaging cost. Written live
--     by Automations A and C and by `record_send`. The reconciler recomputes
--     them from source and, on a mismatch, **records the drift and leaves the
--     row alone**. Healing it silently would hide the bug that caused it; the
--     drift is the evidence.
--   * DERIVED - new vs repeat, wallet collected and outstanding, add-on revenue,
--     reminder bookings, binds, no-shows. Nothing writes these live. The nightly
--     job IS their writer, so it computes and stores them - comparing a value
--     against itself would alert on every salon, every night, and an alert that
--     always fires is one nobody reads.
--
-- The first reconciliation on any existing salon WILL report drift: bookings
-- and visits made before 0075 were never counted, because Automations A and C
-- had no caller. That is correct - it is exactly the historical damage of that
-- bug, surfaced rather than papered over.

-- One drift alert per salon per day, however many times the nightly job runs.
create unique index if not exists domain_events_metrics_drift_once_idx
  on public.domain_events (salon_id, (payload ->> 'day'))
  where type = 'metrics.drift';

-- ---------------------------------------------------------------------------
-- 1. Automation E: reconcile one salon-day
-- ---------------------------------------------------------------------------

create or replace function app.reconcile_day(p_salon_id uuid, p_day date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stored  record;
  v_src_revenue   bigint;
  v_src_completed integer;
  v_src_bookings  integer;
  v_src_cost      bigint;
  v_drift   jsonb := '{}'::jsonb;
begin
  -- ---- source of truth, bucketed by the SAME salon_day the writers use -----
  select coalesce(sum(v.final_amount_paise), 0), count(*)::integer
    into v_src_revenue, v_src_completed
    from public.visits v
   where v.salon_id = p_salon_id
     and v.completed_at is not null
     and app.salon_day(p_salon_id, v.completed_at) = p_day;

  -- Every booking created for that day, whatever became of it: Automation C
  -- counts at creation and never decrements, so the definition the reconciler
  -- checks must be the definition the writer writes. Cancellations are shown
  -- separately, from source, on the dashboard.
  select count(*)::integer into v_src_bookings
    from public.bookings b
   where b.salon_id = p_salon_id
     and app.salon_day(p_salon_id, b.starts_at) = p_day;

  select coalesce(sum(d.cost_paise), 0) into v_src_cost
    from public.notification_deliveries d
   where d.salon_id = p_salon_id
     and d.sent_at is not null
     and app.salon_day(p_salon_id, d.sent_at) = p_day;

  select m.revenue_paise, m.completed, m.bookings, m.messaging_cost_paise
    into v_stored
    from public.daily_salon_metrics m
   where m.salon_id = p_salon_id and m.day = p_day;

  -- ---- compare the INCREMENTAL columns; never overwrite them ----------------
  if coalesce(v_stored.revenue_paise, 0) <> v_src_revenue then
    v_drift := v_drift || jsonb_build_object('revenue_paise',
      jsonb_build_object('stored', coalesce(v_stored.revenue_paise, 0), 'source', v_src_revenue));
  end if;
  if coalesce(v_stored.completed, 0) <> v_src_completed then
    v_drift := v_drift || jsonb_build_object('completed',
      jsonb_build_object('stored', coalesce(v_stored.completed, 0), 'source', v_src_completed));
  end if;
  if coalesce(v_stored.bookings, 0) <> v_src_bookings then
    v_drift := v_drift || jsonb_build_object('bookings',
      jsonb_build_object('stored', coalesce(v_stored.bookings, 0), 'source', v_src_bookings));
  end if;
  if coalesce(v_stored.messaging_cost_paise, 0) <> v_src_cost then
    v_drift := v_drift || jsonb_build_object('messaging_cost_paise',
      jsonb_build_object('stored', coalesce(v_stored.messaging_cost_paise, 0), 'source', v_src_cost));
  end if;

  if v_drift <> '{}'::jsonb then
    -- The ALERT. Written, not healed: the stored number stays wrong on the card
    -- until someone finds out why, because the why is the bug.
    insert into public.domain_events (salon_id, type, aggregate_id, payload)
    values (p_salon_id, 'metrics.drift', null,
            jsonb_build_object('day', p_day::text, 'fields', v_drift))
    on conflict (salon_id, (payload ->> 'day')) where type = 'metrics.drift'
      do nothing;
  end if;

  -- ---- the DERIVED columns: the nightly job is their only writer -------------
  insert into public.daily_salon_metrics
    (salon_id, day, no_shows, new_customers, repeat_customers,
     wallet_collected_paise, wallet_outstanding_paise, addon_revenue_paise,
     reminder_bookings, binds, updated_at)
  select p_salon_id, p_day,
    -- no-shows booked for that day
    (select count(*)::integer from public.bookings b
      where b.salon_id = p_salon_id and b.status = 'no_show'
        and app.salon_day(p_salon_id, b.starts_at) = p_day),
    -- a visit that day by someone whose FIRST completed visit it was
    (select count(distinct v.customer_id)::integer from public.visits v
      where v.salon_id = p_salon_id and v.completed_at is not null
        and app.salon_day(p_salon_id, v.completed_at) = p_day
        and not exists (select 1 from public.visits e
                         where e.customer_id = v.customer_id
                           and e.completed_at < v.completed_at)),
    -- a visit that day by someone who had been before
    (select count(distinct v.customer_id)::integer from public.visits v
      where v.salon_id = p_salon_id and v.completed_at is not null
        and app.salon_day(p_salon_id, v.completed_at) = p_day
        and exists (select 1 from public.visits e
                     where e.customer_id = v.customer_id
                       and e.completed_at < v.completed_at)),
    -- money customers PUT IN that day (paid top-ups only - bonus is not money)
    (select coalesce(sum(t.amount_paise), 0) from public.wallet_transactions t
      where t.salon_id = p_salon_id and t.kind = 'credit_topup'
        and app.salon_day(p_salon_id, t.created_at) = p_day),
    -- credit outstanding at the time the job ran: a snapshot, and the nightly
    -- run is minutes after midnight, so it is "at close of p_day" in practice
    (select coalesce(sum(w.balance_paise), 0) from public.wallet_accounts w
      where w.salon_id = p_salon_id),
    -- add-on revenue from visits completed that day
    (select coalesce(sum(bi.price_paise), 0)
       from public.visits v
       join public.booking_items bi on bi.booking_id = v.booking_id and bi.kind = 'add_on'
      where v.salon_id = p_salon_id and v.completed_at is not null
        and app.salon_day(p_salon_id, v.completed_at) = p_day),
    -- bookings a reminder produced: booked FROM a reminder, or booked while one
    -- was outstanding for that service (Automation C marks it converted). The
    -- second is generous attribution, and deliberately so - it is the number an
    -- owner weighs against what the reminders cost.
    (select count(distinct b.id)::integer from public.bookings b
      where b.salon_id = p_salon_id
        and app.salon_day(p_salon_id, b.starts_at) = p_day
        and (b.source = 'reminder'
             or exists (select 1 from public.reminders r
                         where r.booking_id = b.id and r.status = 'converted'))),
    (select count(*)::integer from public.domain_events e
      where e.salon_id = p_salon_id and e.type = 'customer.bound'
        and app.salon_day(p_salon_id, e.occurred_at) = p_day),
    now()
  on conflict (salon_id, day) do update
     set no_shows = excluded.no_shows,
         new_customers = excluded.new_customers,
         repeat_customers = excluded.repeat_customers,
         wallet_collected_paise = excluded.wallet_collected_paise,
         wallet_outstanding_paise = excluded.wallet_outstanding_paise,
         addon_revenue_paise = excluded.addon_revenue_paise,
         reminder_bookings = excluded.reminder_bookings,
         binds = excluded.binds,
         updated_at = now();

  return jsonb_build_object('ok', true, 'day', p_day, 'drift', v_drift,
                            'drifted', v_drift <> '{}'::jsonb);
end;
$$;

comment on function app.reconcile_day is
  'Automation E for one salon-day. Recomputes the INCREMENTAL columns from source and, on a mismatch, records metrics.drift and leaves the row alone - healing silently would hide the bug (PRD 9.5). Computes and stores the DERIVED columns, which have no other writer. Idempotent: one drift alert per salon-day.';

-- ---------------------------------------------------------------------------
-- 2. Retention cohorts
-- ---------------------------------------------------------------------------

create or replace function app.refresh_retention_cohorts(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  -- A pure read model: rebuilt whole, so a customer who changes segment or a
  -- visit that arrives late cannot leave a stale row behind.
  delete from public.retention_cohorts where salon_id = p_salon_id;

  with firsts as (
    select v.customer_id, min(v.completed_at) as first_at
      from public.visits v
     where v.salon_id = p_salon_id and v.completed_at is not null
       and v.customer_id is not null
     group by v.customer_id
  ), members as (
    select f.customer_id, f.first_at,
           date_trunc('month', app.salon_day(p_salon_id, f.first_at))::date as cohort_month,
           -- "Wallet" means the customer has ever put their own money in.
           -- Bonus and referral credit do not count: the question the owner is
           -- asking is whether PREPAYING changes whether people come back.
           case when exists (select 1 from public.wallet_transactions t
                              where t.customer_id = f.customer_id
                                and t.kind = 'credit_topup')
                then 'wallet' else 'no_wallet' end as wallet_segment,
           exists (select 1 from public.visits r where r.customer_id = f.customer_id
                    and r.completed_at > f.first_at
                    and r.completed_at <= f.first_at + interval '30 days') as back30,
           exists (select 1 from public.visits r where r.customer_id = f.customer_id
                    and r.completed_at > f.first_at
                    and r.completed_at <= f.first_at + interval '60 days') as back60,
           exists (select 1 from public.visits r where r.customer_id = f.customer_id
                    and r.completed_at > f.first_at
                    and r.completed_at <= f.first_at + interval '90 days') as back90,
           (f.first_at + interval '30 days' <= now()) as ripe30,
           (f.first_at + interval '60 days' <= now()) as ripe60,
           (f.first_at + interval '90 days' <= now()) as ripe90
      from firsts f
  )
  insert into public.retention_cohorts
    (salon_id, cohort_month, wallet_segment, cohort_size, d30, d60, d90, updated_at)
  select p_salon_id, m.cohort_month, m.wallet_segment, count(*)::integer,
         -- NULL until EVERY member has had the full window. A cohort that is
         -- 40 days old has no 60-day figure: printing one would count people
         -- who have not yet had the chance to come back as people who did not,
         -- and the chart would show every young cohort as a failure.
         case when bool_and(m.ripe30)
              then round(100.0 * count(*) filter (where m.back30) / count(*), 1) end,
         case when bool_and(m.ripe60)
              then round(100.0 * count(*) filter (where m.back60) / count(*), 1) end,
         case when bool_and(m.ripe90)
              then round(100.0 * count(*) filter (where m.back90) / count(*), 1) end,
         now()
    from members m
   group by m.cohort_month, m.wallet_segment;

  get diagnostics v_rows = row_count;
  return jsonb_build_object('ok', true, 'cohorts', v_rows);
end;
$$;

comment on function app.refresh_retention_cohorts is
  'Rebuilds a salon''s 30/60/90-day return rates by first-visit month, wallet vs no-wallet. A rate is NULL until every member of the cohort has had the full window - a young cohort has no 60-day figure, and printing 0% would call people who have not yet had the chance "lost".';

-- ---------------------------------------------------------------------------
-- 3. The nightly run, per salon, one broken salon failing alone
-- ---------------------------------------------------------------------------

create or replace function app.run_nightly()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   record;
  v_result  jsonb;
  v_drifted integer := 0;
  v_failed  integer := 0;
begin
  for v_salon in
    select s.id from public.salons s where s.status in ('active', 'grace')
  loop
    begin
      -- YESTERDAY in the salon's own timezone: the day that has closed.
      v_result := app.reconcile_day(v_salon.id, app.salon_day(v_salon.id, now()) - 1);
      if (v_result ->> 'drifted')::boolean then
        v_drifted := v_drifted + 1;
      end if;
      perform app.refresh_retention_cohorts(v_salon.id);
    exception when others then
      v_failed := v_failed + 1;
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (v_salon.id, 'automation.failed', null,
              jsonb_build_object('job', 'nightly', 'sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('ok', true, 'salons_drifted', v_drifted, 'salons_failed', v_failed);
end;
$$;

comment on function app.run_nightly is
  'Automation E and the cohort refresh for every live salon, each salon in its own exception block. Scheduled by scripts/db/schedule.sql, not a migration.';

-- ---------------------------------------------------------------------------
-- 4. What the owner sees
-- ---------------------------------------------------------------------------

create or replace function public.owner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon  uuid := app.current_salon_id();
  v_role   text := app.current_app_role();
  v_today  date;
  v_month  date;
  v_out    jsonb;
begin
  if v_salon is null or v_role not in ('owner', 'manager') then
    raise exception 'owner_dashboard: owners and managers only' using errcode = '42501';
  end if;

  v_today := app.salon_day(v_salon, now());
  v_month := date_trunc('month', v_today)::date;

  select jsonb_build_object(
    'day', v_today,

    -- TODAY IS COMPUTED FROM SOURCE, not read from the metrics table. The card
    -- then equals the completed transactions by construction (PRD 9.5 AC), and
    -- the incremental table is only ever needed for history.
    'today', (
      select jsonb_build_object(
        'revenue_paise', coalesce(sum(v.final_amount_paise), 0),
        'completed', count(*),
        'avg_bill_paise', case when count(*) > 0
                               then (sum(v.final_amount_paise) / count(*))::bigint end)
        from public.visits v
       where v.salon_id = v_salon and v.completed_at is not null
         and app.salon_day(v_salon, v.completed_at) = v_today),

    'bookings_today', (
      select jsonb_build_object(
        'live', count(*) filter (where b.status in ('pending', 'confirmed', 'completed')),
        'cancelled', count(*) filter (where b.status = 'cancelled'),
        'no_show', count(*) filter (where b.status = 'no_show'))
        from public.bookings b
       where b.salon_id = v_salon and app.salon_day(v_salon, b.starts_at) = v_today),

    'month', (
      select jsonb_build_object(
        'new_customers', coalesce(sum(m.new_customers), 0),
        'repeat_customers', coalesce(sum(m.repeat_customers), 0),
        'wallet_collected_paise', coalesce(sum(m.wallet_collected_paise), 0),
        'reminder_bookings', coalesce(sum(m.reminder_bookings), 0),
        'binds', coalesce(sum(m.binds), 0))
        from public.daily_salon_metrics m
       where m.salon_id = v_salon and m.day >= v_month and m.day < v_today),

    -- A balance the owner can SEE and cannot move (PRD 9.5: the adjust-wallet
    -- action was removed in v4.1, and no control, API or permission grants it).
    'outstanding_credit_paise', (
      select coalesce(sum(w.balance_paise), 0) from public.wallet_accounts w
       where w.salon_id = v_salon),

    -- Spend and conversion TOGETHER, never apart (PRD 9.5): cost alone invites
    -- switching reminders off, conversion alone invites paying Rs 1.28 a
    -- message without noticing.
    'messaging', jsonb_build_object(
      'spend_by_channel', coalesce((
        select jsonb_object_agg(x.channel, x.paise) from (
          select d.channel::text as channel, sum(d.cost_paise) as paise
            from public.notification_deliveries d
           where d.salon_id = v_salon and d.sent_at is not null
             and app.salon_day(v_salon, d.sent_at) >= v_month
           group by d.channel) x), '{}'::jsonb),
      'acked_pushes', (
        select count(*) from public.notification_deliveries d
         where d.salon_id = v_salon and d.channel = 'push' and d.acked_at is not null
           and app.salon_day(v_salon, d.sent_at) >= v_month),
      'reminders_sent', (
        select count(*) from public.reminders r
         where r.salon_id = v_salon and r.status in ('sent', 'delivered', 'converted')
           and app.salon_day(v_salon, r.scheduled_for) >= v_month),
      'reminder_bookings', (
        select count(distinct r.booking_id) from public.reminders r
         where r.salon_id = v_salon and r.status = 'converted' and r.booking_id is not null
           and app.salon_day(v_salon, r.scheduled_for) >= v_month)),

    'cohorts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'month', c.cohort_month, 'segment', c.wallet_segment,
               'n', c.cohort_size, 'd30', c.d30, 'd60', c.d60, 'd90', c.d90)
             order by c.cohort_month, c.wallet_segment)
        from public.retention_cohorts c
       where c.salon_id = v_salon
         and c.cohort_month >= (v_month - interval '11 months')::date), '[]'::jsonb),

    -- Drift is SHOWN, not hidden. An owner looking at a number the system has
    -- flagged as disagreeing with the money deserves to know which one.
    'drift_days', coalesce((
      select jsonb_agg(e.payload order by (e.payload ->> 'day') desc)
        from public.domain_events e
       where e.salon_id = v_salon and e.type = 'metrics.drift'
         and (e.payload ->> 'day')::date >= v_today - 30), '[]'::jsonb)
  ) into v_out;

  return v_out;
end;
$$;

comment on function public.owner_dashboard is
  'O1. Today is computed FROM SOURCE, so the cards equal the completed transactions by construction (PRD 9.5 AC); history comes from the reconciled read model. Messaging spend is returned beside reminder conversion, never alone. Drift is returned, not hidden. There is no write path here, and none anywhere, that moves a balance.';

revoke all on function public.owner_dashboard() from public, anon;
grant execute on function public.owner_dashboard() to authenticated;

revoke all on function app.reconcile_day(uuid, date) from public, anon, authenticated;
revoke all on function app.refresh_retention_cohorts(uuid) from public, anon, authenticated;
revoke all on function app.run_nightly() from public, anon, authenticated;

select app_admin.close_privileges();
