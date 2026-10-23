-- 0119 The app, run from the console (decided 23 Oct 2026).
--
-- What the food and grocery apps do - change the home screen, announce
-- something, switch a feature off, ask people to update - without shipping
-- an app update. Five pieces:
--
--   1. salon_app_config: per salon, which home tiles show and in what order,
--      which home sections and in what order, and feature switches. The app
--      reads it on open, on return, every minute while open, and the moment
--      it changes (Realtime).
--   2. salon_announcements: the salon's own news - "Closed on Diwali", "New:
--      keratin" - with start and end dates. Only real announcements: there is
--      no offers feature, and an invented offer is a claim the counter will
--      not keep (DESIGN 14).
--   3. The pulse: every change a customer should see - branding, the menu,
--      the plan, the salon's rules, the config, an announcement - touches
--      salon_app_config.updated_at, so the app watches ONE row per salon and
--      re-reads what changed.
--   4. App versions: the lowest build that may still run (below it, the app
--      asks for an update and does nothing else) and the newest (above an old
--      one, it suggests updating). Set for every salon at once - an app
--      version is not a salon's choice.
--   5. Every write is an app_admin function: audited, and Crayora's alone
--      (RULES 8.12 - no owner path).
--
-- What this is NOT: a way to ship code. New screens and features still need
-- an app update - the stores forbid downloading code to run. What changes
-- here is what the existing screens show.

-- ---------------------------------------------------------------------------
-- 1. Per-salon config
-- ---------------------------------------------------------------------------

