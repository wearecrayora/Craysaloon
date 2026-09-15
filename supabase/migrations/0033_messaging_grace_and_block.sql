-- 0033 Messaging grace period, then the salon is blocked
--
-- After a salon's messaging trial (0032) ends, the operator can grant a grace
-- period of any length. When that ends - or when the trial ends and no grace
-- was granted - a salon that STILL has no Message Central account of its own
-- is BLOCKED.
--
-- This reverses decision 2 of 0032, which kept customers logging in on
-- Crayora's account indefinitely after a trial. The owner's instruction: trial,
-- then an optional grace, then block.
--
-- WHAT BLOCKED MEANS
--
--   * no new customer can join   - resolve_join_code and start_join treat the
--                                  salon as if it were not active;
--   * no OTP is sent             - so no new logins, for customers or staff;
--   * no writes                  - app.salon_writable() is false, and every
--                                  INSERT/UPDATE policy in the schema goes
--                                  through it.
--
-- WHAT BLOCKED DELIBERATELY DOES NOT MEAN
--
--   * Reads. No SELECT policy checks salon status, and that is kept. A
--     customer already logged in can still SEE their wallet balance - money
--     they paid, which the salon still owes them under PRD 16A. Hiding it
--     would turn a commercial dispute between Crayora and the salon into
--     customers being unable to see their own money.
--   * Consent withdrawal. consents_customer_insert does not go through
--     salon_writable, on purpose: DPDP requires withdrawal to work at all
--     times. The gate asserts it stays that way.
--   * Status. The salon stays `active`. `suspended` starts the 90-day road to
--     purging its data (ARCHITECTURE 13), and a salon that has not set up
--     Message Central yet does not belong on that road.
--
-- HOW IT ENDS
--
-- The block is a CONDITION computed from dates, not an event fired by a job:
-- it takes effect at exactly the deadline, with no scheduler that can fail to
-- run, and it lifts the moment the salon's own Message Central account is
-- entered - which is the thing the whole sequence exists to get done.

alter table public.subscriptions
  add column messaging_grace_ends_at timestamptz;

comment on column public.subscriptions.messaging_grace_ends_at is
  'After the messaging trial, the operator may grant grace until this moment (0033). Crayora still sends the salon''s OTPs meanwhile. When trial and grace have both ended and the salon has no Message Central account of its own, it is blocked.';

-- ---------------------------------------------------------------------------
-- One definition of a salon's messaging state, used everywhere
-- ---------------------------------------------------------------------------
--
--   own       the salon's own Message Central account is stored and not
--             known-bad. Never blocked by this mechanism.
--   trial     Crayora pays, on purpose (0032).
--   grace     Crayora still pays, on purpose, with a deadline (0033).
--   blocked   a trial or grace existed, every period has ended, and there is
--             still no own account.
--   fallback  no own account and no sponsorship was ever granted: Crayora's
--             account as an alerted fault (RULES 7.1.3). Unchanged.

