-- 0068 The dispatcher was calling functions PostgREST cannot see
--
-- `dispatch-notifications` calls `claim_notification_batch`, `record_send`,
-- `escalate_due_deliveries` and `mark_token_dead` over PostgREST. All four live
-- in schema `app`, and PostgREST exposes `public` - so every one of them was a
-- "function not found", the function returned 500, and no message was ever
-- sent. The functions themselves were correct: called directly over SQL they do
-- exactly what the gate says they do.
--
-- That is why the gate stayed green through two real send attempts. pgTAP runs
-- as a database session, where `app.claim_notification_batch(...)` resolves
-- fine. **The transport was never exercised**, and the transport was the broken
-- part. A gate that tests a function by calling it the way no caller calls it
-- is testing something adjacent to the thing that ships.
--
-- These wrappers follow the pattern the OTP functions already use (0024): a
-- thin `public` entry point, revoked from `anon` and `authenticated`, granted
-- to `service_role` only. A customer must not be able to claim a batch, mark a
-- token dead, or record a send - those are the dispatcher's, and the dispatcher
-- holds the secret key.

create or replace function public.claim_notification_batch(
  p_salon_id uuid,
  p_limit    integer default 50
)
returns table (
  delivery_id     uuid,
  notification_id uuid,
  channel         public.message_channel,
  customer_id     uuid,
  token           text,
  platform        text,
  body            text,
  purpose         text
)
language sql
security definer
set search_path = ''
as $$
  select * from app.claim_notification_batch(p_salon_id, p_limit)
$$;

create or replace function public.record_send(
  p_delivery_id  uuid,
  p_status       text,
  p_provider_message_id text default null,
  p_failure_reason text default null,
  p_cost_paise   bigint default 0
)
returns void
language sql
security definer
set search_path = ''
as $$
  select app.record_send(p_delivery_id, p_status, p_provider_message_id,
                         p_failure_reason, p_cost_paise)
$$;

create or replace function public.escalate_due_deliveries(p_salon_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select app.escalate_due_deliveries(p_salon_id)
$$;

create or replace function public.mark_token_dead(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  select app.mark_token_dead(p_token)
$$;

comment on function public.claim_notification_batch is
  'PostgREST entry point for the dispatcher (0068). The work is in app.*; this exists because PostgREST exposes `public` and nothing else, and calling an app.* function over the API silently fails. Service role only - a customer claiming a batch would be reading every other customer''s messages.';

-- The dispatcher holds the secret key. Nobody else may call any of these: a
-- customer who could mark a token dead could stop their own reminders, and one
-- who could record a send could make a message look delivered.
revoke all on function public.claim_notification_batch(uuid, integer) from public, anon, authenticated;
revoke all on function public.record_send(uuid, text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.escalate_due_deliveries(uuid) from public, anon, authenticated;
revoke all on function public.mark_token_dead(text) from public, anon, authenticated;

grant execute on function public.claim_notification_batch(uuid, integer) to service_role;
grant execute on function public.record_send(uuid, text, text, text, bigint) to service_role;
grant execute on function public.escalate_due_deliveries(uuid) to service_role;
grant execute on function public.mark_token_dead(text) to service_role;