create table public.salon_app_config (
  salon_id     uuid primary key references public.salons(id) on delete cascade,
  -- The home grid, in order. Unknown names are refused by the setter.
  home_tiles   text[] not null default
    array['book', 'add_money', 'bookings', 'bills', 'refer', 'birthday', 'profile', 'your_data'],
  -- The home sections below the things somebody is waiting on (a bill,
  -- today's booking, the next one - those stay first, always).
  home_sections text[] not null default array['categories', 'quick', 'services', 'wallet'],
  -- false switches a feature's entry points off in the app. A display switch,
  -- not a security control: the server rules for each feature still apply.
  switches     jsonb not null default '{}'::jsonb,
  min_build    integer not null default 0 check (min_build >= 0),
  latest_build integer not null default 0 check (latest_build >= 0),
  update_url   text,
  version      bigint not null default 1,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.platform_admins(id) on delete set null
);

alter table public.salon_app_config enable row level security;
alter table public.salon_app_config force row level security;

-- Everyone in the salon reads its config; nobody outside it; nobody writes
-- through the API.
create policy salon_app_config on public.salon_app_config
  for select to authenticated using (salon_id = app.current_salon_id());

grant select on public.salon_app_config to authenticated;

-- A row for every salon, now and on provision.
insert into public.salon_app_config (salon_id)
select id from public.salons
on conflict (salon_id) do nothing;

create or replace function app.salon_app_config_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.salon_app_config (salon_id) values (new.id)
  on conflict (salon_id) do nothing;
  return new;
end;
$$;

create trigger salons_app_config_row
  after insert on public.salons
  for each row execute function app.salon_app_config_row();

-- ---------------------------------------------------------------------------
-- 2. Announcements
-- ---------------------------------------------------------------------------

create table public.salon_announcements (
  id          uuid primary key default extensions.gen_random_uuid(),
  salon_id    uuid not null references public.salons(id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 80),
  body        text check (body is null or char_length(body) <= 280),
  title_hi    text check (title_hi is null or char_length(title_hi) <= 80),
  body_hi     text check (body_hi is null or char_length(body_hi) <= 280),
  icon        text not null default 'campaign'
                check (icon in ('campaign', 'event', 'celebration', 'info', 'schedule', 'new')),
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz not null,
  ended_at    timestamptz,
  created_by  uuid references public.platform_admins(id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint salon_announcements_window check (ends_at > starts_at)
);

create index salon_announcements_salon_live_idx
  on public.salon_announcements (salon_id, ends_at desc);

alter table public.salon_announcements enable row level security;
alter table public.salon_announcements force row level security;

-- Only what is live: started, not past its end, not ended early. An expired
-- announcement is not readable from the app at all.
create policy salon_announcements on public.salon_announcements
  for select to authenticated
  using (salon_id = app.current_salon_id()
         and starts_at <= now() and ends_at > now() and ended_at is null);

grant select on public.salon_announcements to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The pulse
-- ---------------------------------------------------------------------------

create or replace function app.touch_app_config(p_salon_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.salon_app_config (salon_id, updated_at)
  values (p_salon_id, now())
  on conflict (salon_id) do update set updated_at = now(), version = public.salon_app_config.version + 1;
$$;

create or replace function app.pulse_from_salon_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.touch_app_config(coalesce(new.salon_id, old.salon_id));
  return null;
end;
$$;

create or replace function app.pulse_from_salons()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.touch_app_config(new.id);
  return null;
end;
$$;

create trigger services_pulse after insert or update or delete on public.services
  for each row execute function app.pulse_from_salon_row();
create trigger add_ons_pulse after insert or update or delete on public.add_ons
  for each row execute function app.pulse_from_salon_row();
create trigger salon_branding_pulse after insert or update on public.salon_branding
  for each row execute function app.pulse_from_salon_row();
create trigger subscriptions_pulse after insert or update on public.subscriptions
  for each row execute function app.pulse_from_salon_row();
create trigger salon_announcements_pulse after insert or update on public.salon_announcements
  for each row execute function app.pulse_from_salon_row();
create trigger salons_pulse after update on public.salons
  for each row execute function app.pulse_from_salons();

-- Realtime: the app subscribes to its own salon's row. RLS decides what a
-- subscriber is sent, exactly as for a read.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.salon_app_config;
  end if;
end;
$$;

-- What the app reads: everything above in one call.
create or replace function public.my_app_config()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'version', c.version,
    'pulse', c.updated_at,
    'home_tiles', to_jsonb(c.home_tiles),
    'home_sections', to_jsonb(c.home_sections),
    'switches', c.switches,
    'min_build', c.min_build,
    'latest_build', c.latest_build,
    'update_url', c.update_url)
    from public.salon_app_config c
   where c.salon_id = app.current_salon_id()
$$;

revoke all on function public.my_app_config() from public, anon;
grant execute on function public.my_app_config() to authenticated;

-- ---------------------------------------------------------------------------
-- 4 and 5. The console's writes
-- ---------------------------------------------------------------------------

create or replace function app_admin.get_app_config(p_actor_admin_id uuid, p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  return (select to_jsonb(c) from public.salon_app_config c where c.salon_id = p_salon_id);
end;
$$;

create or replace function app_admin.set_app_config(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_home_tiles     text[],
  p_home_sections  text[],
  p_switches       jsonb,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tiles    constant text[] := array['book', 'add_money', 'bookings', 'bills', 'refer',
                                      'birthday', 'profile', 'your_data', 'search'];
  v_sections constant text[] := array['categories', 'quick', 'services', 'wallet'];
  v_keys     constant text[] := array['referrals', 'birthday', 'search', 'wallet_topup',
                                      'announcements'];
  v_before   jsonb;
  v_key      text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a change to what customers see needs a reason - it is the audit entry';
  end if;
  if p_home_tiles is null or not (p_home_tiles <@ v_tiles)
     or cardinality(p_home_tiles) <> (select count(distinct t) from unnest(p_home_tiles) t) then
    raise exception 'app_admin: home tiles must be distinct, from %', v_tiles;
  end if;
  if p_home_sections is null or not (p_home_sections <@ v_sections)
     or cardinality(p_home_sections) <> (select count(distinct s) from unnest(p_home_sections) s) then
    raise exception 'app_admin: home sections must be distinct, from %', v_sections;
  end if;
  if jsonb_typeof(coalesce(p_switches, '{}'::jsonb)) <> 'object' then
    raise exception 'app_admin: switches are an object of true/false';
  end if;
  for v_key in select jsonb_object_keys(coalesce(p_switches, '{}'::jsonb)) loop
    if not (v_key = any (v_keys)) or jsonb_typeof(p_switches -> v_key) <> 'boolean' then
      raise exception 'app_admin: unknown or non-boolean switch %', v_key;
    end if;
  end loop;

  select to_jsonb(c) into v_before from public.salon_app_config c where c.salon_id = p_salon_id;
  if v_before is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  update public.salon_app_config
     set home_tiles    = p_home_tiles,
         home_sections = p_home_sections,
         switches      = coalesce(p_switches, '{}'::jsonb),
         version       = version + 1,
         updated_at    = now(),
         updated_by    = p_actor_admin_id
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'app_config.changed', 'salon_app_config', p_salon_id::text,
    btrim(p_reason),
    jsonb_build_object('home_tiles', v_before -> 'home_tiles',
                       'home_sections', v_before -> 'home_sections',
                       'switches', v_before -> 'switches'),
    jsonb_build_object('home_tiles', to_jsonb(p_home_tiles),
                       'home_sections', to_jsonb(p_home_sections),
                       'switches', coalesce(p_switches, '{}'::jsonb)));

  return jsonb_build_object('ok', true);
end;
$$;

-- App versions apply to every salon: a version of the app is not a salon's.
create or replace function app_admin.set_app_versions(
  p_actor_admin_id uuid,
  p_min_build      integer,
  p_latest_build   integer,
  p_update_url     text,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: forcing an update needs a reason - it is the audit entry';
  end if;
  if p_min_build < 0 or p_latest_build < p_min_build then
    raise exception 'app_admin: the newest build cannot be older than the lowest allowed';
  end if;
  if p_update_url is not null and p_update_url !~ '^https://' then
    raise exception 'app_admin: the update link must be https';
  end if;

  update public.salon_app_config
     set min_build = p_min_build,
         latest_build = p_latest_build,
         update_url = nullif(btrim(coalesce(p_update_url, '')), ''),
         version = version + 1,
         updated_at = now(),
         updated_by = p_actor_admin_id;
  get diagnostics v_count = row_count;

  perform app_admin.audit(
    null, p_actor_admin_id, 'app_versions.changed', 'salon_app_config', null,
    btrim(p_reason), null,
    jsonb_build_object('min_build', p_min_build, 'latest_build', p_latest_build,
                       'update_url', p_update_url, 'salons', v_count));

  return jsonb_build_object('ok', true, 'salons', v_count);
end;
$$;

-- Null salons = every salon that is live or being set up.
create or replace function app_admin.publish_announcement(
  p_actor_admin_id uuid,
  p_salon_ids      uuid[],
  p_title          text,
  p_body           text,
  p_title_hi       text,
  p_body_hi        text,
  p_icon           text,
  p_starts_at      timestamptz,
  p_ends_at        timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid;
  v_id    uuid;
  v_count integer := 0;
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  if p_salon_ids is null then
    perform app_admin.assert_super_admin(p_actor_admin_id);
  end if;

  for v_salon in
    select s.id from public.salons s
     where (p_salon_ids is null and s.status in ('active', 'setup'))
        or s.id = any (p_salon_ids)
  loop
    insert into public.salon_announcements
      (salon_id, title, body, title_hi, body_hi, icon, starts_at, ends_at, created_by)
    values
      (v_salon, btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''),
       nullif(btrim(coalesce(p_title_hi, '')), ''), nullif(btrim(coalesce(p_body_hi, '')), ''),
       coalesce(p_icon, 'campaign'), coalesce(p_starts_at, now()), p_ends_at, p_actor_admin_id)
    returning id into v_id;

    perform app_admin.audit(
      v_salon, p_actor_admin_id, 'announcement.published', 'salon_announcements', v_id::text,
      null, null,
      jsonb_build_object('title', btrim(p_title), 'starts_at', coalesce(p_starts_at, now()),
                         'ends_at', p_ends_at));
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'salons', v_count);
end;
$$;

create or replace function app_admin.end_announcement(p_actor_admin_id uuid, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid;
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  update public.salon_announcements set ended_at = now()
   where id = p_id and ended_at is null
  returning salon_id into v_salon;
  if v_salon is null then
    raise exception 'app_admin: no live announcement %', p_id;
  end if;
  perform app_admin.audit(v_salon, p_actor_admin_id, 'announcement.ended',
                          'salon_announcements', p_id::text);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function app_admin.list_announcements(p_actor_admin_id uuid, p_salon_id uuid)
returns table (id uuid, title text, body text, icon text, starts_at timestamptz,
               ends_at timestamptz, ended_at timestamptz, live boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  return query
    select a.id, a.title, a.body, a.icon, a.starts_at, a.ends_at, a.ended_at,
           (a.starts_at <= now() and a.ends_at > now() and a.ended_at is null)
      from public.salon_announcements a
     where a.salon_id = p_salon_id
     order by a.created_at desc
     limit 50;
end;
$$;

select app_admin.close_privileges();
