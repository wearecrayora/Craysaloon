-- 0059 M8: reminders, the channel ladder, and the ack that gates escalation
--
-- Automations A (visit completed), C (booking confirmed) and K (escalation
-- sweep), plus the notification intent they all create.
--
-- Three rules shape every line, and each of them exists because the obvious
-- implementation costs a salon real money:
--
--   * **Exactly one reminder per cycle, enforced by an index** (ARCHITECTURE
--     6.6). Not by "we only call it once": a replayed offline mark-complete, a
--     retried job and a duplicate event must all become no-ops.
--   * **Escalation is gated on an ACK, never on FCM's response** (12.3). FCM
--     reports "accepted by Google", which is not delivery. Trusting it either
--     never escalates or always does, and the second one spends the salon's
--     money on every message.
--   * **A salon with no WhatsApp templates and no RCS agent still works.** The
--     ladder skips a rung it cannot use; it never blocks and never errors.
--
-- **Loyalty is deliberately absent from Automation A.** PRD §10.3 puts points
-- and tiers in Tier 2, and no document specifies the rule's shape. Inventing
-- one is precisely the bug 0058 fixed: the console wrote one shape, the ledger
-- read another, and a whole feature silently did nothing. An absent award is
-- visible; a wrong one is not.

-- ---------------------------------------------------------------------------
-- 0. The consent view the ladder reads had 0052's bug
-- ---------------------------------------------------------------------------
--
-- `my_consents` was fixed in 0052: `occurred_at` is the TRANSACTION time, so two
-- changes in one transaction tie and `distinct on` picks whichever row the plan
-- produced first - resolving, at worst, to "still consented". The same ordering
-- was left in this view, which is the one the CHANNEL LADDER reads. The failure
-- there is not a wrong toggle on a screen; it is a marketing message sent to
-- someone who withdrew consent, billed to the salon, and reportable.

create or replace view public.consent_state
with (security_invoker = true) as
select distinct on (customer_id, purpose)
       salon_id, customer_id, purpose, granted, occurred_at
  from public.consents
 order by customer_id, purpose, occurred_at desc, id desc;

comment on view public.consent_state is
  'Current state per purpose: the LAST row of the ledger, ordered by occurred_at AND id. The id tiebreak is not cosmetic - occurred_at is transaction time, and the tie resolves to "still consented", which here means sending marketing to someone who withdrew it (0052, 0059).';

-- ---------------------------------------------------------------------------
-- 1. The intent
-- ---------------------------------------------------------------------------

create or replace function app.notify(
  p_salon_id     uuid,
  p_customer_id  uuid,
  p_purpose      text,
  p_category     public.message_category,
  p_template_key text,
  p_params       jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_locale  text;
  v_allowed boolean;
  v_id      uuid;
begin
  -- Locale: the customer's own, then the salon's first declared language, then
  -- English (ARCHITECTURE 12.5).
  select coalesce(c.language, (select s.languages[1] from public.salons s where s.id = p_salon_id), 'en')
    into v_locale
    from public.customers c
   where c.id = p_customer_id;

  if v_locale is null then
    return null;  -- no such customer in this salon
  end if;

  -- Consent, per purpose, from the ledger's current state.
  --
  -- Marketing needs `promotional`. Transactional rides on
  -- `service_communication`, which is the service itself and cannot be
  -- withdrawn while the account exists (RULES 11.6c) - so its absence means a
  -- customer whose consent rows were never written, not one who said no.
  if p_category = 'marketing' then
    select coalesce(cs.granted, false) into v_allowed
      from public.consent_state cs
     where cs.customer_id = p_customer_id and cs.purpose = 'promotional';
  else
    select coalesce(cs.granted, true) into v_allowed
      from public.consent_state cs
     where cs.customer_id = p_customer_id and cs.purpose = 'service_communication';
  end if;

  insert into public.notifications
    (salon_id, customer_id, purpose, category, locale, template_key, params, status)
  values
    (p_salon_id, p_customer_id, p_purpose, p_category, v_locale, p_template_key, p_params,
     case when coalesce(v_allowed, p_category <> 'marketing')
          then 'pending'::public.notification_status
          -- Recorded, not dropped. "We did not send this, and why" is the row
          -- that answers a complaint and proves the withdrawal was honoured.
          else 'suppressed'::public.notification_status end)
  returning id into v_id;

  return v_id;
end;
$$;

comment on function app.notify is
  'Creates the notification INTENT (ARCHITECTURE 12.1). Consent is resolved here, once, from the ledger - a suppressed message is written down rather than dropped, because "we did not send this, and why" is what answers a complaint.';

-- ---------------------------------------------------------------------------
-- 2. Automation A - a visit was completed
-- ---------------------------------------------------------------------------

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

  -- The service this visit was for. A booking can carry several; the reminder
  -- follows the FIRST one, which is the booking's primary service.
  select bi.service_id into v_service
    from public.booking_items bi
   where bi.booking_id = v_visit.booking_id
     and bi.service_id is not null
   order by bi.created_at
   limit 1;

  update public.customers
     set last_visit = v_visit.completed_at,
         updated_at = now()
   where id = v_visit.customer_id
     and (last_visit is null or last_visit < v_visit.completed_at);

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
    -- Nothing to remind about: no service on the booking. Still a completed
    -- visit, so the metrics above stand.
    return jsonb_build_object('ok', true, 'reminder_id', null, 'reason', 'no_service');
  end if;

  -- The learned interval (ARCHITECTURE 6.7). A clamped MEDIAN of this
  -- customer's own gaps for this service - deliberately not a model, because a
  -- median is explainable to a salon owner and a model is not.
  with gaps as (
    select extract(epoch from (v.completed_at - lag(v.completed_at)
             over (order by v.completed_at))) / 86400.0 as days
      from public.visits v
      join public.booking_items bi on bi.booking_id = v.booking_id
     where v.customer_id = v_visit.customer_id
       and bi.service_id = v_service
       and v.completed_at is not null
  )
  select percentile_cont(0.5) within group (order by days), count(*)::integer
    into v_median, v_sample
    from gaps where days is not null and days > 0;

  select s.default_reminder_cycle_days into v_cycle
    from public.salons s where s.id = v_visit.salon_id;
  v_cycle := coalesce(v_cycle, 30);

  if coalesce(v_sample, 0) >= 2 and v_median is not null then
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
    'median_days', case when coalesce(v_sample, 0) >= 2 then round(v_median)::integer end,
    'superseded', v_converted);
