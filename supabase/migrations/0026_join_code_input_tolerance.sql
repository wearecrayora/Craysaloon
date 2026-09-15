-- 0026 Accept the join code the way people actually type it
--
-- FOUND BY PRINTING THE QR PACK AND READING WHAT IT TELLS CUSTOMERS TO DO.
--
-- The printed card says "Or open the app and enter this code" - the fallback
-- for a customer whose camera will not focus, or whose phone has no QR
-- scanner. Tested against the resolver, only ONE form of a valid code worked:
--
--     CRAY-7K4M2P    resolves
--     cray-7k4m2p    resolves
--     CRAY7K4M2P     not found      no hyphen
--     CRAY 7K4M2P    not found      a space instead
--     7K4M2P         not found      just the part that looks like the code
--     CRAY–7K4M2P    not found      EN-DASH
--
-- The en-dash is the one that would have hurt. iOS and Android keyboards
-- substitute "–" for "-" as smart punctuation, and Courier's hyphen on the
-- printed card is wide enough to invite it. A customer typing exactly what
-- they see, correctly, would have been told their code is invalid - in front
-- of the counter, with the salon owner watching.
--
-- So: strip everything that is not a letter or digit, uppercase, accept the
-- code with or without the CRAY prefix, and re-form it canonically.
--
-- What this deliberately does NOT do is guess at mistyped characters. The
-- alphabet excludes 0/O and 1/I/L precisely so there is nothing to guess
-- between; a code containing one of them is simply wrong, and mapping "0" to
-- some other symbol would turn a typo into a lookup of somebody else's salon.

create or replace function app.normalise_join_code(p_input text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    -- 10 characters: CRAY plus the six-character body.
    when v ~ '^CRAY[A-HJKMNP-Z2-9]{6}$' then 'CRAY-' || substr(v, 5)
    -- 6 characters: the body alone, which is what a person reads as "the code".
    when v ~ '^[A-HJKMNP-Z2-9]{6}$'     then 'CRAY-' || v
    else null
  end
  from (select upper(regexp_replace(coalesce(p_input, ''), '[^A-Za-z0-9]', '', 'g')) as v) s
$$;

comment on function app.normalise_join_code is
  'Strips every non-alphanumeric (hyphen, en-dash, em-dash, spaces), uppercases, and accepts the code with or without its CRAY prefix. Returns null rather than guessing: the alphabet has no ambiguous characters to guess between.';

revoke all on function app.normalise_join_code(text) from public;
grant execute on function app.normalise_join_code(text) to service_role;

-- ---------------------------------------------------------------------------
-- Use it in both public entry points
-- ---------------------------------------------------------------------------
--
-- Redefined in full rather than patched, because the normalisation has to
-- happen BEFORE the rate limit is spent on a lookup - but after it is counted,
-- so a caller cannot probe freely by varying the punctuation.

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
     and s.status = 'active';

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
   where join_code = v_code and status = 'active';

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

-- CREATE OR REPLACE preserves existing grants, so the anon surface is
-- unchanged: still exactly the two wrappers in `public` (0025), which the
-- join-flow gate asserts.
