-- 0050 The order id Razorpay gave us, on the payment we created
--
-- Two ids exist for one top-up: ours (`payments.id`, created before anyone pays)
-- and Razorpay's order id (created when we ask them to collect). The webhook
-- arrives carrying THEIRS, so the link has to be stored when the order is made -
-- otherwise the only way back to our row is the amount, which is not an
-- identifier.
--
-- Deliberately narrow: it attaches an order id to a payment still in `created`
-- and does nothing else. It cannot capture, cannot change an amount, and refuses
-- a payment that has already moved on.

create or replace function app.attach_payment_order(
  p_payment_id uuid,
  p_order_id   text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if coalesce(btrim(p_order_id), '') = '' then
    raise exception 'attach_payment_order: an order id is required';
  end if;

  update public.payments
     set razorpay_order_id = p_order_id
   where id = p_payment_id
     and status = 'created'
     -- Idempotent: the same order id may be attached again (a retried order
     -- creation), but a DIFFERENT one may not overwrite it. Two orders for one
     -- payment would mean two ways to pay it.
     and (razorpay_order_id is null or razorpay_order_id = p_order_id);

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

comment on function app.attach_payment_order is
  'Links Razorpay''s order id to the payment we created, so the webhook can find its way back to our row. Refuses to replace a DIFFERENT order id: two orders for one payment would be two ways to pay it.';

revoke all on function app.attach_payment_order(uuid, text) from public, anon, authenticated;
grant execute on function app.attach_payment_order(uuid, text) to service_role;
