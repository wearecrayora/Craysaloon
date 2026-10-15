-- 0113 The birthday offer (PRD 10.5, Automation F's birthday half) - and a
-- hole found while building it.
--
-- THE HOLE. `authenticated` held UPDATE (and INSERT) on every column of
-- `customers`, and the policies limit which ROWS, never which COLUMNS. So a
-- customer could rewrite their own loyalty_points, status, phone_hash,
-- auth_user_id or is_minor; salon staff could do the same to any customer of
-- theirs - flip a child to an adult, say. No client writes this table directly
-- (every write is a server function), so the grant is cut to what a person may
-- edit about themselves: their name and their language.
--
-- THE OFFER.
--   * the OWNER words it (salons.birthday_offer, e.g. "a free head massage") -
--     a description honoured at the counter, never wallet credit, so no new
--     ledger caller (RULES 5.2);
--   * the CUSTOMER adds their birthday - day and month only, no year, optional,
--     removable - and never if they are under 18 (no date of birth for a child,
--     0110/0112); a trigger clears it for a minor whatever path wrote it;
--   * on the day, from 10 am salon time, a push: marketing, so only with the
--     offers consent (app.notify suppresses it otherwise), and ONCE a year,
--     enforced by a unique constraint (PRD 10.5 AC);
--   * through the birthday month the customer's home shows the offer to show
--     at the counter.

-- ---------------------------------------------------------------------------
-- 0. Column grants: a person edits their name and language, nothing else.
-- ---------------------------------------------------------------------------

revoke insert, update on public.customers from authenticated;
grant update (name, language) on public.customers to authenticated;

-- ---------------------------------------------------------------------------
-- 1. The owner's offer.
-- ---------------------------------------------------------------------------

alter table public.salons
  add column if not exists birthday_offer text
    check (birthday_offer is null or length(btrim(birthday_offer)) between 2 and 120);

comment on column public.salons.birthday_offer is
  'What the salon gives on a customer''s birthday, in the owner''s words (0113). Null = no birthday offer. A description honoured at the counter - never wallet credit.';

grant select (birthday_offer) on public.salons to authenticated;

create or replace function public.set_birthday_offer(p_offer text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon  uuid := app.current_salon_id();
  v_before text;
  v_offer  text := nullif(btrim(coalesce(p_offer, '')), '');
begin
  if v_salon is null or app.current_app_role() is distinct from 'owner' then
    raise exception 'set_birthday_offer: only the salon''s owner words the birthday offer'
      using errcode = '42501';
  end if;
  if v_offer is not null and length(v_offer) not between 2 and 120 then
    return jsonb_build_object('ok', false, 'reason', 'length');
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  select s.birthday_offer into v_before from public.salons s where s.id = v_salon for update;
  update public.salons set birthday_offer = v_offer, updated_at = now() where id = v_salon;

  insert into public.audit_log (salon_id, actor_user_id, actor_kind, action, entity,
                                entity_id, before_state, after_state)
  values (v_salon, auth.uid(), 'owner', 'salon.birthday_offer_set', 'salons', v_salon::text,
          jsonb_build_object('birthday_offer', v_before),
          jsonb_build_object('birthday_offer', v_offer));

  return jsonb_build_object('ok', true, 'birthday_offer', v_offer);
end;
$$;

revoke all on function public.set_birthday_offer(text) from public, anon;
grant execute on function public.set_birthday_offer(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The customer's birthday: day and month, never the year, never a child's.
-- ---------------------------------------------------------------------------

comment on column public.customers.birthday is
  'Day and month only (0113): stored in the year 2000, which keeps 29 February. The year is never asked. Never set for a customer under 18.';

-- Whatever wrote it: a child has no date of birth on record (DPDP s.9).
create or replace function app.no_dates_for_children()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_minor then
    new.birthday := null;
    new.anniversary := null;
  end if;
  return new;
end;
$$;

revoke all on function app.no_dates_for_children() from public, anon, authenticated;

drop trigger if exists customers_no_dates_for_children on public.customers;
create trigger customers_no_dates_for_children
  before insert or update on public.customers
  for each row execute function app.no_dates_for_children();

create or replace function public.set_my_birthday(p_month integer, p_day integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
  v_minor    boolean;
  v_date     date;
begin
  -- The customer's own, and optional: nobody else adds it for them.
  if v_customer is null then
    raise exception 'set_my_birthday: only the customer adds their birthday' using errcode = '42501';
  end if;
  select c.is_minor into v_minor from public.customers c where c.id = v_customer;
  if v_minor then
    return jsonb_build_object('ok', false, 'reason', 'minor');
  end if;

  if p_month is null and p_day is null then
    update public.customers set birthday = null, updated_at = now() where id = v_customer;
    return jsonb_build_object('ok', true, 'birthday', null);
  end if;
  begin
    v_date := make_date(2000, p_month, p_day);
  exception when others then
    return jsonb_build_object('ok', false, 'reason', 'invalid_date');
  end;

  update public.customers set birthday = v_date, updated_at = now() where id = v_customer;
  return jsonb_build_object('ok', true, 'month', p_month, 'day', p_day);
end;
$$;

revoke all on function public.set_my_birthday(integer, integer) from public, anon;
grant execute on function public.set_my_birthday(integer, integer) to authenticated;

-- What the customer's home shows through their birthday month: the salon's
-- offer, to show at the counter. Nothing outside that month, or with no offer.
create or replace function public.my_birthday_offer()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('offer', s.birthday_offer,
                            'month', extract(month from c.birthday)::int,
                            'day', extract(day from c.birthday)::int)
    from public.customers c
    join public.salons s on s.id = c.salon_id
   where c.id = app.current_customer_id()
     and not c.is_minor
     and c.birthday is not null
     and s.birthday_offer is not null
     and extract(month from c.birthday)
         = extract(month from (now() at time zone coalesce(s.timezone, 'Asia/Kolkata')))
$$;

revoke all on function public.my_birthday_offer() from public, anon;
grant execute on function public.my_birthday_offer() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Once a year, by constraint.
-- ---------------------------------------------------------------------------

create table if not exists public.lifecycle_messages (
  salon_id    uuid not null references public.salons(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  kind        text not null check (kind in ('birthday')),
  period      text not null,
  sent_at     timestamptz not null default now(),
  constraint lifecycle_messages_once unique (customer_id, kind, period)
);

comment on table public.lifecycle_messages is
  'One row per lifecycle message per period (0113, PRD 10.5): the unique constraint is what makes a birthday offer fire once a year, however often the scan runs.';

alter table public.lifecycle_messages enable row level security;
alter table public.lifecycle_messages force row level security;
create policy lifecycle_messages on public.lifecycle_messages
  for select using (salon_id = app.current_salon_id());
create policy customer_scope on public.lifecycle_messages as restrictive
  using ((app.current_app_role() <> 'customer') or (customer_id = app.current_customer_id()))
  with check ((app.current_app_role() <> 'customer') or (customer_id = app.current_customer_id()));
grant select on public.lifecycle_messages to authenticated;

create or replace function app.queue_birthday_offers(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon  record;
  v_local  timestamp;
  v_today  date;
  v_leap   boolean;
  v_row    record;
  v_queued integer := 0;
begin
  select s.birthday_offer, coalesce(s.timezone, 'Asia/Kolkata') as tz into v_salon
    from public.salons s where s.id = p_salon_id;
  if v_salon.birthday_offer is null then
    return jsonb_build_object('ok', true, 'queued', 0);
  end if;

  v_local := now() at time zone v_salon.tz;
  -- From 10 am: a birthday wish at dawn is an alarm, not a gift.
  if extract(hour from v_local) < 10 then
    return jsonb_build_object('ok', true, 'queued', 0);
  end if;
  v_today := v_local::date;
  v_leap := extract(year from v_today)::int % 4 = 0
            and (extract(year from v_today)::int % 100 <> 0
                 or extract(year from v_today)::int % 400 = 0);

  for v_row in
    select c.id
      from public.customers c
     where c.salon_id = p_salon_id
       and c.anonymised_at is null
       and not c.is_minor
       and c.birthday is not null
       and (
         (extract(month from c.birthday) = extract(month from v_today)
          and extract(day from c.birthday) = extract(day from v_today))
         -- 29 February, in a year without one: the 28th.
         or (not v_leap and extract(month from v_today) = 2 and extract(day from v_today) = 28
             and extract(month from c.birthday) = 2 and extract(day from c.birthday) = 29)
       )
  loop
    insert into public.lifecycle_messages (salon_id, customer_id, kind, period)
    values (p_salon_id, v_row.id, 'birthday', extract(year from v_today)::text)
    on conflict (customer_id, kind, period) do nothing;
    if found then
      -- Marketing: app.notify suppresses it without the offers consent.
      perform app.notify(p_salon_id, v_row.id, 'birthday_offer', 'marketing', 'birthday_offer',
        jsonb_build_object('customer_id', v_row.id, 'gift', v_salon.birthday_offer));
      v_queued := v_queued + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'queued', v_queued);
end;
$$;

revoke all on function app.queue_birthday_offers(uuid) from public, anon, authenticated;

create or replace function app.run_due_automations(p_nudge_days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon   record;
  v_escalated integer := 0;
  v_expired   integer := 0;
  v_nudged    integer := 0;
  v_reminded  integer := 0;
  v_referred  integer := 0;
  v_summaries integer := 0;
  v_birthdays integer := 0;
  v_failed    integer := 0;
  v_result  jsonb;
begin
  for v_salon in
    select s.id from public.salons s where s.status in ('active', 'grace')
  loop
    begin
      v_result := app.send_due_reminders(v_salon.id);
      v_reminded := v_reminded + coalesce((v_result ->> 'sent')::integer, 0);

      v_result := app.release_due_referrals(v_salon.id);
      v_referred := v_referred + coalesce((v_result ->> 'released')::integer, 0);

      v_result := app.escalate_due_deliveries(v_salon.id);
      v_escalated := v_escalated + coalesce((v_result ->> 'escalated')::integer, 0);

      v_result := app.expire_due_bonus_lots(v_salon.id);
      v_expired := v_expired + coalesce((v_result ->> 'lots_expired')::integer, 0);

      v_result := app.nudge_expiring_bonus(v_salon.id, p_nudge_days);
      v_nudged := v_nudged + coalesce((v_result ->> 'nudged')::integer, 0);

      -- 0112: the owner's day, at 9 pm salon time.
      v_result := app.queue_daily_summary(v_salon.id);
      v_summaries := v_summaries + coalesce((v_result ->> 'queued')::integer, 0);

      -- 0113: birthday offers, from 10 am salon time, once a year each.
      v_result := app.queue_birthday_offers(v_salon.id);
      v_birthdays := v_birthdays + coalesce((v_result ->> 'queued')::integer, 0);
    exception when others then
      v_failed := v_failed + 1;
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (v_salon.id, 'automation.failed', null,
              jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok', true, 'reminded', v_reminded, 'referrals_released', v_referred,
    'escalated', v_escalated, 'expired', v_expired, 'nudged', v_nudged,
    'summaries', v_summaries, 'birthdays', v_birthdays, 'salons_failed', v_failed);
end;
$$;

-- The words. Every push names the salon (PRD 6.6); the gift is the owner's.
insert into public.message_templates (salon_id, template_key, locale, channel, body) values
  (null, 'birthday_offer', 'en', 'push', '{{salon}}: happy birthday, {{customer}}! {{gift}} is waiting for you this month.'),
  (null, 'birthday_offer', 'hi', 'push', '{{salon}}: जन्मदिन मुबारक, {{customer}}! इस महीने आपके लिए {{gift}} रखा है।'),
  (null, 'birthday_offer', 'hi_Latn', 'push', '{{salon}}: janamdin mubarak, {{customer}}! Is mahine aapke liye {{gift}} rakha hai.');
