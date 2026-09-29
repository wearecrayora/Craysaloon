-- 0086 "Your bill is ready", and the owner sees every start without a code
--
-- The last two pieces of the start-and-pay flow (0084, 0085):
--
--   * When the stylist marks the work complete, a customer who has the app is
--     told the bill is ready. Only a customer WITH the app: one without it is
--     standing at the counter, and an SMS would be the salon's money spent to
--     tell them what they can see.
--   * That message NEVER escalates to a paid channel. It is a convenience for
--     someone in the room; five minutes later they have paid or gone. Every
--     other transactional message escalates when unacked - this one is the
--     exception, and escalation_window says so by returning NULL, which the
--     sweep's comparison can never satisfy.
--   * The owner's dashboard counts starts without the code, with the reason.
--     "Required when possible" is only a control if someone can see the
--     exceptions (decision of 29 Sep 2026).
--
-- All three existing functions are rewritten from their LIVE definitions, one
-- asserted fragment each, as in 0084 and 0085.

-- ---------------------------------------------------------------------------
-- 1. The message, in all three languages
-- ---------------------------------------------------------------------------

insert into public.message_templates (salon_id, template_key, locale, channel, body)
values
  (null, 'visit_completed', 'en', 'push',
   '{{salon}}: all done. Your bill is ready - pay from the app, or at the counter.'),
  (null, 'visit_completed', 'hi', 'push',
   '{{salon}}: सर्विस पूरी हुई। आपका बिल तैयार है - ऐप से या काउंटर पर भुगतान करें।'),
  (null, 'visit_completed', 'hi_Latn', 'push',
   '{{salon}}: service poori hui. Aapka bill taiyaar hai - app se ya counter par payment karein.')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. It never escalates
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'escalation_window';

  v_new := replace(v_def,
    $x$    else interval '1 hour'$x$,
    $x$    -- NULL: never escalates. The customer is in the room; an SMS five
    -- minutes later is the salon's money spent on someone who has already
    -- paid or already left (0086).
    when 'visit_completed'   then null
    else interval '1 hour'$x$);
  if v_new = v_def then
    raise exception '0086: escalation_window''s default was not where expected';
  end if;
  execute v_new;
end;
$$;

-- ...and the dispatcher never OPENS a paid rung for it either. Without this, a
-- customer whose token died between the notice and the dispatch would get it
-- by SMS as the FIRST rung - no escalation needed to spend the salon's money.
-- A message whose window is "never" is push or nothing.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'claim_notification_batch';

  v_new := replace(v_def,
    $x$     and (t.token is not null
          or app.next_channel(n.salon_id, n.category, '{push}') is not null)$x$,
    $x$     and (t.token is not null
          -- Push-only purposes (window NULL, 0086) never open a paid rung.
          or (app.escalation_window(n.purpose) is not null
              and app.next_channel(n.salon_id, n.category, '{push}') is not null))$x$);
  if v_new = v_def then
    raise exception '0086: claim_notification_batch''s first-rung filter was not where expected';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Mark-complete tells a customer with the app
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mark_visit_complete';

  v_new := replace(v_def,
    $x$  perform app.on_visit_completed(v_visit);$x$,
    $x$  perform app.on_visit_completed(v_visit);

  -- The bill is ready (0086) - for a customer whose phone can take a PUSH. One
  -- without the app, or with notifications off, is at the counter already, and
  -- any other channel would be the salon's money spent for nothing. Created
  -- only on the path that made the visit, so a replay tells nobody twice.
  if exists (select 1 from public.notification_tokens nt
              where nt.customer_id = v_booking.customer_id and nt.dead_at is null) then
    perform app.notify(v_salon, v_booking.customer_id, 'visit_completed', 'transactional',
                       'visit_completed', jsonb_build_object('visit_id', v_visit));
  end if;$x$);
  if v_new = v_def then
    raise exception '0086: mark_visit_complete''s automation call was not where expected';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The owner sees every start without the code
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_dashboard';

  v_new := replace(v_def,
    $x$    'drift_days', coalesce(($x$,
    $x$    -- Starts WITHOUT the customer's code, and why (0084). "Required when
    -- possible" is a control only because this is visible.
    'start_exceptions', jsonb_build_object(
      'today', (select count(*) from public.bookings b
                 where b.salon_id = v_salon and b.start_method = 'without_code'
                   and app.salon_day(v_salon, b.started_at) = v_today),
      'month', (select count(*) from public.bookings b
                 where b.salon_id = v_salon and b.start_method = 'without_code'
                   and app.salon_day(v_salon, b.started_at) >= v_month),
      'with_code_month', (select count(*) from public.bookings b
                 where b.salon_id = v_salon and b.start_method = 'code'
                   and app.salon_day(v_salon, b.started_at) >= v_month),
      'by_reason', coalesce((
        select jsonb_object_agg(x.start_note, x.n) from (
          select b.start_note, count(*) as n from public.bookings b
           where b.salon_id = v_salon and b.start_method = 'without_code'
             and app.salon_day(v_salon, b.started_at) >= v_month
           group by b.start_note) x), '{}'::jsonb)),

    'drift_days', coalesce(($x$);
  if v_new = v_def then
    raise exception '0086: owner_dashboard''s drift field was not where expected';
  end if;
  execute v_new;
end;
$$;