create or replace function app.salon_messaging_state(p_salon uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_own   boolean;
  v_trial timestamptz;
  v_grace timestamptz;
begin
  select exists (
    select 1 from public.salon_integrations
     where salon_id = p_salon and provider = 'message_central'
       and vault_secret_id is not null and status <> 'failing'
  ) into v_own;

  if v_own then
    return 'own';
  end if;

  select messaging_trial_ends_at, messaging_grace_ends_at
    into v_trial, v_grace
    from public.subscriptions where salon_id = p_salon;

  if v_trial is not null and v_trial > now() then return 'trial'; end if;
  if v_grace is not null and v_grace > now() then return 'grace'; end if;

  -- A sponsorship existed and every period of it is over.
  if v_trial is not null or v_grace is not null then
    return 'blocked';
  end if;

  return 'fallback';
end;
$$;

create or replace function app.salon_blocked(p_salon uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.salon_messaging_state(p_salon) = 'blocked'
$$;

revoke all on function app.salon_messaging_state(uuid) from public, anon, authenticated;
revoke all on function app.salon_blocked(uuid) from public, anon, authenticated;
grant execute on function app.salon_messaging_state(uuid) to service_role;
grant execute on function app.salon_blocked(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Writes: the one gate every INSERT/UPDATE policy already calls
-- ---------------------------------------------------------------------------

create or replace function app.salon_writable(p_salon uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.salons s
     where s.id = p_salon
       and s.status = 'active'
  )
  -- 0033: a blocked salon is read-only, whatever its status says.
  and not app.salon_blocked(p_salon)
$$;

-- ---------------------------------------------------------------------------
-- Joins: a blocked salon's code resolves to nothing, like an inactive one
-- ---------------------------------------------------------------------------

create or replace function app.resolve_join_code(
  p_code        text,
  p_device_key  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code  text;
  v_row   record;
begin
  if not app.rate_limit_hit(
       'join_code:' || app.caller_key(p_device_key), 60, interval '1 hour') then
    raise exception 'rate limit exceeded' using errcode = '53400';
  end if;

  v_code := app.normalise_join_code(p_code);
  if v_code is null then
    return null;
  end if;

  select s.id, s.display_name, b.version, b.tokens
    into v_row
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.join_code = v_code
     and s.status = 'active'
     -- 0033: identical to an unknown code, so this is still no oracle.
     and not app.salon_blocked(s.id);

  if v_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'salon_id',         v_row.id,
    'display_name',     v_row.display_name,
    'branding_version', v_row.version,
    'branding',         v_row.tokens
  );
end;
$$;

create or replace function app.start_join(
  p_code       text,
  p_phone      text,
  p_device_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code     text;
  v_salon_id uuid;
  v_hash     bytea;
begin
  v_code := app.normalise_join_code(p_code);

  select id into v_salon_id
    from public.salons
   where join_code = v_code and status = 'active'
     and not app.salon_blocked(id);

  if v_salon_id is null then
    raise exception 'that code is not valid' using errcode = '22023';
  end if;

  v_hash := app.phone_hash(p_phone);

  if not app.rate_limit_hit(
       'join_phone:' || encode(v_hash, 'hex'), 5, interval '1 hour') then
    raise exception 'too many attempts for this number' using errcode = '53400';
  end if;

  if not app.rate_limit_hit(
       'join_caller:' || app.caller_key(p_device_key), 20, interval '1 hour') then
    raise exception 'too many attempts' using errcode = '53400';
  end if;

  if not app.rate_limit_hit(
       'join_salon:' || v_salon_id::text, 500, interval '1 day') then
    raise exception 'this salon has reached its daily join limit'
      using errcode = '53400';
  end if;

  insert into public.join_intents (phone_hash, salon_id, created_at, expires_at)
  values (v_hash, v_salon_id, now(), now() + interval '15 minutes')
  on conflict (phone_hash) do update
    set salon_id = excluded.salon_id,
        created_at = excluded.created_at,
        expires_at = excluded.expires_at;

  return jsonb_build_object('ok', true, 'expires_in_seconds', 900);
end;
$$;

-- ---------------------------------------------------------------------------
-- OTP: no send for a blocked salon, and report the state to the Edge Function
-- ---------------------------------------------------------------------------

alter table public.otp_challenges drop constraint otp_challenges_sender_check;
alter table public.otp_challenges
  add constraint otp_challenges_sender_check
  check (sender in ('salon', 'trial', 'grace', 'platform'));

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
  v_state  text;
begin
  v_hash := app.phone_hash(p_phone);

  v_sender := app.resolve_otp_sender(p_phone);
  if not (v_sender ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  -- Limits first, so even refusals are rate-limited and a blocked salon's
  -- customer list cannot be walked at speed.
  if not app.rate_limit_hit(
       'otp_send_phone:' || encode(v_hash, 'hex'), 3, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  v_caller := coalesce(nullif(trim(coalesce(p_device_key, '')), ''), 'unknown');
  if not app.rate_limit_hit(
       'otp_send_caller:' || v_caller, 10, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  v_state := app.salon_messaging_state((v_sender ->> 'salon_id')::uuid);

  if v_state = 'blocked' then
    -- Nobody is paying for this salon's OTPs any more, so none is sent.
    return jsonb_build_object('ok', false, 'reason', 'salon_blocked');
  end if;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_sender ->> 'salon_id',
    'source', v_sender ->> 'source',
    'mobile', app.canonical_phone(p_phone),
    'country_code', '91',
    'messaging_state', v_state,
    -- Kept for the otp-send already deployed; messaging_state supersedes it.
    'messaging_trial_active', v_state = 'trial'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- The one way to grant or end a grace period
-- ---------------------------------------------------------------------------

create or replace function app_admin.set_messaging_grace(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_days           integer,
  p_reason         text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trial  timestamptz;
  v_before timestamptz;
  v_after  timestamptz;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_days is null or p_days < 0 then
    raise exception 'app_admin: grace days must be zero or more (zero ends it now)';
  end if;
  if p_days > 365 then
    raise exception 'app_admin: a grace period can be at most 365 days - this one asked for %', p_days;
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception
      'app_admin: a grace period needs a reason - when it ends, the salon is blocked';
  end if;

  select messaging_trial_ends_at, messaging_grace_ends_at
    into v_trial, v_before
    from public.subscriptions where salon_id = p_salon_id
   for update;

  if not found then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;

  -- Grace follows the trial. Granted while a trial is still running, it starts
  -- when the trial ends, so "14 days' grace" always means 14 days after the
  -- free period rather than 14 days that quietly overlap it.
  if p_days = 0 then
    v_after := now();
  else
    v_after := greatest(now(), coalesce(v_trial, now())) + make_interval(days => p_days);
  end if;

  update public.subscriptions
     set messaging_grace_ends_at = v_after, updated_at = now()
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id,
    case when p_days = 0 then 'messaging_grace.ended' else 'messaging_grace.granted' end,
    'subscriptions', p_salon_id::text, p_reason,
    jsonb_build_object('messaging_grace_ends_at', v_before),
    jsonb_build_object('messaging_grace_ends_at', v_after, 'days', p_days));

  return v_after;
end;
$$;

select app_admin.close_privileges();
