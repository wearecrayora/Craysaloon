-- 0025 The join flow's public surface - fixing two mistakes in 0024
--
-- BOTH FOUND BY THE GATE WRITTEN ALONGSIDE 0024, WHICH IS THE ONLY REASON
-- THEY ARE BEING FIXED NOW RATHER THAN IN PRODUCTION.
--
-- MISTAKE 1: `grant usage on schema app to anon`.
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC. Until 0024, that did not matter
-- for the `app` schema because no tenant role had USAGE on it, so nothing in
-- there was reachable. Granting anon USAGE to expose two entry points exposed
-- ALL of them - including `app.phone_hash`.
--
-- That one is not cosmetic. The pepper exists so that a leaked phone_hash
-- cannot be reversed by brute force over the ~10^9 Indian mobile keyspace
-- (ADR-15, RULES 4.7). An anon-callable hashing oracle hands that attack back:
-- an attacker cannot read customer_identities, but they can ask the database
-- to hash any number they like and compare. The pepper stops being a secret in
-- any useful sense.
--
-- MISTAKE 2: the grants were pointless anyway.
--
-- PostgREST only exposes the schemas in its configuration - `public` and
-- `graphql_public`. A function in `app` cannot be called over the REST API at
-- all, so the Flutter client could never have reached
-- `app.resolve_join_code`. The two entry points had to live in `public` to be
-- callable, which is also the safer place: `public` is already assumed hostile
-- and is where the grant model in 0016 is declared.
--
-- So: revoke the schema grant, and put thin SECURITY DEFINER wrappers in
-- `public` that delegate to the implementations in `app`. The implementations
-- stay where ARCHITECTURE 5.6 puts them; only the door moves.

-- ---------------------------------------------------------------------------
-- Close the schema again
-- ---------------------------------------------------------------------------

revoke usage on schema app from anon;

-- The ACL entries 0024 added are now unreachable, but leaving a grant that
-- says "anon may execute this" while relying on schema USAGE to deny it is
-- exactly the kind of two-layer reasoning that breaks the day someone grants
-- USAGE again for an unrelated reason.
revoke all on function app.resolve_join_code(text, text) from anon, authenticated;
revoke all on function app.start_join(text, text, text) from anon, authenticated;

-- Belt and braces on the helper that would hurt most. `phone_hash` is called
-- by SECURITY DEFINER functions, which run as their owner, so nothing legitimate
-- needs a tenant-role grant here.
revoke all on function app.phone_hash(text) from public, anon, authenticated;
grant execute on function app.phone_hash(text) to service_role;

-- ---------------------------------------------------------------------------
-- The two public entry points
-- ---------------------------------------------------------------------------
--
-- Thin wrappers. They add no logic - logic belongs in one place - and exist
-- only so PostgREST has something to expose.

create or replace function public.resolve_join_code(
  p_code       text,
  p_device_key text default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select app.resolve_join_code(p_code, p_device_key);
$$;

comment on function public.resolve_join_code is
  'Pre-auth: display name and branding for an ACTIVE salon, null for anything else. The app calls this before it asks for a phone number (RULES 4.1). Rate-limited inside app.resolve_join_code.';

create or replace function public.start_join(
  p_code       text,
  p_phone      text,
  p_device_key text default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select app.start_join(p_code, p_phone, p_device_key);
$$;

comment on function public.start_join is
  'Pre-auth: records which salon''s Message Central account must send the OTP. Rate-limited per phone, per caller and per salon per day - the last caps what a salon can be made to spend.';

-- ---------------------------------------------------------------------------
-- Grants: exactly these two, to exactly these roles
-- ---------------------------------------------------------------------------

revoke all on function public.resolve_join_code(text, text) from public;
revoke all on function public.start_join(text, text, text) from public;

grant execute on function public.resolve_join_code(text, text) to anon, authenticated;
grant execute on function public.start_join(text, text, text) to anon, authenticated;

-- Guard: if a future migration adds a function to `public` and inherits the
-- default PUBLIC EXECUTE, this fails the migration rather than quietly
-- widening the pre-auth surface.
do $$
declare
  v_unexpected text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_unexpected
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and has_function_privilege('anon', p.oid, 'EXECUTE')
     and p.proname not in ('resolve_join_code', 'start_join');

  if v_unexpected is not null then
    raise exception
      'anon can execute unexpected function(s) in public: %. The pre-auth '
      'surface is exactly resolve_join_code and start_join.', v_unexpected;
  end if;
end;
$$;