end;
$$;

comment on function app.on_visit_completed is
  'Automation A. Last visit, learned interval, exactly ONE reminder per cycle, today''s metrics. No loyalty award: points and tiers are Tier 2 (PRD 10.3) and no document specifies the rule - and 0058 is what inventing a rule shape costs.';

-- ---------------------------------------------------------------------------
-- 3. Automation C - a booking was confirmed
-- ---------------------------------------------------------------------------

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

  select bi.service_id into v_service
    from public.booking_items bi
   where bi.booking_id = p_booking_id and bi.service_id is not null
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
  'Automation C. Confirms, and stops the reminder that would otherwise nag a customer who has already booked - marked `converted`, which is also what makes reminder conversion measurable.';

-- ---------------------------------------------------------------------------
-- 4. The ack, and Automation K
-- ---------------------------------------------------------------------------

create or replace function app.escalation_window(p_purpose text)
returns interval
language sql
immutable
set search_path = ''
as $$
  -- ARCHITECTURE 12.3. Patience is cheap for a reminder and expensive for a
  -- booking confirmation, and these numbers are the difference between a salon
  -- paying Rs 0 and paying for every message it sends.
  select case p_purpose
    when 'booking_confirmed' then interval '5 minutes'
    when 'wallet_receipt'    then interval '15 minutes'
    when 'service_due'       then interval '6 hours'
    when 'billing'           then interval '1 hour'
    else interval '1 hour'
  end
$$;

