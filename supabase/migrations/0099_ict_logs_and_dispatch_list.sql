-- 0099 ICT logs kept 180 days in India, and a dispatcher that finds its salons.
--
-- 1. CERT-In (April 2022 directions) expects ICT system logs kept for 180 days,
--    within Indian jurisdiction. Supabase keeps its API, auth, database and
--    Edge Function logs only for the plan's short default. Decided 13 Oct 2026
--    (the free route): an hourly job (.github/workflows/ict-logs.yml,
--    scripts/ops/pull-logs.mjs) copies them through the Management API into
--    ops.ict_logs - in this database, in ap-south-1 (Mumbai) - and deletes
--    anything older than 180 days.
--
--    In its own schema, `ops`, which PostgREST does not expose: logs carry IP
--    addresses and request paths, and no app or console user has any reason to
--    read them. Only the database owner can. They hold no salon_id - they are
--    the platform's, not a tenant's - so tenant RLS does not apply; RLS is still
--    enabled and forced, with no policy, so that a grant made by mistake later
--    opens nothing.
--
-- 2. The dispatcher (.github/workflows/dispatch.yml) took its salons from a
--    hand-kept repository secret, so every newly activated salon would get no
--    messages until someone remembered it. And the secret was never set: the
--    workflow "succeeded" every five minutes since 5 Oct while sending nothing.
--    It now asks: public.dispatch_salons() lists the active salons, to the
--    service role only.

create schema if not exists ops;
revoke all on schema ops from public, anon, authenticated;

create table if not exists ops.ict_logs (
  source      text        not null,   -- edge_logs, auth_logs, postgres_logs, function_edge_logs
  event_id    text        not null,   -- the provider's id: re-pulling a window is a no-op
  logged_at   timestamptz not null,
  message     text,
  metadata    jsonb,
  ingested_at timestamptz not null default now(),
  primary key (source, event_id)
);

create index if not exists ict_logs_logged_at_idx on ops.ict_logs (logged_at);

alter table ops.ict_logs enable row level security;
alter table ops.ict_logs force row level security;
revoke all on ops.ict_logs from public, anon, authenticated, service_role;

comment on table ops.ict_logs is
  'CERT-In: ICT logs (API, auth, database, Edge Functions) kept 180 days in India (Mumbai). Filled hourly by scripts/ops/pull-logs.mjs; rows older than 180 days are deleted by the same job (0099).';

create or replace function public.dispatch_salons()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.salons s where s.status = 'active' order by s.id
$$;

comment on function public.dispatch_salons() is
  'The salons the dispatcher sends for - every ACTIVE salon, so a newly activated one is never forgotten (0099). service_role only.';

revoke all on function public.dispatch_salons() from public, anon, authenticated;
grant execute on function public.dispatch_salons() to service_role;
