-- 0079 Checkout by BOOKING, so it can be queued offline
--
-- `checkout_visit` (0069) takes a visit id. Offline, the app does not have one:
-- the visit is created by `mark_visit_complete`, which is itself sitting in the
-- outbox waiting for a connection. So the owner who marks a haircut done and
-- takes ₹450 in cash, on salon wifi that has dropped, had no way to record the
-- payment until they were back online - and a visit that stays `unpaid` never
-- releases a referral reward and never reaches the dashboard's takings.
--
-- RULES 9.5 describes exactly the shape this needs: "an offline completion
-- records INTENT. The wallet debit ... runs server-side at sync." The device
-- queues the intent; the money moves on the server when it arrives, never on
-- the phone. The outbox drains in order, so the mark-complete queued before
-- this has already created the visit by the time this runs - and if it has not
-- (a completion that was refused), this refuses too, into Needs attention.
--
-- This is also the caller `checkout_visit` never had: the orphan check lists it
-- as unreachable until something that ships calls it, and this is that thing.

create or replace function public.checkout_booking(
  p_client_action_id uuid,
  p_booking_id       uuid,
  p_use_wallet       boolean default true,
  p_other_method     public.payment_method default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid := app.current_salon_id();
  v_visit uuid;
begin
  -- The role is checked again inside checkout_visit; checking it here too means
  -- a customer is refused before anything about the booking is looked up.
  if app.current_app_role() not in ('owner', 'manager', 'staff') then
    raise exception 'checkout_booking: only the salon may take payment'
      using errcode = '42501';
  end if;

  select v.id into v_visit
    from public.visits v
   where v.booking_id = p_booking_id and v.salon_id = v_salon;

  if v_visit is null then
    -- Not completed - or the completion was refused and is sitting in Needs
    -- attention. Money cannot be taken for a visit that did not happen.
    return jsonb_build_object('ok', false, 'reason', 'not_completed');
  end if;

  return public.checkout_visit(v_visit, p_client_action_id, p_use_wallet, p_other_method);
end;
$$;

comment on function public.checkout_booking is
  'Settles the visit a booking became. By BOOKING because offline the app has no visit id yet - mark-complete is queued ahead of this in the same outbox (RULES 9.5: offline records intent, money moves server-side at sync). Refuses a booking that was never completed.';

revoke all on function public.checkout_booking(uuid, uuid, boolean, public.payment_method)
  from public, anon;
grant execute on function public.checkout_booking(uuid, uuid, boolean, public.payment_method)
  to authenticated;
