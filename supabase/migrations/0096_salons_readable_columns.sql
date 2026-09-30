-- 0096 What a salon's own users may read of the salon row.
--
-- salons_select lets any signed-in user of a salon read its row - owner,
-- stylist AND customer - and the table-level SELECT grant exposed every
-- column. Among them:
--   * webhook_token - the path Razorpay posts to. It identifies rather than
--     authorises (the signature does that, 0049), but it is deliberately not
--     published, and a customer had no business reading it;
--   * activated_by, purged_by - Crayora operators' ids;
--   * the offboarding record: export_offered_*, credit_settled_*, purged_at.
-- Found 30 Sep 2026 while building the owner's read-only Rules and Hours
-- screens. Nothing in the app, console or Edge Functions reads these through
-- the API: the console connects as postgres, and every function is a definer.
--
-- So: table SELECT goes, and SELECT comes back on the business columns only.
-- A column added later is unreadable until someone decides it should be read.

revoke select on public.salons from authenticated;

grant select (
  id, legal_name, display_name, join_code, status,
  address, phone, email, timezone, languages,
  gst_number, gst_rate_bp,
  working_hours, cancellation_policy,
  wallet_rule, reward_rule, loyalty_rule,
  default_reminder_cycle_days, notification_prefs,
  grievance_name, grievance_email, grievance_phone,
  activated_at, created_at, updated_at
) on public.salons to authenticated;
