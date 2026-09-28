-- 0066 Nothing was sending the reminders
--
-- M8 is called "reminders and push". Automation A schedules a reminder with a
-- `scheduled_for`, the one-per-cycle index keeps it unique, the sweep runs every
-- minute - and **no code anywhere reads `scheduled_for`**. Every reminder this
-- system has ever scheduled would have sat in the table until the heat death of
-- the salon.
--
-- The gate did not catch it because of how the gate was written: it asserts that
-- a visit schedules exactly one reminder, and that a replay schedules none. Both
-- true. Neither says a reminder ever becomes a message. A gate that follows the
-- code it was written beside inherits that code's blind spot, and this is what
-- that looks like.
--
-- Two details that are not incidental:
--
--   * **`opted_out`, not `sent`, when consent says no.** The reminder status
--     enum has carried that value since M1. A customer who refused marketing
--     gets the reminder closed as opted_out, which is both honest and the thing
--     that keeps the conversion rate meaningful - counting suppressed reminders
--     as sent would quietly deflate it.
--   * **`for update skip locked`.** The sweep runs every minute and may overlap
--     itself on a slow salon. Two overlapping runs must not both send.

create or replace function app.send_due_reminders(
  p_salon_id uuid,
  p_limit    integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row       record;
  v_service   text;
  v_notification uuid;
  v_status    public.notification_status;
  v_sent      integer := 0;
  v_opted_out integer := 0;
begin
  for v_row in
    select r.id, r.customer_id, r.service_id
      from public.reminders r
     where r.salon_id = p_salon_id
       and r.status = 'scheduled'
       and r.scheduled_for <= now()
     order by r.scheduled_for
     limit greatest(coalesce(p_limit, 200), 1)
     -- The sweep runs every minute and can overlap itself on a slow salon.
     -- Two overlapping runs must not both send the same reminder.
     for update skip locked
  loop
    select s.name into v_service
      from public.services s where s.id = v_row.service_id;

    -- A reminder is MARKETING (ARCHITECTURE 12.2), so consent decides before a
    -- paisa is spent. app.notify writes the suppression down either way.
    v_notification := app.notify(
      p_salon_id, v_row.customer_id, 'service_due', 'marketing', 'service_due',
      jsonb_build_object('service', coalesce(v_service, ''),
                         'reminder_id', v_row.id));

    select n.status into v_status
      from public.notifications n where n.id = v_notification;

    if v_status = 'suppressed' then
      -- Closed as opted_out rather than sent. Counting a suppressed reminder as
      -- sent would quietly deflate the conversion rate the salon is judged on.
      update public.reminders set status = 'opted_out' where id = v_row.id;
      v_opted_out := v_opted_out + 1;
    else
      update public.reminders set status = 'sent' where id = v_row.id;
      v_sent := v_sent + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'sent', v_sent, 'opted_out', v_opted_out);
end;
$$;

comment on function app.send_due_reminders is
  'Turns a due reminder into a message. Idempotent through the status transition out of `scheduled`, and `for update skip locked` so two overlapping sweeps cannot both send one. A customer who refused marketing closes the reminder as opted_out, never as sent.';

-- ---------------------------------------------------------------------------
-- Into the sweep
-- ---------------------------------------------------------------------------

create or replace function app.run_due_automations(p_nudge_days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   record;
  v_escalated integer := 0;
  v_expired   integer := 0;
  v_nudged    integer := 0;
  v_reminded  integer := 0;
  v_failed    integer := 0;
  v_result  jsonb;
begin
  for v_salon in
    select s.id from public.salons s where s.status in ('active', 'grace')
  loop
    begin
      -- Automation A's tail: a reminder that is due becomes a message. Without
      -- this the whole reminder loop schedules and never fires (0066).
      v_result := app.send_due_reminders(v_salon.id);
      v_reminded := v_reminded + coalesce((v_result ->> 'sent')::integer, 0);

      -- Automation K: promote anything unacked past its window.
      v_result := app.escalate_due_deliveries(v_salon.id);
      v_escalated := v_escalated + coalesce((v_result ->> 'escalated')::integer, 0);

      -- Automation L: expire what is due, and warn once about what is close.
      v_result := app.expire_due_bonus_lots(v_salon.id);
      v_expired := v_expired + coalesce((v_result ->> 'lots_expired')::integer, 0);

      v_result := app.nudge_expiring_bonus(v_salon.id, p_nudge_days);
      v_nudged := v_nudged + coalesce((v_result ->> 'nudged')::integer, 0);
    exception when others then
      -- One salon's bad data must not stop every other salon's reminders and
      -- expiries, and it must not be silent either.
      v_failed := v_failed + 1;
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (v_salon.id, 'automation.failed', null,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok', true, 'reminded', v_reminded, 'escalated', v_escalated,
    'expired', v_expired, 'nudged', v_nudged, 'salons_failed', v_failed);
end;
$$;

comment on function app.run_due_automations is
  'Automations A (the sending half), K and L across every live salon, each inside its own exception block: a salon whose data is broken fails ALONE, is recorded as automation.failed, and the loop carries on.';

select app_admin.close_privileges();
