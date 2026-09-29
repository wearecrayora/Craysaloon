-- 0078 The Razorpay webhook could never credit a wallet
--
-- `rzp-webhook` calls `webhook_seen` and `record_payment_captured` over
-- PostgREST. `create-payment-order` calls `attach_payment_order`. All three live
-- in schema `app`, and PostgREST exposes only `public` - so every one of those
-- calls has always returned "function not found".
--
-- What that would have done with real money, in order:
--
--   1. `webhook_seen` fails, its result is null, and the webhook carries on -
--      so DEDUPE WAS SILENTLY OFF.
--   2. `record_payment_captured` fails, the webhook alerts and answers 500, and
--      Razorpay retries for about a day and then gives up.
--   3. The customer has paid. The money is in the salon's Razorpay account.
--      **Their wallet is never credited.**
--
-- It has not happened only because no salon has Razorpay credentials yet.
--
-- This is 0068's bug exactly - the dispatcher calling app.* over PostgREST -
-- and I fixed that one without sweeping the other Edge Functions for the same
-- shape. When a bug has a shape, the fix is not done until the shape has been
-- searched for. `scripts/db/orphan-check.mjs` found these, by refusing to count
-- an app.* name in the repo as a caller: PostgREST cannot see it, so it is not
-- one. It now also fails outright on any rpc('x') where x exists only outside
-- `public`.
--
-- Same wrappers as 0068: thin, `public`, service role only. A customer who
-- could call record_payment_captured could tell the ledger they had paid.

create or replace function public.webhook_seen(
  p_provider text,
  p_event_id text,
  p_salon_id uuid,
  p_payload  jsonb
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select app.webhook_seen(p_provider, p_event_id, p_salon_id, p_payload)
$$;

create or replace function public.record_payment_captured(
  p_payment_id     uuid,
  p_rzp_payment_id text,
  p_amount_paise   bigint
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select app.record_payment_captured(p_payment_id, p_rzp_payment_id, p_amount_paise)
$$;

create or replace function public.attach_payment_order(
  p_payment_id uuid,
  p_order_id   text
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select app.attach_payment_order(p_payment_id, p_order_id)
$$;

comment on function public.record_payment_captured is
  'PostgREST entry point for rzp-webhook (0078). The work is in app.record_payment_captured, which re-verifies the amount against the payment row we created. Service role only: a customer who could call this could tell the ledger they had paid.';

revoke all on function public.webhook_seen(text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.record_payment_captured(uuid, text, bigint) from public, anon, authenticated;
revoke all on function public.attach_payment_order(uuid, text) from public, anon, authenticated;

grant execute on function public.webhook_seen(text, text, uuid, jsonb) to service_role;
grant execute on function public.record_payment_captured(uuid, text, bigint) to service_role;
grant execute on function public.attach_payment_order(uuid, text) to service_role;
