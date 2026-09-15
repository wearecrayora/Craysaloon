-- 0030 Rate-limit OTP sends by the CUSTOMER's address, not the Edge Function's
--
-- FOUND WHILE WRITING THE EDGE FUNCTION THAT CALLS THIS - AND PROVEN BEFORE
-- BEING FIXED.
--
-- app.caller_key() identifies a caller by the x-forwarded-for header PostgREST
-- records. That is right for resolve_join_code and start_join, which the APP
-- calls directly: the header carries the customer's address.
--
-- otp_begin is different. It is service_role-only, so it is only ever called
-- by the otp-send Edge Function, and the header PostgREST records is the
-- FUNCTION's egress address. Reproduced with a simulated header:
--
--     request.headers = {"x-forwarded-for": "10.0.0.99"}   -- the Edge Function
--     otp_begin(phone, 'customer-ip-203.0.113.7')          -- the real customer
--     -> bucket used: otp_send_caller:10.0.0.99
--
-- Every customer in the country would have shared ONE bucket of ten sends per
-- ten minutes. Login would have worked in testing, where there is one tester,
-- and stopped working for everybody on the first busy morning.
--
-- The Edge Function reads the customer's address from its own incoming
-- request and passes it explicitly. Because only service_role can call this,
-- that value comes from our own code and can be trusted here in a way a
-- client-supplied key never could.

create or replace function public.otp_begin(p_phone text, p_device_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   bytea;
  v_sender jsonb;
  v_caller text;
begin
  v_hash := app.phone_hash(p_phone);

  v_sender := app.resolve_otp_sender(p_phone);
  if not (v_sender ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  if not app.rate_limit_hit(
       'otp_send_phone:' || encode(v_hash, 'hex'), 3, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  -- NOT app.caller_key(): see above. The explicit key is the customer's
  -- address as seen by the Edge Function. If it is missing, fail towards a
  -- shared bucket rather than no limit at all.
  v_caller := coalesce(nullif(trim(coalesce(p_device_key, '')), ''), 'unknown');

  if not app.rate_limit_hit(
       'otp_send_caller:' || v_caller, 10, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_sender ->> 'salon_id',
    'source', v_sender ->> 'source',
    'mobile', app.canonical_phone(p_phone),
    'country_code', '91'
  );
end;
$$;

comment on function public.otp_begin is
  'Called ONLY by the otp-send Edge Function. p_device_key must be the customer''s address from the function''s incoming request - app.caller_key() would see the function''s own address and put every customer in one bucket (0030).';
