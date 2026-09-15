-- 0028 OTP challenges - Message Central verifies, the server remembers what it asked
--
-- ADR-36. Message Central VerifyNow generates, sends and verifies the code;
-- Supabase issues a session only after VerifyNow confirms. Between those two
-- calls the server has to remember WHICH verification it started, for WHICH
-- phone, on behalf of WHICH salon. This table is that memory.
--
-- The property that matters: at verify time the client sends only an opaque
-- challenge id and the code it received. It never names the phone or the
-- salon, so it cannot validate a code against a verification it did not
-- start, and it cannot move a login from one salon to another by editing a
-- request.

create table public.otp_challenges (
  id              uuid primary key default extensions.gen_random_uuid(),
  phone_hash      bytea not null,
  salon_id        uuid not null references public.salons(id) on delete cascade,
  -- Message Central's handle for the verification. Never returned to the
  -- client: it is what validateOtp is called with.
  verification_id text not null,
  -- 'salon' normally; 'platform' when the salon's own account failed and the
  -- send fell back to Crayora's (RULES 7.1.3). Recorded so a fallback is
  -- countable, not just logged.
  sender          text not null check (sender in ('salon', 'platform')),
  attempts        int  not null default 0 check (attempts >= 0),
  created_at      timestamptz not null default now(),
  -- VerifyNow's code is short-lived; ten minutes is generous for a person
  -- switching to their messages and back, and short enough that a leaked
  -- challenge id is worthless soon after.
  expires_at      timestamptz not null default now() + interval '10 minutes',
  consumed_at     timestamptz
);

create index otp_challenges_phone_idx  on public.otp_challenges (phone_hash);
create index otp_challenges_expiry_idx on public.otp_challenges (expires_at);

comment on table public.otp_challenges is
  'Server-side memory of an in-flight Message Central verification (ADR-36). No policies and no tenant grants: only the OTP Edge Functions, as service_role, ever touch it.';

-- Same class as join_intents: cross-tenant machinery with no tenant access.
-- Forced RLS with zero policies means a missing grant is not the only thing
-- standing between a tenant and this table.
alter table public.otp_challenges enable row level security;
alter table public.otp_challenges force row level security;
revoke all on public.otp_challenges from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The four calls the Edge Functions make
-- ---------------------------------------------------------------------------
--
-- In `public` because PostgREST only exposes `public`, and the Edge Functions
-- reach the database through it with the service role. EXECUTE is granted to
-- service_role ONLY, and the join-flow gate asserts that anon and
-- authenticated can reach exactly two public functions - so one of these
-- becoming tenant-callable fails CI rather than shipping.

-- 1. May we send? Resolves the salon and applies the send-side limit.
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
  -- Raises on anything that is not a valid Indian mobile.
  v_hash := app.phone_hash(p_phone);

  v_sender := app.resolve_otp_sender(p_phone);
  if not (v_sender ->> 'ok')::boolean then
    -- RULES 7.1.5: no salon context, no send. Nothing downstream runs.
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  -- Every send is real money on a salon's account. Three per ten minutes per
  -- number covers "didn't arrive, tap resend" twice and stops a flood.
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
    'source', v_sender ->> 'source'
  );
end;
$$;

-- 2. Remember the verification Message Central just started.
create or replace function public.otp_record_challenge(
  p_phone           text,
  p_salon_id        uuid,
  p_verification_id text,
  p_sender          text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash bytea;
  v_id   uuid;
begin
  v_hash := app.phone_hash(p_phone);

  -- One live challenge per phone: a resend supersedes the previous one, so an
  -- old challenge id cannot be kept around and ground against.
  update public.otp_challenges
     set consumed_at = now()
   where phone_hash = v_hash and consumed_at is null;

  insert into public.otp_challenges (phone_hash, salon_id, verification_id, sender)
  values (v_hash, p_salon_id, p_verification_id, p_sender)
  returning id into v_id;

  return v_id;
end;
$$;

-- 3. May this code be checked? Counts the attempt BEFORE the check is made,
--    so a caller cannot learn anything from a failed check it was not charged
--    for.
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

  -- Unknown, used, superseded and expired all look identical from outside.
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
    'attempts_left', 4 - v_row.attempts
  );
end;
$$;

-- 4. Message Central said VERIFICATION_COMPLETED. Consume the challenge and
--    hand back what the session must be minted for.
create or replace function public.otp_complete(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.otp_challenges%rowtype;
begin
  update public.otp_challenges
     set consumed_at = now()
   where id = p_challenge_id
     and consumed_at is null
     and expires_at > now()
  returning * into v_row;

  if v_row.id is null then
    -- Already consumed: a second completion for one verification must not
    -- produce a second session.
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_row.salon_id,
    -- The Auth identity is derived from this (ARCHITECTURE 5.2), so
    -- auth.users never holds a plaintext phone number.
    'identity', encode(v_row.phone_hash, 'hex') || '@phone.craysalon.invalid'
  );
end;
$$;

-- 5. The salon's own Message Central credentials, AT THE MOMENT OF USE.
--
-- ARCHITECTURE 8.1: decryption happens only inside an Edge Function holding
-- the service role, at the moment of use. This is that path, and it is the
-- only function in the system that returns a decrypted credential. GATE-7
-- keeps the console and the app from growing a second one.
--
-- Returns null when the salon has no usable Message Central credential - the
-- caller then falls back to Crayora's platform account and alerts.
create or replace function public.otp_salon_sender(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id text;
  v_secret_id   uuid;
  v_status      text;
  v_token       text;
begin
  select public_key_id, vault_secret_id, status::text
    into v_customer_id, v_secret_id, v_status
    from public.salon_integrations
   where salon_id = p_salon_id and provider = 'message_central';

  -- `failing` is deliberately excluded: a credential that has already been
  -- seen to fail should not cost the customer a login attempt to rediscover.
  if v_secret_id is null or v_customer_id is null or v_status = 'failing' then
    return null;
  end if;

  select decrypted_secret into v_token
    from vault.decrypted_secrets where id = v_secret_id;

  if v_token is null then
    return null;
  end if;

  return jsonb_build_object('customer_id', v_customer_id, 'auth_token', v_token);
end;
$$;

comment on function public.otp_salon_sender is
  'The ONE function that returns a decrypted credential, and only to service_role, for the OTP Edge Function at the moment of use (ARCHITECTURE 8.1). Never add a second.';

-- ---------------------------------------------------------------------------
-- Grants: service_role and nobody else
-- ---------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.otp_begin(text, text)',
    'public.otp_record_challenge(text, uuid, text, text)',
    'public.otp_attempt(uuid)',
    'public.otp_complete(uuid)',
    'public.otp_salon_sender(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Guard, at migration time: none of these may be reachable by a tenant role.
do $$
declare
  v_open text;
begin
  select string_agg(p.proname, ', ') into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname like 'otp\_%'
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
       or has_function_privilege('authenticated', p.oid, 'EXECUTE'));

  if v_open is not null then
    raise exception 'OTP machinery reachable by a tenant role: %', v_open;
  end if;
end;
$$;
