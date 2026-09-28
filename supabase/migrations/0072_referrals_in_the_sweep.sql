-- 0072 Automation D joins the sweep, and gets something to say
--
-- 0071 built the release and nothing called it - which is the exact mistake
-- 0066 and 0069 were: a correct function with no caller. Writing the caller in
-- the same session as the function is the cheapest possible fix for that
-- pattern, so this is deliberately not left for later.
--
-- It also seeds the `referral_rewarded` push template. Without one,
-- `render_template` returns null, the dispatcher records `no_template`, and the
-- reward lands silently in a wallet nobody was told about.

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
  v_referred  integer := 0;
  v_failed    integer := 0;
  v_result  jsonb;
begin
  for v_salon in
    select s.id from public.salons s where s.status in ('active', 'grace')
  loop
    begin
      -- Automation A's tail: a reminder that is due becomes a message.
      v_result := app.send_due_reminders(v_salon.id);
      v_reminded := v_reminded + coalesce((v_result ->> 'sent')::integer, 0);

      -- Automation D: a referred customer has paid for their first visit.
      v_result := app.release_due_referrals(v_salon.id);
      v_referred := v_referred + coalesce((v_result ->> 'released')::integer, 0);

      -- Automation K: promote anything unacked past its window.
      v_result := app.escalate_due_deliveries(v_salon.id);
      v_escalated := v_escalated + coalesce((v_result ->> 'escalated')::integer, 0);

      -- Automation L: expire what is due, and warn once about what is close.
      v_result := app.expire_due_bonus_lots(v_salon.id);
      v_expired := v_expired + coalesce((v_result ->> 'lots_expired')::integer, 0);

      v_result := app.nudge_expiring_bonus(v_salon.id, p_nudge_days);
      v_nudged := v_nudged + coalesce((v_result ->> 'nudged')::integer, 0);
    exception when others then
      -- One salon's bad data must not stop every other salon's work, and it
      -- must not be silent either.
      v_failed := v_failed + 1;
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (v_salon.id, 'automation.failed', null,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok', true, 'reminded', v_reminded, 'referrals_released', v_referred,
    'escalated', v_escalated, 'expired', v_expired, 'nudged', v_nudged,
    'salons_failed', v_failed);
end;
$$;

comment on function app.run_due_automations is
  'Automations A (sending), D, K and L across every live salon, each salon inside its own exception block: a salon whose data is broken fails ALONE, is recorded as automation.failed, and the loop carries on.';

-- A reward nobody is told about is a reward that does not retain anybody.
insert into public.message_templates (salon_id, template_key, locale, channel, body)
values
  (null, 'referral_rewarded', 'en', 'push',
   '{{salon}}: your referral reward has been added to your wallet.'),
  (null, 'referral_rewarded', 'hi', 'push',
   '{{salon}}: आपका रेफ़रल इनाम आपके वॉलेट में जुड़ गया है।'),
  (null, 'referral_rewarded', 'hi_Latn', 'push',
   '{{salon}}: aapka referral reward aapke wallet mein jud gaya hai.')
on conflict do nothing;
