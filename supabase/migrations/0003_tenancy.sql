-- 0003 Tenancy: salons, branding, integrations, users, subscriptions,
--      platform admins, feature flags, audit log.
--
-- Conventions enforced throughout (ARCHITECTURE 6.1):
--   * uuid primary keys
--   * salon_id on every tenant table, FIRST column of every composite index
--   * money is bigint PAISE - never float, never numeric in the app layer
--   * timestamptz always
--   * statuses, not deletes

-- ---------------------------------------------------------------------------
-- Enums. Closed sets get a type; open ones stay text.
-- ---------------------------------------------------------------------------

create type public.salon_status as enum ('setup', 'active', 'grace', 'suspended');
create type public.user_role as enum ('owner', 'manager', 'staff');
create type public.subscription_status as enum ('active', 'past_due', 'cancelled');
create type public.setup_fee_status as enum ('unpaid', 'paid', 'waived');
create type public.integration_provider as enum
  ('razorpay', 'message_central', 'whatsapp', 'rcs');
create type public.integration_status as enum
  ('missing', 'untested', 'ok', 'failing');

-- ---------------------------------------------------------------------------
-- salons
-- ---------------------------------------------------------------------------

create table public.salons (
  id                  uuid primary key default extensions.gen_random_uuid(),

  legal_name          text not null,
  -- Rendered in EVERY message and all over the app. Never translated.
  display_name        text not null check (length(trim(display_name)) > 0),

  -- CRAY-XXXXXX, 32-symbol unambiguous alphabet (no 0/O, 1/I/L), ~1.07e9
  -- combinations. Case-insensitive on input, so store it uppercase and
  -- compare uppercase (ARCHITECTURE 5.6).
  join_code           text not null unique
                        check (join_code ~ '^CRAY-[A-HJ-NP-Z2-9]{6}$'),

  -- Razorpay calls /rzp-webhook/{this}. The salon is resolved from the PATH,
  -- never from the request body, which an attacker controls (ARCH 8.3).
  webhook_token       text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),

  address             text,
  phone               text,
  email               text,
  gst_number          text,
  timezone            text not null default 'Asia/Kolkata',
  languages           text[] not null default array['en'],

  working_hours       jsonb not null default '{}'::jsonb,
  cancellation_policy text,

  -- Bonus rule, minimum top-up, and BONUS expiry only. There is deliberately
  -- no paid-credit expiry key: money the customer paid never expires, and the
  -- capability is absent rather than defaulted off (RULES 5.3.3).
  wallet_rule         jsonb not null default
                        '{"bonus_percent": 10, "min_topup_paise": 50000, "bonus_expiry_days": 180}'::jsonb,
  reward_rule         jsonb not null default '{}'::jsonb,
  loyalty_rule        jsonb not null default '{}'::jsonb,
  default_reminder_cycle_days int not null default 30
                        check (default_reminder_cycle_days between 1 and 365),

  notification_prefs  jsonb not null default
                        '{"marketing_escalation": "sms"}'::jsonb,

  status              public.salon_status not null default 'setup',
  activated_by        uuid,
  activated_at        timestamptz,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- A salon cannot be active without someone having deliberately activated it
  -- (ARCHITECTURE 5.7). Nothing else may flip this.
  constraint salons_activation_recorded
    check (status = 'setup' or (activated_by is not null and activated_at is not null))
);

comment on table public.salons is
  'One tenant. Created only through the console, activated only by a human.';

-- ---------------------------------------------------------------------------
-- salon_branding - the design-token document (DESIGN.md 3.2)
-- ---------------------------------------------------------------------------

