-- CI only, run as supabase_admin: auth tables GoTrue owns and the image lacks.
--
-- The supabase/postgres image ships auth.users but not what GoTrue's own
-- migrations create at startup. `postgres` cannot create in the image's auth
-- schema (CI run 34958080527: "permission denied for schema auth"), so this
-- runs as the image's superuser, in its own step, before bootstrap.sql.
--
-- auth.sessions: 0035 ends a customer's sessions when their binding moves or
-- goes. Without this table the trigger's guard would skip the delete and the
-- bind-flow gate would test nothing. Only the two NOT NULL columns the hosted
-- table has, plus a timestamp - no pretended fidelity.
--
-- The grant mirrors the hosted project, where `postgres` holds DELETE on
-- auth.sessions (checked 2026-09-15). Never run this against the hosted
-- project: it is GoTrue's table there.

do $$
begin
  if to_regclass('auth.sessions') is null then
    create table auth.sessions (
      id         uuid primary key,
      user_id    uuid not null references auth.users(id) on delete cascade,
      created_at timestamptz default now()
    );
  end if;
end;
$$;

grant select, insert, delete on auth.sessions to postgres;

-- auth.uid(), with PRODUCTION's definition (read from the hosted project,
-- 2026-09-27). The image ships its own, and bootstrap.sql used to leave it
-- alone - which meant every gate that resolves a customer from auth.uid() was
-- testing the image's behaviour, not Supabase's. The customer-scope gate was
-- the first to depend on it and failed in CI while passing against the hosted
-- project, which is exactly the wrong way round for a gate to behave.
--
-- Replaced here, as supabase_admin, because the auth schema is not postgres's
-- to modify. bootstrap.sql then ASSERTS the behaviour, so this can never
-- silently drift again.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

grant execute on function auth.uid() to postgres, anon, authenticated, service_role;
