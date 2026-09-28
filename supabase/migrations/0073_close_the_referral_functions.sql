-- 0073 The new ledger caller was executable by PUBLIC
--
-- `CREATE FUNCTION` grants EXECUTE to PUBLIC, and `ALTER DEFAULT PRIVILEGES`
-- does not stick on this database (0020) - so every function in `app` has to be
-- closed by an explicit revoke, which 0048 does for each of the four ledger
-- callers it created. 0071 added the fifth and did not.
--
-- The money gate caught it on the next run: "no device can call any ledger
-- function - not an owner, not a customer". In practice `authenticated` has no
-- USAGE on schema `app` so the call would have failed anyway, but that is a
-- second lock standing in for a missing first one - and the day somebody grants
-- schema usage for an unrelated reason, a customer can pay themselves a
-- referral reward.
--
-- Closed the same way 0048 closes the others, and the gate now names all five.

revoke all on function app.referral_release_reward(uuid) from public, anon, authenticated;
revoke all on function app.release_due_referrals(uuid) from public, anon, authenticated;
revoke all on function app.new_referral_code(uuid) from public, anon, authenticated;

-- The sweep and the other M8 functions have the same exposure for the same
-- reason. Closing them here rather than waiting for a gate to name each one.
revoke all on function app.send_due_reminders(uuid, integer) from public, anon, authenticated;
revoke all on function app.run_due_automations(integer) from public, anon, authenticated;
revoke all on function app.escalate_due_deliveries(uuid) from public, anon, authenticated;
revoke all on function app.expire_due_bonus_lots(uuid) from public, anon, authenticated;
revoke all on function app.nudge_expiring_bonus(uuid, integer) from public, anon, authenticated;
revoke all on function app.claim_notification_batch(uuid, integer) from public, anon, authenticated;
revoke all on function app.record_send(uuid, text, text, text, bigint) from public, anon, authenticated;
revoke all on function app.mark_token_dead(text) from public, anon, authenticated;
revoke all on function app.notify(uuid, uuid, text, public.message_category, text, jsonb)
  from public, anon, authenticated;
revoke all on function app.on_visit_completed(uuid) from public, anon, authenticated;
revoke all on function app.on_booking_confirmed(uuid) from public, anon, authenticated;
revoke all on function app.render_template(uuid, text, text, public.message_channel, jsonb)
  from public, anon, authenticated;
revoke all on function app.next_channel(uuid, public.message_category, public.message_channel[])
  from public, anon, authenticated;
revoke all on function app.wallet_bonus_for(jsonb, bigint) from public, anon, authenticated;
revoke all on function app.escalation_window(text) from public, anon, authenticated;
