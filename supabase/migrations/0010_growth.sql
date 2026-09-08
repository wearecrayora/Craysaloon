-- 0010 The growth loop: referrals, reminders, notifications, templates

create type public.referral_status as enum
  ('invited', 'registered', 'pending_visit', 'rewarded', 'rejected');
create type public.reminder_status as enum
  ('scheduled', 'sent', 'delivered', 'failed', 'converted', 'opted_out');
create type public.message_category as enum ('transactional', 'marketing');
create type public.message_channel as enum ('push', 'rcs', 'whatsapp', 'sms');
create type public.notification_status as enum
  ('pending', 'sent', 'acked', 'escalated', 'suppressed', 'no_channel_available');

-- ---------------------------------------------------------------------------
-- referrals
-- ---------------------------------------------------------------------------

create table public.referrals (
  id                  uuid primary key default extensions.gen_random_uuid(),
  salon_id            uuid not null references public.salons(id) on delete cascade,

  referrer_id         uuid not null references public.customers(id) on delete restrict,
  referred_customer_id uuid references public.customers(id) on delete set null,

  code                text not null,
  status              public.referral_status not null default 'invited',

  -- Released ONLY after a completed, paid first visit (RULES.md 1.8).
  reward_paise        bigint not null default 0 check (reward_paise >= 0),
  completed_visit_id  uuid references public.visits(id) on delete set null,
  rewarded_at         timestamptz,

  created_at          timestamptz not null default now(),

  -- One referrer per referred customer. A constraint, not a check in code.
  constraint referrals_no_self_referral
    check (referred_customer_id is null or referred_customer_id <> referrer_id)
);

create unique index referrals_code_idx on public.referrals (salon_id, code);
create unique index referrals_one_referrer_idx
  on public.referrals (salon_id, referred_customer_id)
  where referred_customer_id is not null;
create index referrals_referrer_idx on public.referrals (salon_id, referrer_id);

-- ---------------------------------------------------------------------------
-- reminders - exactly one per cycle, enforced by index
-- ---------------------------------------------------------------------------

create table public.reminders (
  id              uuid primary key default extensions.gen_random_uuid(),
  salon_id        uuid not null references public.salons(id) on delete cascade,
  customer_id     uuid not null references public.customers(id) on delete cascade,
  service_id      uuid references public.services(id) on delete set null,

  -- Derived from the visit that generated this reminder. A replayed offline
  -- mark-complete, a retried job and a duplicate event all collide on the
  -- unique index below and become no-ops (ARCHITECTURE 6.6).
  cycle_key       text not null,

  type            text not null default 'service_due',
  scheduled_for   timestamptz not null,
  status          public.reminder_status not null default 'scheduled',
  booking_id      uuid references public.bookings(id) on delete set null,

  created_at      timestamptz not null default now()
);

-- THE constraint that makes "exactly one reminder per cycle" true.
create unique index reminders_one_per_cycle
  on public.reminders (salon_id, customer_id, service_id, cycle_key)
  where status in ('scheduled', 'sent', 'delivered');

create index reminders_due_idx
  on public.reminders (salon_id, scheduled_for) where status = 'scheduled';

-- Learned intervals: after 2+ visits, next-due uses the customer's own median
-- clamped to the owner's range. Deliberately a median, not a model - it has to
-- be explainable to a salon owner (ARCHITECTURE 6.7).
create table public.customer_service_intervals (
  salon_id    uuid not null references public.salons(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  service_id  uuid not null references public.services(id) on delete cascade,
  median_days numeric not null check (median_days > 0),
  sample_n    int not null check (sample_n >= 2),
  updated_at  timestamptz not null default now(),
  primary key (salon_id, customer_id, service_id)
);

-- ---------------------------------------------------------------------------
-- notifications: INTENT, and per-channel ATTEMPTS
-- ---------------------------------------------------------------------------
--
-- Separating the two is what makes "push was tried before paid WhatsApp"
-- auditable, and PRD §12 makes that a business metric, not just a behaviour.

create table public.notifications (
  id            uuid primary key default extensions.gen_random_uuid(),
  salon_id      uuid not null references public.salons(id) on delete cascade,

  customer_id   uuid references public.customers(id) on delete cascade,
  user_id       uuid references public.users(id) on delete cascade,

  purpose       text not null,
  category      public.message_category not null,
  locale        text not null default 'en',
  template_key  text not null,
  params        jsonb not null default '{}'::jsonb,

  status        public.notification_status not null default 'pending',
  created_at    timestamptz not null default now(),

  constraint notifications_has_recipient
    check (num_nonnulls(customer_id, user_id) = 1)
);

create index notifications_salon_created_idx
  on public.notifications (salon_id, created_at desc);

create table public.notification_deliveries (
  id                  uuid primary key default extensions.gen_random_uuid(),
  salon_id            uuid not null references public.salons(id) on delete cascade,
  notification_id     uuid not null references public.notifications(id) on delete cascade,

  channel             public.message_channel not null,
  provider_message_id text,
  sent_at             timestamptz,

  -- FCM reports acceptance by Google, NOT delivery. Escalation is gated on
  -- this column - the app acknowledges receipt - never on FCM's response
  -- (ARCHITECTURE 12.3).
  acked_at            timestamptz,

  provider_status     text,
  failure_reason      text,

  -- The SALON's cost, not Crayora's. Drives the owner's spend view shown
  -- beside reminder conversion (ARCHITECTURE 12.4).
  cost_paise          bigint not null default 0 check (cost_paise >= 0),

  created_at          timestamptz not null default now()
);

create index notification_deliveries_notification_idx
  on public.notification_deliveries (salon_id, notification_id);
-- Drives the escalation sweep: unacked pushes past their window.
create index notification_deliveries_unacked_idx
  on public.notification_deliveries (salon_id, channel, sent_at)
  where acked_at is null;

-- ---------------------------------------------------------------------------
-- message_templates
-- ---------------------------------------------------------------------------
--
-- PUSH bodies live here in full - it is the one channel we control end to end.
-- WhatsApp and RCS bodies are authored in the Message Central dashboard per
-- salon; we store only the identifier and variable order (ARCHITECTURE 12.5a).

create table public.message_templates (
  id                   uuid primary key default extensions.gen_random_uuid(),
  -- NULL salon_id is the Crayora default; a salon row overrides it.
  salon_id             uuid references public.salons(id) on delete cascade,

  template_key         text not null,
  locale               text not null,
  channel              public.message_channel not null,

  -- Push only. Null for WhatsApp/RCS, whose text lives at the provider.
  body                 text,
  -- WhatsApp/RCS: the provider-side identifier, per salon.
  provider_template_id text,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint message_templates_body_or_provider check (
    (channel = 'push' and body is not null)
    or (channel <> 'push')
  )
);

create unique index message_templates_default_idx
  on public.message_templates (template_key, locale, channel)
  where salon_id is null;
create unique index message_templates_salon_idx
  on public.message_templates (salon_id, template_key, locale, channel)
  where salon_id is not null;
