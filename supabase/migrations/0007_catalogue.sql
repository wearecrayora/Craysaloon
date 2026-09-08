-- 0007 Catalogue: services, add-ons, staff and their availability
--
-- Every table carries salon_id and every composite index leads with it
-- (ARCHITECTURE 6.1). Money is bigint paise throughout - never numeric, never
-- float (RULES 5.1.2).

create table public.services (
  id                uuid primary key default extensions.gen_random_uuid(),
  salon_id          uuid not null references public.salons(id) on delete cascade,

  name              text not null check (length(trim(name)) > 0),
  category          text,
  price_paise       bigint not null check (price_paise >= 0),
  duration_minutes  int not null check (duration_minutes between 5 and 600),

  -- Drives the next-due date until the customer has enough history for a
  -- learned median (ARCHITECTURE 6.7).
  repeat_cycle_days int check (repeat_cycle_days between 1 and 365),

  image_url         text,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index services_salon_active_idx on public.services (salon_id, active);

create table public.add_ons (
  id                     uuid primary key default extensions.gen_random_uuid(),
  salon_id               uuid not null references public.salons(id) on delete cascade,

  name                   text not null check (length(trim(name)) > 0),
  price_paise            bigint not null check (price_paise >= 0),
  extra_duration_minutes int not null default 0 check (extra_duration_minutes >= 0),

  active                 boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index add_ons_salon_active_idx on public.add_ons (salon_id, active);

-- Which add-ons are relevant to which service. Only relevant ones are shown,
-- and none is ever pre-selected (RULES.md 2).
create table public.service_addons (
  salon_id    uuid not null references public.salons(id) on delete cascade,
  service_id  uuid not null references public.services(id) on delete cascade,
  add_on_id   uuid not null references public.add_ons(id) on delete cascade,
  primary key (service_id, add_on_id)
);

create index service_addons_salon_idx on public.service_addons (salon_id, service_id);

create table public.staff (
  id              uuid primary key default extensions.gen_random_uuid(),
  salon_id        uuid not null references public.salons(id) on delete cascade,

  -- Null until the barber gets their own login at Tier 2.
  user_id         uuid references public.users(id) on delete set null,

  name            text not null check (length(trim(name)) > 0),
  skills          text[] not null default '{}',
  commission_rule jsonb not null default '{}'::jsonb,
  active          boolean not null default true,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index staff_salon_active_idx on public.staff (salon_id, active);

-- Recurring weekly availability. Feeds app.available_slots() together with
-- time off and existing bookings (ARCHITECTURE 6.5).
create table public.staff_schedules (
  id          uuid primary key default extensions.gen_random_uuid(),
  salon_id    uuid not null references public.salons(id) on delete cascade,
  staff_id    uuid not null references public.staff(id) on delete cascade,

  -- 0 = Sunday, matching Postgres extract(dow).
  day_of_week smallint not null check (day_of_week between 0 and 6),
  starts_at   time not null,
  ends_at     time not null,

  constraint staff_schedules_ordered check (ends_at > starts_at)
);

create index staff_schedules_lookup_idx
  on public.staff_schedules (salon_id, staff_id, day_of_week);

-- One-off absences and salon holidays. staff_id null = the whole salon closed.
create table public.staff_time_off (
  id          uuid primary key default extensions.gen_random_uuid(),
  salon_id    uuid not null references public.salons(id) on delete cascade,
  staff_id    uuid references public.staff(id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  reason      text,

  constraint staff_time_off_ordered check (ends_at > starts_at)
);

create index staff_time_off_lookup_idx
  on public.staff_time_off (salon_id, starts_at, ends_at);
