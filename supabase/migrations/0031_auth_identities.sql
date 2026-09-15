-- 0031 The server only adopts Auth accounts it created itself
--
-- FOUND BY READING THE LIVE PROJECT'S AUTH SETTINGS INSTEAD OF config.toml.
--
-- The session for a phone number is minted for a synthetic Auth identity,
-- `<hex of phone_hash>@phone.craysalon.invalid` (ADR-36). The obvious
-- implementation - "create it, or if it already exists, use it" - has a hole:
-- whoever created it first owns its password.
--
-- The live project had public sign-up OPEN (config.toml claimed otherwise).
-- So anyone holding the publishable key could create an account at a
-- customer's synthetic address, with a password of their choosing, before the
-- customer ever logged in. On that customer's first real login the server
-- would find the account "already exists", adopt it, and hand the customer a
-- session - on an account the attacker can still sign into by password. That
-- is account pre-hijacking.
--
-- It was blocked by exactly one thing: computing the address needs the pepper,
-- which never leaves the database. Three layers now instead of one:
--
--   1. the pepper (unchanged);
--   2. public sign-up switched off (config.toml, and the live dashboard);
--   3. THIS TABLE. The server records every account it creates. An account
--      that exists at a synthetic address WITHOUT a row here was not made by
--      us, and otp-verify refuses to mint a session for it and alerts.

create table public.auth_identities (
  phone_hash   bytea primary key,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now()
);

comment on table public.auth_identities is
  'Every Auth account the OTP flow created, keyed on the peppered phone hash. The ONLY accounts otp-verify will mint sessions for - an account at a synthetic address with no row here was not created by us (0031).';

alter table public.auth_identities enable row level security;
alter table public.auth_identities force row level security;
revoke all on public.auth_identities from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- otp_complete also reports whether we already own this phone's account
-- ---------------------------------------------------------------------------

create or replace function public.otp_complete(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row  public.otp_challenges%rowtype;
  v_auth uuid;
begin
  update public.otp_challenges
     set consumed_at = now()
   where id = p_challenge_id
     and consumed_at is null
     and expires_at > now()
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  select auth_user_id into v_auth
    from public.auth_identities where phone_hash = v_row.phone_hash;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_row.salon_id,
    'identity', encode(v_row.phone_hash, 'hex') || '@phone.craysalon.invalid',
    -- null means "first login - create the account and record it".
    'auth_user_id', v_auth
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Record an account the OTP flow just created
-- ---------------------------------------------------------------------------
--
-- Keyed on the challenge, not on a hash the caller passes in, so the Edge
-- Function cannot link an account to an arbitrary phone: only to the phone of
-- a challenge that was genuinely verified and consumed a moment ago.

create or replace function public.otp_link_identity(
  p_challenge_id uuid,
  p_auth_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash bytea;
begin
  select phone_hash into v_hash
    from public.otp_challenges
   where id = p_challenge_id
     and consumed_at is not null
     and consumed_at > now() - interval '5 minutes';

  if v_hash is null then
    raise exception 'otp_link_identity: no recently completed challenge %', p_challenge_id;
  end if;

  insert into public.auth_identities (phone_hash, auth_user_id)
  values (v_hash, p_auth_user_id);
end;
$$;

revoke all on function public.otp_complete(uuid) from public, anon, authenticated;
revoke all on function public.otp_link_identity(uuid, uuid) from public, anon, authenticated;
grant execute on function public.otp_complete(uuid) to service_role;
grant execute on function public.otp_link_identity(uuid, uuid) to service_role;
