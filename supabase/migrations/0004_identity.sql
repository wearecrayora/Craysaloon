-- 0004 Identity and binding
--
-- This file contains the one genuinely cross-tenant table in the database.
-- Read the comment on customer_identities before changing anything here.

create type public.binding_event_kind as enum ('bind', 'unbind', 'transfer');
create type public.consent_purpose as enum
  ('service_communication', 'promotional', 'whatsapp', 'photos');
create type public.customer_status as enum ('active', 'transferred_out', 'anonymised');

-- ---------------------------------------------------------------------------
-- customer_identities - GLOBAL. One active binding per phone, full stop.
-- ---------------------------------------------------------------------------
--
-- This is the ONLY table that spans tenants, and therefore the only table with
-- ZERO policies: under forced RLS, no policy means no access. Nothing reaches
-- it except `security definer` functions (ARCHITECTURE 5.4).
--
-- The primary key on phone_hash is the whole exclusivity rule. It is not
-- enforced in application code, which could be bypassed or forgotten.

create table public.customer_identities (
  phone_hash    bytea primary key,
  auth_user_id  uuid not null unique references auth.users(id) on delete cascade,
  salon_id      uuid not null references public.salons(id) on delete restrict,
  customer_id   uuid not null,
  bound_at      timestamptz not null default now()
);

comment on table public.customer_identities is
  'GLOBAL, cross-tenant. One row per phone = one active binding per phone. Deliberately has NO RLS policies: no tenant role may read it. Access only via security definer functions.';

create index customer_identities_salon_idx on public.customer_identities (salon_id);

-- ---------------------------------------------------------------------------
-- binding_events - append-only history of every bind, unbind and transfer
-- ---------------------------------------------------------------------------
--
-- customer_identities holds the CURRENT binding; this holds how it got there.
-- acknowledged_balance_paise is required on a transfer, which is what forces
-- support to look the balance up and tell the customer before moving them
-- (ARCHITECTURE 5.4).

create table public.binding_events (
  id                          uuid primary key default extensions.gen_random_uuid(),
  phone_hash                  bytea not null,
  kind                        public.binding_event_kind not null,
  from_salon_id               uuid references public.salons(id) on delete set null,
  to_salon_id                 uuid references public.salons(id) on delete set null,
  -- Null for a customer's own first bind; required for admin actions.
  actor_admin_id              uuid references public.platform_admins(id) on delete set null,
  reason                      text,
  acknowledged_balance_paise  bigint,
  occurred_at                 timestamptz not null default now(),

  constraint binding_events_admin_needs_reason check (
    actor_admin_id is null or (reason is not null and length(trim(reason)) > 0)
  ),
  -- A transfer must record what the customer was told they would forfeit.
  constraint binding_events_transfer_needs_balance check (
    kind <> 'transfer' or acknowledged_balance_paise is not null
  )
);

create index binding_events_phone_idx on public.binding_events (phone_hash, occurred_at desc);

-- ---------------------------------------------------------------------------
-- join_intents - carries the salon through OTP, pre-auth
-- ---------------------------------------------------------------------------
--
-- Written by start_join() BEFORE signInWithOtp. The Send SMS Hook then
-- resolves which salon's Message Central account to send from by looking the
-- phone up HERE - server-side, from our own table, never from client-supplied
-- metadata (ARCHITECTURE 5.2).

create table public.join_intents (
  phone_hash  bytea primary key,
  salon_id    uuid not null references public.salons(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '15 minutes'
);

create index join_intents_expiry_idx on public.join_intents (expires_at);

comment on table public.join_intents is
  'Short-lived pre-auth record so the OTP can be sent from the right salon. No policies: security definer only.';

-- ---------------------------------------------------------------------------
-- customers - one row per (salon, person)
-- ---------------------------------------------------------------------------

create table public.customers (
  id              uuid primary key default extensions.gen_random_uuid(),
  salon_id        uuid not null references public.salons(id) on delete restrict,

  -- Null until the person installs the app and binds.
  auth_user_id    uuid references auth.users(id) on delete set null,

  name            text,
  phone           text,
  -- Survives anonymisation, so exclusivity stays enforceable after erasure
  -- (ARCHITECTURE 15.4).
  phone_hash      bytea not null,

  birthday        date,
  anniversary     date,
  language        text not null default 'en',

  last_visit_at   timestamptz,
  loyalty_points  bigint not null default 0 check (loyalty_points >= 0),
  tier            text,

  status          public.customer_status not null default 'active',
  anonymised_at   timestamptz,
  deleted_at      timestamptz,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- The same person cannot appear twice inside one salon.
  unique (salon_id, phone_hash)
);

create index customers_salon_last_visit_idx
  on public.customers (salon_id, last_visit_at desc nulls last);
create index customers_auth_user_idx
  on public.customers (auth_user_id) where auth_user_id is not null;

-- ---------------------------------------------------------------------------
-- consents - a LEDGER, not a boolean
-- ---------------------------------------------------------------------------
--
-- Per-purpose and append-only: withdrawal is a new row, never an update. A
-- single is_subscribed flag cannot represent "booking confirmations yes,
-- offers no", which is precisely what DPDP requires (ARCHITECTURE 15.4).
--
-- Written at BINDING, not at the DPDP milestone: reminders start sending at
-- M8, and consent that was never captured cannot be retro-fitted
-- (PHASES.md dependency 3).

create table public.consents (
  id          bigint generated always as identity primary key,
  salon_id    uuid not null references public.salons(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  purpose     public.consent_purpose not null,
  granted     boolean not null,
  source      text not null default 'binding',
  occurred_at timestamptz not null default now()
);

create index consents_lookup_idx
  on public.consents (salon_id, customer_id, purpose, occurred_at desc);

comment on table public.consents is
  'Append-only per-purpose consent events. Current state is the latest row per purpose.';

-- The current state of each purpose, for policies and the channel ladder.
create or replace view public.consent_state
with (security_invoker = true) as
select distinct on (customer_id, purpose)
       salon_id, customer_id, purpose, granted, occurred_at
  from public.consents
 order by customer_id, purpose, occurred_at desc;

-- ---------------------------------------------------------------------------
-- notification_tokens - FCM device tokens
-- ---------------------------------------------------------------------------

create table public.notification_tokens (
  id            uuid primary key default extensions.gen_random_uuid(),
  salon_id      uuid not null references public.salons(id) on delete cascade,
  customer_id   uuid references public.customers(id) on delete cascade,
  user_id       uuid references public.users(id) on delete cascade,
  token         text not null,
  platform      text not null check (platform in ('android', 'ios')),
  -- Set the moment FCM answers UNREGISTERED, so the ladder escalates without
  -- waiting out a window (RULES 7.3.3).
  dead_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  unique (token),
  constraint notification_tokens_has_owner
    check (num_nonnulls(customer_id, user_id) = 1)
);

create index notification_tokens_live_idx
  on public.notification_tokens (salon_id, customer_id) where dead_at is null;