create or replace function public.ack_notification(p_delivery_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
  v_row      record;
begin
  if v_customer is null then
    raise exception 'ack_notification: only the recipient may acknowledge'
      using errcode = '42501';
  end if;

  select d.id, d.acked_at, n.id as notification_id, n.status
    into v_row
    from public.notification_deliveries d
    join public.notifications n on n.id = d.notification_id
   where d.id = p_delivery_id
     and n.customer_id = v_customer;

  if v_row.id is null then
    -- Someone else's delivery, or none. The same answer for both: an ack
    -- endpoint that distinguishes them is an endpoint that enumerates them.
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v_row.acked_at is not null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.notification_deliveries set acked_at = now() where id = p_delivery_id;

  -- An acked push is money the owner did not spend (12.4), and the status is
  -- what the escalation sweep reads to leave it alone.
  update public.notifications
     set status = 'acked'
   where id = v_row.notification_id and status in ('pending', 'sent');

  return jsonb_build_object('ok', true, 'already', false);
end;
$$;

comment on function public.ack_notification is
  'The ack that gates escalation (ARCHITECTURE 12.3). FCM reports "accepted by Google", not "delivered" - so the APP says it arrived, and until it does the sweep counts the window. Only the recipient may ack, and an unknown delivery answers the same as someone else''s.';

revoke all on function public.ack_notification(uuid) from public, anon;
grant execute on function public.ack_notification(uuid) to authenticated;

-- What channel comes next, given what this salon can actually use.
create or replace function app.next_channel(
  p_salon_id uuid,
  p_category public.message_category,
  p_tried    public.message_channel[]
)
returns public.message_channel
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rcs_ok      boolean;
  v_whatsapp_ok boolean;
  v_prefs       jsonb;
begin
  select (i.rcs_agent_status = 'verified') into v_rcs_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'rcs';

  select (i.whatsapp_template_status = 'approved') into v_whatsapp_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'whatsapp';

  select coalesce(s.notification_prefs, '{}'::jsonb) into v_prefs
    from public.salons s where s.id = p_salon_id;

  -- RCS sits above WhatsApp when the agent is verified: cheaper, and it carries
  -- the salon's name and logo natively (12.2a). Skipped entirely when it is not
  -- - a rung the salon cannot use is not an error, it is simply not there.
  if coalesce(v_rcs_ok, false) and not ('rcs' = any(p_tried)) then
    return 'rcs';
  end if;

  if p_category = 'transactional' then
    -- WhatsApp Utility is CHEAPER than SMS (Rs 0.17 vs Rs 0.22), which is the
    -- fact that surprises people and decides this order.
    if coalesce(v_whatsapp_ok, false) and not ('whatsapp' = any(p_tried)) then
      return 'whatsapp';
    end if;
    if not ('sms' = any(p_tried)) then
      return 'sms';
    end if;
    return null;
  end if;

  -- Marketing: SMS by default, because WhatsApp Marketing is six times the
  -- price of SMS and it is the SALON's money. WhatsApp only if the owner has
  -- said so explicitly.
  if not ('sms' = any(p_tried)) then
    return 'sms';
  end if;
  if (v_prefs ->> 'marketing_escalation') = 'whatsapp'
     and coalesce(v_whatsapp_ok, false)
     and not ('whatsapp' = any(p_tried)) then
    return 'whatsapp';
  end if;

  return null;
end;
$$;

comment on function app.next_channel is
  'The ladder (ARCHITECTURE 12.2), per salon and per category. A salon with no approved WhatsApp templates and no verified RCS agent still works completely - the rungs it cannot use are skipped, never errored on. Marketing escalates to SMS, not to WhatsApp Marketing at 6x the price, unless the owner has opted in.';

create or replace function app.escalate_due_deliveries(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row      record;
  v_next     public.message_channel;
  v_tried    public.message_channel[];
  v_escalated integer := 0;
  v_exhausted integer := 0;
begin
  for v_row in
    select d.id, d.notification_id, n.purpose, n.category
      from public.notification_deliveries d
      join public.notifications n on n.id = d.notification_id
     where d.salon_id = p_salon_id
       and d.acked_at is null
       and d.sent_at is not null
       -- Unacked past its window. A dead token short-circuits the wait, which
       -- is the whole point of marking it dead the moment FCM says UNREGISTERED.
       and d.sent_at + app.escalation_window(n.purpose) <= now()
       and n.status in ('pending', 'sent')
  loop
    select array_agg(d2.channel) into v_tried
      from public.notification_deliveries d2
     where d2.notification_id = v_row.notification_id;

    v_next := app.next_channel(p_salon_id, v_row.category, coalesce(v_tried, '{}'));

    if v_next is null then
      -- Nothing left to try. Recorded as a state, not as an error: a customer
      -- with no reachable channel is a fact the salon should be able to see.
      update public.notifications
         set status = 'no_channel_available'
       where id = v_row.notification_id;
      v_exhausted := v_exhausted + 1;
    else
      -- Queued, not sent: the dispatcher owns the provider call. A row with
      -- sent_at null is the queue.
      insert into public.notification_deliveries
        (salon_id, notification_id, channel, provider_status)
      values (p_salon_id, v_row.notification_id, v_next, 'queued');

      update public.notifications
         set status = 'escalated'
       where id = v_row.notification_id;
      v_escalated := v_escalated + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'escalated', v_escalated, 'exhausted', v_exhausted);
end;
$$;

comment on function app.escalate_due_deliveries is
  'Automation K, one salon at a time. Promotes a delivery that is UNACKED past its window - never one that FCM merely failed to confirm, and never one that was acked. Escalating on FCM''s response instead would either never escalate or always escalate, and the second spends the salon''s money on every single message.';

-- FCM said UNREGISTERED: the token is dead now, so the next send escalates
-- immediately instead of waiting out a window it can never satisfy (12.3).
create or replace function app.mark_token_dead(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notification_tokens
     set dead_at = now(), updated_at = now()
   where token = p_token and dead_at is null
$$;

select app_admin.close_privileges();
