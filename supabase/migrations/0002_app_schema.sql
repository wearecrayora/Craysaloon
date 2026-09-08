-- 0002 The `app` schema and its tenancy helpers
--
-- Every RLS policy in this database funnels through these three functions.
-- They are `stable` so PostgreSQL evaluates each ONCE PER STATEMENT as an
-- InitPlan rather than once per row - the difference between a dashboard that
-- loads and one that times out at 10k rows (ARCHITECTURE 5.3).
--
-- `security definer` + `set search_path = ''` is mandatory on all of them:
-- without the pinned search_path a caller could shadow a referenced object.

create schema if not exists app;
comment on schema app is
  'Tenancy helpers and business invariants. Not exposed through PostgREST.';

-- Not in the exposed schema list, so PostgREST cannot call into it directly.
revoke all on schema app from public, anon, authenticated;
grant usage on schema app to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Principal resolution
-- ---------------------------------------------------------------------------

-- The caller's tenant, straight from the GoTrue-signed JWT.
--
-- Returns NULL for an unbound customer and for a platform admin, and NULL
-- makes every tenant policy evaluate false - which is exactly the intent
-- (ARCHITECTURE 5.5).
create or replace function app.current_salon_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select nullif(
    current_setting('request.jwt.claims', true)::jsonb ->> 'salon_id',
    ''
  )::uuid
$$;

comment on function app.current_salon_id() is
  'The caller''s salon from the verified JWT. NULL denies everything.';

-- The caller's role claim. Used by policies that narrow within a salon
-- (a customer seeing only their own rows).
create or replace function app.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    current_setting('request.jwt.claims', true)::jsonb ->> 'app_role',
    'anon'
  )
$$;

-- ---------------------------------------------------------------------------
-- Identity hashing
-- ---------------------------------------------------------------------------

-- Phone numbers are stored as a PEPPERED HMAC, never plaintext and never a
-- bare hash: Indian mobile numbers are a ~10^9 keyspace, so an unsalted
-- SHA-256 is equivalent to plaintext against a database dump
-- (ARCHITECTURE 5.4).
--
-- The pepper lives in Vault, so a dump alone is useless. At M2 this reads
-- `vault.decrypted_secrets`; until the secret exists it falls back to a
-- database setting so migrations and tests can run.
create or replace function app.phone_hash(p_phone text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pepper text;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'phone_hash: empty phone';
  end if;

  begin
    select decrypted_secret into v_pepper
      from vault.decrypted_secrets
     where name = 'phone_hash_pepper'
     limit 1;
  exception when others then
    v_pepper := null;
  end;

  v_pepper := coalesce(
    v_pepper,
    nullif(current_setting('app.phone_hash_pepper', true), '')
  );

  if v_pepper is null then
    raise exception
      'phone_hash: no pepper configured (vault secret phone_hash_pepper)';
  end if;

  -- Normalise before hashing, or +91 98765 43210 and 9876543210 become two
  -- different people and the one-binding-per-phone rule silently fails.
  return extensions.hmac(
    regexp_replace(p_phone, '[^0-9]', '', 'g'),
    v_pepper,
    'sha256'
  );
end;
$$;

comment on function app.phone_hash(text) is
  'Peppered HMAC of a normalised phone. The pepper is never in a table.';
