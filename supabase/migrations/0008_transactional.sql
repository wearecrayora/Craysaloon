-- 0008 Bookings, visits and payments
--
-- Two things here exist because of specific failure modes:
--
--   booking_items snapshots price and duration AT BOOKING TIME. Without it,
--   an owner editing a service price silently rewrites past revenue and every
--   dashboard number drifts (ARCHITECTURE 6.2).
--
--   payments + payment_allocations exist because visits.payment_status alone
--   cannot express "Rs 300 from a package, Rs 200 from wallet, Rs 400 on UPI",
--   let alone unwind it when the service is cancelled (ARCHITECTURE 6.3).

create type public.booking_status as enum
  ('pending', 'confirmed', 'completed', 'cancelled', 'no_show');
create type public.booking_source as enum
  ('walk_in', 'app', 'reminder', 'referral', 'waitlist');
create type public.booking_item_kind as enum ('service', 'add_on');
create type public.payment_method as enum
  ('package', 'wallet', 'upi', 'card', 'cash');
create type public.payment_status as enum
  ('created', 'authorized', 'captured', 'failed', 'cancelled');
create type public.visit_payment_status as enum ('unpaid', 'partial', 'paid');

-- ---------------------------------------------------------------------------
-- bookings
-- ---------------------------------------------------------------------------

create table public.bookings (
  id           uuid primary key default extensions.gen_random_uuid(),
  salon_id     uuid not null references public.salons(id) on delete cascade,
  customer_id  uuid not null references public.customers(id) on delete restrict,

  -- Nullable: a walk-in may not have a barber assigned yet. The exclusion
  -- constraint in 0012 only binds rows where staff_id is set, which is the
  -- correct behaviour - an unassigned booking blocks nobody.
  staff_id     uuid references public.staff(id) on delete set null,

  starts_at    timestamptz not null,
  ends_at      timestamptz not null,

  status       public.booking_status not null default 'pending',
  source       public.booking_source not null default 'walk_in',

  -- Sum of the snapshotted item prices, not a live lookup.
  total_paise  bigint not null default 0 check (total_paise >= 0),

  notes        text,
  cancelled_at timestamptz,
  cancel_reason text,

  -- Set by the client for offline replay; an idempotent retry collides here
  -- and becomes a no-op rather than a second booking (ARCHITECTURE 10.2).
  client_action_id uuid,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint bookings_ordered check (ends_at > starts_at)
);

create index bookings_salon_start_idx on public.bookings (salon_id, starts_at);
create index bookings_salon_customer_idx
  on public.bookings (salon_id, customer_id, starts_at desc);
create index bookings_salon_staff_idx
  on public.bookings (salon_id, staff_id, starts_at);
create unique index bookings_client_action_idx
  on public.bookings (salon_id, client_action_id)
  where client_action_id is not null;

-- ---------------------------------------------------------------------------
-- booking_items - the price snapshot
-- ---------------------------------------------------------------------------

create table public.booking_items (
  id               uuid primary key default extensions.gen_random_uuid(),
  salon_id         uuid not null references public.salons(id) on delete cascade,
  booking_id       uuid not null references public.bookings(id) on delete cascade,

  kind             public.booking_item_kind not null,
  -- Points at services.id or add_ons.id depending on kind. Deliberately not a
  -- foreign key: deleting a service must never orphan or rewrite history.
  ref_id           uuid not null,

  -- SNAPSHOT. What it cost and how long it took, at the moment of booking.
  name_snapshot    text not null,
  price_paise      bigint not null check (price_paise >= 0),
  duration_minutes int not null check (duration_minutes >= 0),

  created_at       timestamptz not null default now()
);

create index booking_items_booking_idx on public.booking_items (salon_id, booking_id);

comment on table public.booking_items is
  'Price and duration snapshotted at booking time. Never re-read from services - that would rewrite past revenue.';

-- ---------------------------------------------------------------------------
-- visits - a completed booking
-- ---------------------------------------------------------------------------

create table public.visits (
  id                uuid primary key default extensions.gen_random_uuid(),
  salon_id          uuid not null references public.salons(id) on delete cascade,
  booking_id        uuid not null unique references public.bookings(id) on delete restrict,
  customer_id       uuid not null references public.customers(id) on delete restrict,
  staff_id          uuid references public.staff(id) on delete set null,

  final_amount_paise bigint not null default 0 check (final_amount_paise >= 0),
  tip_paise          bigint not null default 0 check (tip_paise >= 0),
  payment_status     public.visit_payment_status not null default 'unpaid',

  completed_at       timestamptz not null default now(),

  -- Mark-complete is queued offline, so the same action can arrive twice
  -- (RULES 9.3). Unique below makes the replay a no-op.
  client_action_id   uuid,

  created_at         timestamptz not null default now()
);

create index visits_salon_completed_idx on public.visits (salon_id, completed_at desc);
create index visits_salon_customer_idx
  on public.visits (salon_id, customer_id, completed_at desc);
create unique index visits_client_action_idx
  on public.visits (salon_id, client_action_id)
  where client_action_id is not null;

-- ---------------------------------------------------------------------------
-- payments and their allocations
-- ---------------------------------------------------------------------------

create table public.payments (
  id                  uuid primary key default extensions.gen_random_uuid(),
  salon_id            uuid not null references public.salons(id) on delete cascade,
  customer_id         uuid not null references public.customers(id) on delete restrict,
  -- Null for a wallet TOP-UP, which is not payment for a visit.
  visit_id            uuid references public.visits(id) on delete restrict,

  method              public.payment_method not null,
  amount_paise        bigint not null check (amount_paise > 0),
  status              public.payment_status not null default 'created',

  -- Money settles into THE SALON'S OWN Razorpay account. Crayora never
  -- receives, holds or disburses it (RULES 6d).
  razorpay_order_id   text,
  razorpay_payment_id text,

  idempotency_key     text,

  created_at          timestamptz not null default now(),
  captured_at         timestamptz
);

create index payments_salon_created_idx on public.payments (salon_id, created_at desc);
create index payments_salon_visit_idx on public.payments (salon_id, visit_id);
create unique index payments_idempotency_idx
  on public.payments (salon_id, idempotency_key)
  where idempotency_key is not null;
create unique index payments_razorpay_idx
  on public.payments (razorpay_payment_id)
  where razorpay_payment_id is not null;

-- What each payment actually consumed, so a cancellation can be unwound
-- precisely rather than approximately.
create table public.payment_allocations (
  id                  uuid primary key default extensions.gen_random_uuid(),
  salon_id            uuid not null references public.salons(id) on delete cascade,
  payment_id          uuid not null references public.payments(id) on delete cascade,

  -- Exactly one source. wallet_lot_id and customer_package_id are added as
  -- foreign keys in 0009 and at Tier 2 respectively.
  wallet_lot_id       uuid,
  customer_package_id uuid,

  amount_paise        bigint not null check (amount_paise > 0),
  created_at          timestamptz not null default now()
);

create index payment_allocations_payment_idx
  on public.payment_allocations (salon_id, payment_id);