create table public.salon_branding (
  salon_id    uuid primary key references public.salons(id) on delete cascade,
  -- Bumping this is what re-themes installed apps on their next open.
  version     int  not null default 1 check (version > 0),
  tokens      jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- salon_integrations - REFERENCES to secrets, never secrets
-- ---------------------------------------------------------------------------

create table public.salon_integrations (
  id                        uuid primary key default extensions.gen_random_uuid(),
  salon_id                  uuid not null references public.salons(id) on delete cascade,
  provider                  public.integration_provider not null,

  -- The secret itself lives in Vault. This table holds only the handle plus
  -- non-sensitive metadata, and has NO tenant policies at all (0010), so an
  -- owner cannot read their own credential back (RULES 11.1).
  vault_secret_id           uuid,
  public_key_id             text,
  last4                     text check (last4 is null or length(last4) <= 8),
  sender_id                 text,

  -- Gate the WhatsApp rung of the ladder. Never blocks onboarding.
  whatsapp_template_status  text not null default 'not_started',
  -- Gate the RCS rung. Designed, unpriced, not built until Q-G is answered.
  rcs_agent_id              text,
  rcs_agent_status          text not null default 'not_started',

  status                    public.integration_status not null default 'missing',
  last_tested_at            timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  unique (salon_id, provider)
);

comment on table public.salon_integrations is
  'Handles to Vault secrets. No tenant role may read this table (see 0010).';

-- ---------------------------------------------------------------------------
-- users - staff principals. Exactly one salon each.
-- ---------------------------------------------------------------------------

create table public.users (
  id           uuid primary key references auth.users(id) on delete cascade,
  salon_id     uuid not null references public.salons(id) on delete restrict,
  role         public.user_role not null,

  -- Granular permissions. There is no key here that grants wallet adjustment,
  -- and adding one would not help: no such code path exists (RULES 5.2).
  permissions  jsonb not null default '{}'::jsonb,

  name         text not null,
  phone        text not null,
  -- Lets resolve_otp_sender find a staff member's salon without a plaintext
  -- lookup (ARCHITECTURE 5.2).
  phone_hash   bytea not null,
  active       boolean not null default true,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index users_salon_idx on public.users (salon_id, active);
create index users_phone_hash_idx on public.users (phone_hash) where active;

-- ---------------------------------------------------------------------------
-- subscriptions - setup fee is recorded, never processed
-- ---------------------------------------------------------------------------

create table public.subscriptions (
  salon_id              uuid primary key references public.salons(id) on delete cascade,
  plan                  text not null default 'starter',
  status                public.subscription_status not null default 'active',

  -- Collected OFFLINE, cash or bank transfer. There is no payment integration
  -- for it and activation is a separate deliberate act (ARCHITECTURE 13.2).
  setup_fee_paise       bigint not null default 0 check (setup_fee_paise >= 0),
  setup_fee_status      public.setup_fee_status not null default 'unpaid',
  setup_fee_reference   text,
  setup_fee_paid_on     date,

  billing_starts_on     date,
  renews_at             timestamptz,
  past_due_since        timestamptz,

  -- Retained for owner transparency and an optional soft cap. NOT a plan
  -- entitlement: the salon pays its own messaging bill (ARCHITECTURE 12.4).
  messages_used_this_cycle int not null default 0 check (messages_used_this_cycle >= 0),

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- platform_admins - Crayora. No salon_id, ever.
-- ---------------------------------------------------------------------------

create table public.platform_admins (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null unique,
  name        text not null,
  is_super    boolean not null default false,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

comment on table public.platform_admins is
  'Crayora operators. Never granted a salon_id claim; no RLS policy references this table.';

-- ---------------------------------------------------------------------------
-- feature_flags
-- ---------------------------------------------------------------------------

create table public.feature_flags (
  salon_id    uuid not null references public.salons(id) on delete cascade,
  flag        text not null,
  enabled     boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (salon_id, flag)
);

-- ---------------------------------------------------------------------------
-- audit_log - every admin mutation, written in the SAME transaction
-- ---------------------------------------------------------------------------

create table public.audit_log (
  id              bigint generated always as identity primary key,
  -- Nullable: some entries are platform-level and belong to no tenant.
  salon_id        uuid references public.salons(id) on delete set null,
  actor_user_id   uuid,
  actor_kind      text not null default 'platform_admin',
  action          text not null,
  entity          text,
  entity_id       text,
  reason          text,
  before_state    jsonb,
  after_state     jsonb,
  created_at      timestamptz not null default now()
);

create index audit_log_salon_idx on public.audit_log (salon_id, created_at desc);
create index audit_log_actor_idx on public.audit_log (actor_user_id, created_at desc);

comment on table public.audit_log is
  'Append-only in practice: app_admin.* functions write here in the same transaction as the mutation, so audit cannot be forgotten.';
