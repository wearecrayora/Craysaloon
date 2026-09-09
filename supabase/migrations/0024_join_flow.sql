-- 0024 Salon-code-first join flow
--
-- RULES 4.1: the app resolves the code, themes itself, shows the salon's name,
-- and only THEN asks for a phone number. This file is the database half of
-- that - the two public entry points and the sender resolution the SMS hook
-- will call.
--
-- These are the only functions in the system callable by `anon`, so each one
-- is written on the assumption that its caller is hostile.

-- ---------------------------------------------------------------------------
-- Rate limiting
-- ---------------------------------------------------------------------------
--
-- Fixed windows, in Postgres, so a limit shares a transaction with the thing
-- it guards (ARCHITECTURE 6.2). A separate vendor cannot do that: it would
-- allow a request whose transaction then rolls back, or refuse one that
-- succeeded.

create or replace function app.rate_limit_hit(
  p_bucket text,
  p_limit  int,
  p_window interval
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_start timestamptz;
  v_count        int;
begin
  if p_bucket is null or p_limit <= 0 then
    return false;
  end if;

  -- Fixed window: floor now() to the window size. Cheaper than a sliding
  -- window and, for "stop the obvious abuse", accurate enough. Worst case a
  -- caller gets 2x the limit across a boundary, which does not matter for a
  -- limit whose job is to make enumeration impractical.
  v_window_start := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / extract(epoch from p_window))
    * extract(epoch from p_window));

  insert into public.rate_limit_counters (bucket, window_start, count)
  values (p_bucket, v_window_start, 1)
  on conflict (bucket, window_start)
    do update set count = public.rate_limit_counters.count + 1
  returning count into v_count;

  return v_count <= p_limit;
end;
$$;

comment on function app.rate_limit_hit is
  'Records the attempt and returns whether it is allowed. Counts the REFUSED attempts too - a caller being throttled who keeps trying should stay throttled, not reset by being refused.';

-- Best-effort caller identity for anonymous entry points. PostgREST exposes
-- request headers as a GUC; when that is absent (a direct connection, a
-- background job) there is no IP to key on and the caller must supply
-- something. A client-supplied key is spoofable, which is why the per-phone
-- and per-salon limits below do not depend on it.
create or replace function app.caller_key(p_fallback text default null)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_headers json;
  v_ip      text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    v_headers := null;
  end;

  if v_headers is not null then
    -- The left-most entry is the client; the rest are proxies.
    v_ip := split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1);
    v_ip := nullif(trim(v_ip), '');
  end if;

  return coalesce(v_ip, nullif(trim(coalesce(p_fallback, '')), ''), 'unknown');
end;
$$;

-- ---------------------------------------------------------------------------
-- resolve_join_code - the app themes itself before anyone authenticates
-- ---------------------------------------------------------------------------
--
-- Returns display name and the branding token document, and NOTHING else: no
-- counts, no customer data, no contact details, no credentials (ARCHITECTURE
-- 5.6).
--
-- An unknown code and a code belonging to a salon that is not active return
-- the SAME thing - null. Distinguishing them would turn this into an oracle
-- for "which codes exist", which is the enumeration this is rate-limited
-- against in the first place.

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

  -- Case-insensitive on input: the code is read off print and typed by hand.
  v_code := upper(trim(coalesce(p_code, '')));
  if v_code !~ '^CRAY-[A-HJKMNP-Z2-9]{6}$' then
    return null;
  end if;

  select s.id, s.display_name, b.version, b.tokens
    into v_row
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.join_code = v_code
     and s.status = 'active';

  if v_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'salon_id',        v_row.id,
    'display_name',    v_row.display_name,
    'branding_version', v_row.version,
    'branding',        v_row.tokens
  );
end;
$$;

comment on function app.resolve_join_code is
  'The only pre-auth read in the system. Returns display name and branding for an ACTIVE salon; null for anything else, including a code that exists but belongs to a salon in setup - so a leaked QR cannot bind customers before the operator switches the salon on.';

