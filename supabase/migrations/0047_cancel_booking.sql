-- 0047 Cancelling a booking (M6)
--
-- The third of the three writes the day view needs, and the one that frees the
-- chair: the exclusion constraint only counts `pending` and `confirmed`, so a
-- cancelled booking releases its slot the moment its status changes.
--
-- Who may cancel: the salon, or the customer whose booking it is. A customer
-- cancelling their own appointment is the normal case and does not need a phone
-- call - but the booking is resolved from the database (app.current_customer_id),
-- never from the request, so "their own" cannot be claimed.
--
-- What this deliberately does NOT do: charge anything. `salons.cancellation_policy`
-- exists and a late-cancellation fee would be money moving, which is M7's
-- business and never a device's (RULES 5). Cancelling here changes a status and
-- records who did it.

create or replace function public.cancel_booking(
  p_client_action_id uuid,
  p_booking_id       uuid,
  p_reason           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_role     text := app.current_app_role();
  v_customer uuid;
  v_booking  record;
  v_prior    jsonb;
  v_result   jsonb;
begin
  if v_salon is null then
    raise exception 'cancel_booking: no salon in session' using errcode = '42501';
  end if;
  if p_client_action_id is null then
    raise exception 'cancel_booking: a client_action_id is required (RULES 9.3)';
  end if;

  select k.result into v_prior
    from public.idempotency_keys k
   where k.salon_id = v_salon and k.key = p_client_action_id;
  if v_prior is not null then
    return v_prior;
  end if;

  select b.id, b.customer_id, b.status
    into v_booking
    from public.bookings b
   where b.id = p_booking_id and b.salon_id = v_salon
   for update;

  if v_booking.id is null then
    raise exception 'cancel_booking: no such booking here' using errcode = '42501';
  end if;

  if v_role = 'customer' then
    v_customer := app.current_customer_id();
    if v_booking.customer_id is distinct from v_customer then
      -- Not "no such booking": it exists, it is simply not theirs. The message
      -- names no other customer.
      raise exception 'cancel_booking: that booking is not yours' using errcode = '42501';
    end if;
  elsif v_role not in ('owner', 'manager', 'staff') then
    raise exception 'cancel_booking: this account cannot cancel' using errcode = '42501';
  end if;

  -- A completed visit is history and is not cancelled away; a booking already
  -- cancelled is simply cancelled (the offline queue will deliver this twice).
  if v_booking.status = 'completed' then
    return jsonb_build_object('ok', false, 'reason', 'already_completed');
  end if;
  if v_booking.status = 'cancelled' then
    return jsonb_build_object('ok', true, 'booking_id', p_booking_id, 'already', true);
  end if;

  update public.bookings
     set status = 'cancelled',
         cancelled_at = now(),
         cancel_reason = nullif(btrim(coalesce(p_reason, '')), ''),
         updated_at = now()
   where id = p_booking_id;

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'booking.cancelled', p_booking_id,
          jsonb_build_object('customer_id', v_booking.customer_id, 'by_role', v_role));

  v_result := jsonb_build_object('ok', true, 'booking_id', p_booking_id, 'already', false);

  insert into public.idempotency_keys (salon_id, key, operation, result)
  values (v_salon, p_client_action_id, 'cancel_booking', v_result);

  return v_result;
end;
$$;

comment on function public.cancel_booking is
  'Frees the chair: the exclusion constraint counts only pending and confirmed, so a cancelled booking releases its slot immediately. The salon, or the customer whose booking it is - resolved from the database, never claimed in the request. Charges nothing: a cancellation fee is money, and money is M7''s and never a device''s.';

revoke all on function public.cancel_booking(uuid, uuid, text) from public, anon;
grant execute on function public.cancel_booking(uuid, uuid, text) to authenticated;
