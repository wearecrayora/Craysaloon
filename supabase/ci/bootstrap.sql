-- CI bootstrap: the minimum of Supabase that our migrations depend on.
--
-- CI runs against the `supabase/postgres` image rather than a full
-- `supabase start` stack. The gates need Postgres, pgTAP and the Supabase
-- roles - not Studio, Kong, GoTrue, Realtime or Storage. Dropping the full
-- stack removes a large opaque dependency whose only failure signal was
-- "Start a clean local stack: failed", with logs we could not read.
--
-- What the image already provides: the extensions, the roles, and the `auth`,
-- `extensions` and `vault` schemas. What GoTrue would normally create, and we
-- therefore create here: `auth.users` and `auth.uid()`.
--
-- Everything is guarded, so this is safe to run against an image that already
-- has some of it.

-- ---------------------------------------------------------------------------
-- Roles: ASSERT, never mutate.
-- ---------------------------------------------------------------------------
--
-- This file used to run `alter role authenticated nobypassrls`. Two things
-- were wrong with that.
--
-- First, it does not work: `postgres` in this image is NOT a superuser
-- (usesuper = false) and supautils rejects any ALTER ROLE against a reserved
-- role with "only superusers can modify it". That error is what took the
-- database job down once the pipefail bug stopped hiding it.
--
-- Second, and worse, it was the wrong shape even if it had worked. The gates
-- only prove something if CI's roles behave like production's. Setting the
-- flags ourselves would make that true BY CONSTRUCTION - CI would pass because
-- we forced it to, on an image whose real behaviour we never looked at. So
-- check instead, and fail the bootstrap with a specific message if the image
-- ever ships different defaults.
--
-- Verified against the hosted project:
--   anon           bypassrls = false
--   authenticated  bypassrls = false
--   service_role   bypassrls = true

do $$
declare
  v_name     text;
  v_want     boolean;
  v_have     boolean;
  v_exists   boolean;
begin
  foreach v_name in array array['anon', 'authenticated', 'service_role'] loop
    v_want := (v_name = 'service_role');

    select true, rolbypassrls into v_exists, v_have
      from pg_roles where rolname = v_name;

    if v_exists is null then
      raise exception
        'bootstrap: role % is missing from this image - the gates cannot run '
        'without it', v_name;
    end if;

    if v_have <> v_want then
      raise exception
        'bootstrap: role % has rolbypassrls = %, production has % - the leak '
        'test would prove nothing on this image', v_name, v_have, v_want;
    end if;
  end loop;
end;
$$;

-- The tests reach `authenticated` with SET ROLE, which needs membership. The
-- image normally grants it already; only ask for it when it is missing, and
-- say plainly what broke if the grant is refused too.
do $$
declare
  v_name text;
begin
  foreach v_name in array array['anon', 'authenticated', 'service_role'] loop
    if not pg_has_role(current_user, v_name, 'MEMBER') then
      begin
        execute format('grant %I to %I', v_name, current_user);
      exception when others then
        raise exception
          'bootstrap: % is not granted to % and the grant was refused (%) - '
          'the leak test cannot SET ROLE', v_name, current_user, sqlerrm;
      end;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- The auth schema GoTrue would have created.
-- ---------------------------------------------------------------------------

create schema if not exists auth;
create schema if not exists extensions;

-- Only the columns our migrations and tests actually touch. Matching the real
-- table's full shape would be pretending to a fidelity we do not have; the FK
-- from customer_identities and the test inserts need id and the two NOT NULL
-- defaults, and nothing else.
--
-- Guarded by a catalogue lookup rather than IF NOT EXISTS: on a real Supabase
-- project `postgres` has no rights on the `auth` schema at all, so the bare
-- CREATE raises "permission denied for schema auth" even though the table is
-- already there. Looking first means this file runs unchanged against the CI
-- image and against the hosted project.
do $$
begin
  if not exists (
    select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'auth' and c.relname = 'users'
  ) then
    create table auth.users (
      id           uuid primary key,
      is_sso_user  boolean not null default false,
      is_anonymous boolean not null default false
    );
  end if;
end;
$$;

-- CREATE OR REPLACE would fail if the image already ships auth.uid() owned by
-- another role, so only define it when it is absent - and never overwrite the
-- real one.
do $$
begin
  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'auth' and p.proname = 'uid'
  ) then
    execute $fn$
      create function auth.uid()
      returns uuid
      language sql
      stable
      as $body$
        select nullif(
          current_setting('request.jwt.claims', true)::jsonb ->> 'sub', ''
        )::uuid
      $body$
    $fn$;
  end if;
end;
$$;

-- Best effort: on a real Supabase database these grants already exist and the
-- `auth` schema is not ours to modify. Nothing in the gates depends on them -
-- app.current_*() are SECURITY DEFINER and run as their owner - so a refusal
-- here is not a reason to fail the build.
do $$
begin
  grant usage on schema auth       to anon, authenticated, service_role;
  grant usage on schema extensions to anon, authenticated, service_role;
  grant select on auth.users       to authenticated, service_role;
exception when others then
  raise notice 'bootstrap: auth/extensions grants skipped (%)', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- Deliberately NOT recreating Supabase's default privileges on `public`.
-- ---------------------------------------------------------------------------
--
-- Migration 0016 grants what the app needs explicitly. Leaving the platform
-- defaults out here is the point: it is what surfaced the bug where the schema
-- only worked because it inherited grants it never asked for.