-- ---------------------------------------------------------------------------
-- start_join - records which salon the OTP must come from
-- ---------------------------------------------------------------------------
--
-- Limited far more tightly than a lookup, because unlike a lookup this causes
-- a paid SMS on a salon's own account. Three independent limits, because they
-- fail differently: per phone stops one number being spammed, per caller stops
-- one machine walking many numbers, and per salon per day caps what a single
-- salon can be made to spend.

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
  v_code := upper(trim(coalesce(p_code, '')));

  select id into v_salon_id
    from public.salons
   where join_code = v_code and status = 'active';

  if v_salon_id is null then
    -- Same refusal as a bad code. Do not confirm that a code exists but its
    -- salon is not live.
    raise exception 'that code is not valid' using errcode = '22023';
  end if;

  -- Raises on anything that is not a valid Indian mobile, before any limit is
  -- spent on it.
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
    -- The salon's own money. A cap here is the difference between an incident
    -- and an invoice.
    raise exception 'this salon has reached its daily join limit'
      using errcode = '53400';
  end if;

  -- One live intent per phone. A second attempt replaces the first rather than
  -- accumulating, and re-arms the 15-minute window.
  insert into public.join_intents (phone_hash, salon_id, created_at, expires_at)
  values (v_hash, v_salon_id, now(), now() + interval '15 minutes')
  on conflict (phone_hash) do update
    set salon_id = excluded.salon_id,
        created_at = excluded.created_at,
        expires_at = excluded.expires_at;

  -- Nothing about the phone or the salon beyond what the caller already sent.
  return jsonb_build_object('ok', true, 'expires_in_seconds', 900);
end;
$$;

comment on function app.start_join is
  'Records the pre-auth intent so the OTP is sent from the right salon''s Message Central account. Rate-limited per phone, per caller and per salon per day - the last one caps what a salon can be made to spend.';

-- ---------------------------------------------------------------------------
-- resolve_otp_sender - which salon pays for this OTP
-- ---------------------------------------------------------------------------
--
-- Called by the sms-hook Edge Function. The order is intent → binding → staff
-- → REFUSE, and the refusal is the important part: PHASES M3 requires that an
-- OTP request with no salon context is refused, not quietly sent from
-- Crayora's account. A default sender would mean any number in India could be
-- made to cost Crayora money, and the customer would receive an OTP from a
-- brand they have never heard of.

create or replace function app.resolve_otp_sender(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash     bytea;
  v_salon_id uuid;
  v_source   text;
begin
  v_hash := app.phone_hash(p_phone);

  -- 1. A live join intent: someone is signing up right now.
  select salon_id into v_salon_id
    from public.join_intents
   where phone_hash = v_hash and expires_at > now();
  if v_salon_id is not null then
    v_source := 'join_intent';
  end if;

  -- 2. An existing customer signing back in.
  if v_salon_id is null then
    select salon_id into v_salon_id
      from public.customer_identities where phone_hash = v_hash;
    if v_salon_id is not null then
      v_source := 'binding';
    end if;
  end if;

  -- 3. Salon staff - owner or manager - who have a users row but no customer
  --    binding. The owner created at provisioning arrives here on their first
  --    login, before they have ever opened the app.
  if v_salon_id is null then
    select salon_id into v_salon_id
      from public.users where phone_hash = v_hash and active
     limit 1;
    if v_salon_id is not null then
      v_source := 'staff';
    end if;
  end if;

  if v_salon_id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  return jsonb_build_object('ok', true, 'salon_id', v_salon_id, 'source', v_source);
end;
$$;

comment on function app.resolve_otp_sender is
  'Intent, then binding, then staff, then refuse. There is deliberately no default sender: an OTP with no salon context is refused rather than billed to Crayora and sent from a brand the recipient does not recognise.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC. For `app` that is not the disaster
-- it is for `app_admin` - these are security definer functions written for
-- untrusted callers - but the grant should still be deliberate rather than
-- inherited.

revoke all on function app.rate_limit_hit(text, int, interval) from public;
revoke all on function app.caller_key(text) from public;
revoke all on function app.resolve_otp_sender(text) from public;

-- Internal helpers: only the service role and the functions below.
grant execute on function app.rate_limit_hit(text, int, interval) to service_role;
grant execute on function app.caller_key(text) to service_role;

-- The SMS hook runs as the service role.
grant execute on function app.resolve_otp_sender(text) to service_role;

-- The two genuinely public entry points. `anon` needs these before any
-- session exists (RULES 3.3 permits anon exactly here).
revoke all on function app.resolve_join_code(text, text) from public;
revoke all on function app.start_join(text, text, text) from public;
grant execute on function app.resolve_join_code(text, text) to anon, authenticated;
grant execute on function app.start_join(text, text, text) to anon, authenticated;

grant usage on schema app to anon;
