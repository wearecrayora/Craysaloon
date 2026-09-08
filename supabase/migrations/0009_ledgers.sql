-- 0009 Wallet and loyalty ledgers
--
-- The most consequential file in the schema. Three rules from RULES.md §5
-- shape every line of it:
--
--   Append-only. Reversals are new rows. Never UPDATE, never DELETE.
--   Paid and bonus are separate LOTS with independent expiry.
--   PAID CREDIT NEVER EXPIRES - the capability is absent, not defaulted off.
--
-- The grants, the blocking trigger and the closed set of ledger callers are
-- applied in 0012; this file defines the shapes they protect.

create type public.wallet_lot_kind as enum ('paid', 'bonus');
create type public.wallet_entry_kind as enum
  ('credit_topup', 'credit_bonus', 'debit_spend', 'debit_expiry',
   'credit_reversal', 'credit_referral', 'admin_correction');
create type public.loyalty_entry_kind as enum ('earn', 'redeem', 'admin_correction');

-- ---------------------------------------------------------------------------
-- wallet_accounts - one per customer. The row that gets locked.
-- ---------------------------------------------------------------------------
--
-- balance_paise is a CACHE of the ledger, maintained only by the posting
-- function. It exists so a checkout can take `select ... for update` on one
-- row: without that lock two concurrent debits both read a stale balance and
-- overdraw (ARCHITECTURE 6.4).

create table public.wallet_accounts (
  customer_id   uuid primary key references public.customers(id) on delete cascade,
  salon_id      uuid not null references public.salons(id) on delete cascade,

  balance_paise bigint not null default 0 check (balance_paise >= 0),
  updated_at    timestamptz not null default now()
);

create index wallet_accounts_salon_idx on public.wallet_accounts (salon_id);

comment on column public.wallet_accounts.balance_paise is
  'Cache of the ledger. Written only by app.wallet_post under a row lock, never by a client.';

-- ---------------------------------------------------------------------------
-- wallet_lots - paid and bonus tranches, consumed FIFO by expiry
-- ---------------------------------------------------------------------------
--
-- A top-up of Rs 500 with a 10% bonus creates TWO lots:
--   (paid,  50000 paise, expires_at NULL)
--   (bonus,  5000 paise, expires_at now + bonus_expiry_days)
--
-- Spend order is bonus first, then paid, both FIFO by expiry: bonus expires,
-- so consuming it first means the customer loses the least (RULES 5.3.2).

create table public.wallet_lots (
  id              uuid primary key default extensions.gen_random_uuid(),
  salon_id        uuid not null references public.salons(id) on delete cascade,
  customer_id     uuid not null references public.customers(id) on delete cascade,

  kind            public.wallet_lot_kind not null,
  amount_paise    bigint not null check (amount_paise > 0),
  remaining_paise bigint not null check (remaining_paise >= 0),

  -- Terms are CAPTURED ONTO THE LOT at issue time, never read live. Changing
  -- the salon's rule affects only credit issued afterwards; it can never
  -- retroactively expire money a customer already holds (RULES 5.3.4).
  expires_at      timestamptz,
  expired_at      timestamptz,

  source_payment_id uuid references public.payments(id) on delete set null,
  created_at      timestamptz not null default now(),

  constraint wallet_lots_remaining_within_amount
    check (remaining_paise <= amount_paise),

  -- PAID CREDIT NEVER EXPIRES. Enforced by the database, so no future code
  -- path, setting or migration can quietly introduce it (RULES.md §2).
  constraint wallet_lots_paid_never_expires
    check (kind <> 'paid' or (expires_at is null and expired_at is null))
);

create index wallet_lots_spend_order_idx
  on public.wallet_lots (salon_id, customer_id, kind, expires_at nulls last)
  where remaining_paise > 0 and expired_at is null;

comment on constraint wallet_lots_paid_never_expires on public.wallet_lots is
  'Consumer Protection Act 2019: expiring money the customer actually paid is an unfair contract term, and it weakens the closed-loop PPI-exempt position.';

-- payment_allocations can now point at a real lot.
alter table public.payment_allocations
  add constraint payment_allocations_wallet_lot_fk
  foreign key (wallet_lot_id) references public.wallet_lots(id) on delete restrict;

-- ---------------------------------------------------------------------------
-- wallet_transactions - APPEND ONLY
-- ---------------------------------------------------------------------------

create table public.wallet_transactions (
  id              bigint generated always as identity primary key,
  salon_id        uuid not null references public.salons(id) on delete restrict,
  customer_id     uuid not null references public.customers(id) on delete restrict,

  kind            public.wallet_entry_kind not null,

  -- Signed: credits positive, debits negative. One column, so the sum of the
  -- ledger is the balance and reconciliation is a single aggregate.
  amount_paise    bigint not null check (amount_paise <> 0),

  -- Written by the posting function, never by a client (RULES 5.1.4).
  balance_after   bigint not null check (balance_after >= 0),

  lot_id          uuid references public.wallet_lots(id) on delete restrict,
  payment_id      uuid references public.payments(id) on delete restrict,
  visit_id        uuid references public.visits(id) on delete restrict,

  -- Mandatory on an admin correction: the only human path to a balance, and
  -- it may not be silent (RULES 5.2).
  reason          text,
  actor_admin_id  uuid references public.platform_admins(id) on delete set null,

  created_at      timestamptz not null default now(),

  constraint wallet_transactions_correction_needs_reason check (
    kind <> 'admin_correction'
    or (reason is not null and length(trim(reason)) > 0 and actor_admin_id is not null)
  )
);

create index wallet_transactions_ledger_idx
  on public.wallet_transactions (salon_id, customer_id, created_at desc);

comment on table public.wallet_transactions is
  'APPEND ONLY. Reversals are new rows. UPDATE and DELETE are revoked and trigger-blocked in 0012.';

-- ---------------------------------------------------------------------------
-- loyalty_ledger - APPEND ONLY, same rules
-- ---------------------------------------------------------------------------

create table public.loyalty_ledger (
  id              bigint generated always as identity primary key,
  salon_id        uuid not null references public.salons(id) on delete restrict,
  customer_id     uuid not null references public.customers(id) on delete restrict,

  kind            public.loyalty_entry_kind not null,
  points          bigint not null check (points <> 0),
  balance_after   bigint not null check (balance_after >= 0),

  visit_id        uuid references public.visits(id) on delete restrict,
  reason          text,
  actor_admin_id  uuid references public.platform_admins(id) on delete set null,

  created_at      timestamptz not null default now(),

  constraint loyalty_ledger_correction_needs_reason check (
    kind <> 'admin_correction'
    or (reason is not null and length(trim(reason)) > 0 and actor_admin_id is not null)
  )
);

create index loyalty_ledger_idx
  on public.loyalty_ledger (salon_id, customer_id, created_at desc);
