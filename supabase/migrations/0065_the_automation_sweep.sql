-- 0065 One sweep, per salon, that a single bad tenant cannot stall
--
-- ARCHITECTURE 11.2 says scans are tenant-sharded: "one job per salon, not one
-- job iterating all salons - so a single bad tenant cannot stall the platform."
-- A cron entry per salon delivers that literally, and costs a `cron.job` row per
-- salon plus a provisioning step that can silently not happen.
--
-- This keeps the property and drops the bookkeeping: ONE schedule, iterating
-- salons, with each salon's work inside its own exception block. A salon whose
-- data is broken fails alone, is logged, and the loop carries on - which is the
-- outcome the sharding was for. If a salon ever needs its own cadence, it gets
-- its own schedule then, for that reason rather than pre-emptively.
--
-- Also: `next_channel` returned bare string literals for an enum return type,
-- which plpgsql_check flagged as a type mismatch. It worked by implicit
-- coercion. It is now explicit, because the next person to read it should not
-- have to know that rule.

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
    return 'rcs'::public.message_channel;
  end if;

  if p_category = 'transactional' then
    -- WhatsApp Utility is CHEAPER than SMS (Rs 0.17 vs Rs 0.22), which is the
    -- fact that surprises people and decides this order.
    if coalesce(v_whatsapp_ok, false) and not ('whatsapp' = any(p_tried)) then
      return 'whatsapp'::public.message_channel;
    end if;
    if not ('sms' = any(p_tried)) then
      return 'sms'::public.message_channel;
    end if;
    return null;
  end if;

  -- Marketing: SMS by default, because WhatsApp Marketing is six times the
  -- price of SMS and it is the SALON's money. WhatsApp only if the owner has
  -- said so explicitly.
  if not ('sms' = any(p_tried)) then
    return 'sms'::public.message_channel;
  end if;
  if (v_prefs ->> 'marketing_escalation') = 'whatsapp'
     and coalesce(v_whatsapp_ok, false)
     and not ('whatsapp' = any(p_tried)) then
    return 'whatsapp'::public.message_channel;
  end if;

  return null;
end;
$$;

comment on function app.next_channel is
  'The ladder (ARCHITECTURE 12.2), per salon and per category. A salon with no approved WhatsApp templates and no verified RCS agent still works completely. Marketing escalates to SMS, not to WhatsApp Marketing at 6x the price, unless the owner has opted in.';

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
  v_failed    integer := 0;
  v_result  jsonb;
begin
  for v_salon in
    select s.id from public.salons s where s.status in ('active', 'grace')
  loop
    begin
      -- Automation K: promote anything unacked past its window.
      v_result := app.escalate_due_deliveries(v_salon.id);
      v_escalated := v_escalated + coalesce((v_result ->> 'escalated')::integer, 0);

      -- Automation L: expire what is due, and warn once about what is close.
      v_result := app.expire_due_bonus_lots(v_salon.id);
      v_expired := v_expired + coalesce((v_result ->> 'lots_expired')::integer, 0);

      v_result := app.nudge_expiring_bonus(v_salon.id, p_nudge_days);
      v_nudged := v_nudged + coalesce((v_result ->> 'nudged')::integer, 0);
    exception when others then
      -- **This block is the whole point.** One salon's bad data must not stop
      -- every other salon's reminders and expiries, and it must not be silent
      -- either: the error is recorded and the loop continues.
      v_failed := v_failed + 1;
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (v_salon.id, 'automation.failed', null,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok', true, 'escalated', v_escalated, 'expired', v_expired,
    'nudged', v_nudged, 'salons_failed', v_failed);
end;
$$;

comment on function app.run_due_automations is
  'Automations K and L across every live salon, each inside its own exception block: a salon whose data is broken fails ALONE, is recorded as automation.failed, and the loop carries on. That is the property ARCHITECTURE 11.2 wanted from per-salon jobs, without a cron row per salon that provisioning could forget to create.';

select app_admin.close_privileges();
