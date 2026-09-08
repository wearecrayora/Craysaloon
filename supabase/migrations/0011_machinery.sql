-- 0011 Machinery: the outbox, jobs, idempotency, webhooks, rate limits and
--      the pre-aggregated read models.
--
-- None of this is a product surface. It is what makes the automations
-- survive retries, redeploys and offline replay (ARCHITECTURE 11).

create type public.job_status as enum
  ('pending', 'running', 'done', 'failed', 'dead');

-- ---------------------------------------------------------------------------
-- domain_events - the transactional outbox
-- ---------------------------------------------------------------------------
--
-- A trigger that fires an HTTP call is NOT transactional: the request can
-- succeed while the transaction rolls back, or fire twice on a retry. So
-- domain writes append here in the SAME transaction, and a dispatcher drains
-- it. If the transaction rolls back, the event never existed.

create table public.domain_events (
  id            bigint generated always as identity primary key,
  salon_id      uuid not null references public.salons(id) on delete cascade,
  type          text not null,
  aggregate_id  uuid,
  payload       jsonb not null default '{}'::jsonb,
  occurred_at   timestamptz not null default now(),
  processed_at  timestamptz
);

create index domain_events_undrained_idx
  on public.domain_events (occurred_at) where processed_at is null;

-- ---------------------------------------------------------------------------
-- jobs - scheduled and retried work, with a dead-letter that ALERTS
-- ---------------------------------------------------------------------------

create table public.jobs (
  id            bigint generated always as identity primary key,
  salon_id      uuid references public.salons(id) on delete cascade,
  kind          text not null,
  payload       jsonb not null default '{}'::jsonb,

  run_at        timestamptz not null default now(),
  attempts      int not null default 0 check (attempts >= 0),
  max_attempts  int not null default 5 check (max_attempts > 0),
  status        public.job_status not null default 'pending',
  last_error    text,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index jobs_runnable_idx on public.jobs (run_at) where status = 'pending';
-- Work that fails silently is worse than work that fails loudly: this index
-- backs the Sentry alert on dead-lettered jobs.
create index jobs_dead_idx on public.jobs (updated_at desc) where status = 'dead';

-- ---------------------------------------------------------------------------
-- idempotency_keys - offline replay protection
-- ---------------------------------------------------------------------------
--
-- Every server RPC takes a client_action_id. A replay returns the ORIGINAL
-- result instead of re-applying, which is what makes a double-sync a no-op
-- rather than a double-charge (ARCHITECTURE 10.2).

create table public.idempotency_keys (
  salon_id    uuid not null references public.salons(id) on delete cascade,
  key         uuid not null,
  operation   text not null,
  result      jsonb,
  created_at  timestamptz not null default now(),
  primary key (salon_id, key)
);

-- ---------------------------------------------------------------------------
-- webhook_events - insert first, then process
-- ---------------------------------------------------------------------------
--
-- The unique constraint IS the dedupe: a Razorpay redelivery collides and
-- becomes a no-op. The salon is resolved from the webhook PATH token, never
-- from the body, which an attacker controls (ARCHITECTURE 8.3).

create table public.webhook_events (
  id            bigint generated always as identity primary key,
  provider      text not null,
  event_id      text not null,
  salon_id      uuid references public.salons(id) on delete set null,
  payload       jsonb not null,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  unique (provider, event_id)
);

-- ---------------------------------------------------------------------------
-- rate_limit_counters - fixed windows, in Postgres
-- ---------------------------------------------------------------------------
--
-- In the database rather than a separate vendor, so a limit shares a
-- transaction with the thing it guards. Protects OTP spend (the salon's
-- money), start_join, salon-code lookup and bind attempts (RULES 11.5).

create table public.rate_limit_counters (
  bucket        text not null,
  window_start  timestamptz not null,
  count         int not null default 0 check (count >= 0),
  primary key (bucket, window_start)
);

create index rate_limit_counters_sweep_idx on public.rate_limit_counters (window_start);

-- ---------------------------------------------------------------------------
-- Read models - the dashboard never aggregates raw rows
-- ---------------------------------------------------------------------------

create table public.daily_salon_metrics (
  salon_id                uuid not null references public.salons(id) on delete cascade,
  day                     date not null,

  revenue_paise           bigint not null default 0,
  bookings                int not null default 0,
  completed               int not null default 0,
  no_shows                int not null default 0,
  new_customers           int not null default 0,
  repeat_customers        int not null default 0,
  wallet_collected_paise  bigint not null default 0,
  wallet_outstanding_paise bigint not null default 0,
  addon_revenue_paise     bigint not null default 0,
  reminder_bookings       int not null default 0,
  -- The leading indicator for the whole funnel: if customers are not being
  -- asked to scan, nothing else in the product can work (PRD §18).
  binds                   int not null default 0,

  -- Messaging spend, shown BESIDE reminder conversion and never without it
  -- (RULES 7.3.1a).
  messaging_cost_paise    bigint not null default 0,

  updated_at              timestamptz not null default now(),
  primary key (salon_id, day)
);

create table public.retention_cohorts (
  salon_id       uuid not null references public.salons(id) on delete cascade,
  cohort_month   date not null,
  -- 'wallet' | 'non_wallet' - the split that proves the loop (PRD §9.5).
  wallet_segment text not null,
  cohort_size    int not null default 0,
  d30            numeric,
  d60            numeric,
  d90            numeric,
  updated_at     timestamptz not null default now(),
  primary key (salon_id, cohort_month, wallet_segment)
);
