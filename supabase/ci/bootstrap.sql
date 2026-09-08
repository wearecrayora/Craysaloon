-- CI bootstrap: the minimum of Supabase that our migrations depend on.
--
-- CI runs against the `supabase/postgres` image rather than a full
-- `supabase start` stack. The gates need Postgres, pgTAP and the Supabase
-- roles - not Studio, Kong, GoTrue, Realtime or Storage. Dropping the full
-- stack removes a large opaque dependency whose only failure signal was
-- "Start a clean local stack: failed", with logs we could not read.
--
-- What the image already provides: the extensions, and usually the roles.
-- What GoTrue would normally create, and we therefore create here: the `auth`
-- schema, `auth.users`, and `auth.uid()`.
--
-- Everything is guarded, so this is safe to run against an image that already
-- has some of it.

-- ---------------------------------------------------------------------------
-- Roles. Their RLS behaviour must match production or the gates prove nothing:
-- `authenticated` MUST NOT bypass RLS, and the leak test asserts exactly that.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

-- Match production exactly (verified on the hosted project):
--   anon           bypassrls = false
--   authenticated  bypassrls = false
--   service_role   bypassrls = true
alter role anon          nobypassrls;
alter role authenticated nobypassrls;
alter role service_role  bypassrls;

grant anon, authenticated, service_role to current_user;

-- ---------------------------------------------------------------------------
-- The auth schema GoTrue would have created.
-- ---------------------------------------------------------------------------

create schema if not exists auth;
create schema if not exists extensions;

-- Only the columns our migrations and tests actually touch. Matching the real
-- table's full shape would be pretending to a fidelity we do not have; the FK
-- from customer_identities and the test inserts need id and the two NOT NULL
-- defaults, and nothing else.
create table if not exists auth.users (
  id           uuid primary key,
  is_sso_user  boolean not null default false,
  is_anonymous boolean not null default false
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    current_setting('request.jwt.claims', true)::jsonb ->> 'sub', ''
  )::uuid
$$;

grant usage on schema auth       to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;
grant select on auth.users       to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Deliberately NOT recreating Supabase's default privileges on `public`.
-- ---------------------------------------------------------------------------
--
-- Migration 0016 grants what the app needs explicitly. Leaving the platform
-- defaults out here is the point: it is what surfaced the bug where the schema
-- only worked because it inherited grants it never asked for.
