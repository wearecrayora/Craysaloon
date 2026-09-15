-- 0029 One normalisation of a phone number, not two
--
-- Message Central wants the bare 10-digit number and a country code. The Edge
-- Function could strip "+91", spaces and leading zeros itself - but that would
-- be a SECOND implementation of the normalisation app.phone_hash already does,
-- and the two would drift. This project has already had two normalisation bugs
-- (0006, 0015), each of which would have let one person bind to two salons.
-- A third, living in TypeScript where the gates cannot see it, is not worth
-- the convenience.
--
-- So the database returns the canonical number, from the same rules, and the
-- OTP gate asserts the two functions agree on which inputs are "the same
-- phone".

create or replace function app.canonical_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digits text;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'phone_hash: empty phone';
  end if;

  -- Identical to app.phone_hash (0015). If you change one, change both - the
  -- consistency assertion in supabase/tests/identity/otp_test.sql will fail
  -- if you do not.
  v_digits := regexp_replace(p_phone, '[^0-9]', '', 'g');
  v_digits := regexp_replace(v_digits, '^0+', '');
  if length(v_digits) = 12 and left(v_digits, 2) = '91' then
    v_digits := right(v_digits, 10);
  end if;
  if v_digits !~ '^[6-9][0-9]{9}$' then
    raise exception 'phone_hash: not a valid Indian mobile number';
  end if;

  return v_digits;
end;
$$;

revoke all on function app.canonical_phone(text) from public, anon, authenticated;
grant execute on function app.canonical_phone(text) to service_role;

-- otp_begin also returns the canonical mobile number for Message Central.
create or replace function public.otp_begin(p_phone text, p_device_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   bytea;
  v_sender jsonb;
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

  if not app.rate_limit_hit(
       'otp_send_caller:' || app.caller_key(p_device_key), 10, interval '10 minutes') then
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

-- otp_attempt also says which account sent the code. A verification can only
-- be validated with the token of the account that started it, so a code sent
-- from Crayora's fallback account must be checked against Crayora's account,
-- not the salon's.
create or replace function public.otp_attempt(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.otp_challenges%rowtype;
begin
  select * into v_row
    from public.otp_challenges
   where id = p_challenge_id
   for update;

  if v_row.id is null
     or v_row.consumed_at is not null
     or v_row.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  if v_row.attempts >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
  end if;

  update public.otp_challenges set attempts = attempts + 1 where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'verification_id', v_row.verification_id,
    'salon_id', v_row.salon_id,
    'sender', v_row.sender,
    'attempts_left', 4 - v_row.attempts
  );
end;
$$;

-- CREATE OR REPLACE keeps the service_role-only grants from 0028.
