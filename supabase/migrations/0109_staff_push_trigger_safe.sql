-- 0109 The booking trigger from 0108 must never break the insert it watches.
--
-- 0108's trigger asked app.current_app_role(), which casts request.jwt.claims to
-- jsonb. A session that set the claims to an empty string - a server job, a
-- script - made that cast throw, and the trigger took the BOOKING down with it.
-- A notification is never worth a booking: the trigger now reads the role
-- defensively, and a session with no claims is simply not a customer.

create or replace function app.on_booking_for_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text := nullif(btrim(coalesce(current_setting('request.jwt.claims', true), '')), '');
  v_role   text;
begin
  begin
    v_role := v_claims::jsonb ->> 'app_role';
  exception when others then
    v_role := null;
  end;

  if v_role is distinct from 'customer' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform app.notify_staff(new.salon_id, 'staff_new_booking', 'staff_new_booking',
      jsonb_build_object('customer_id', new.customer_id, 'starts_at', new.starts_at,
                         'booking_id', new.id));
  elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform app.notify_staff(new.salon_id, 'staff_booking_cancelled', 'staff_booking_cancelled',
      jsonb_build_object('customer_id', new.customer_id, 'starts_at', new.starts_at,
                         'booking_id', new.id));
  end if;
  return null;
end;
$$;

revoke all on function app.on_booking_for_staff() from public, anon, authenticated;
