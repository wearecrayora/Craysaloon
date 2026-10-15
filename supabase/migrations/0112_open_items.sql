-- 0112 The open items, 15 Oct 2026.
--
--   1. Billing notices reach the owner's phone. A notice was a row the console
--      showed and the app displayed only when opened; owner devices register
--      since 0108, so it is now a push to the owner.
--   2. The owner's daily summary: at 9 pm salon time, the day in two numbers,
--      to the owner and managers. Skipped on a day with no visits.
--   3. No photos for a child (DPDP s.9). 0110 refused offers and WhatsApp for a
--      minor; the photos consent is refused the same way, from every path.
--   4. Nomination (DPDP s.14): a customer names someone to exercise their rights
--      if they die or cannot. Theirs alone to set, change or remove; part of the
--      copy of their data; erased with their identity.
--   5. A subscription payment recorded by mistake can be reversed - by a NEW row
--      (the table is append-only), with a reason, audited, once per payment.

-- ---------------------------------------------------------------------------
-- 0. notify_staff learns roles: billing is the owner's business.
-- ---------------------------------------------------------------------------

drop function if exists app.notify_staff(uuid, text, text, jsonb);

create function app.notify_staff(
  p_salon_id     uuid,
  p_purpose      text,
  p_template_key text,
  p_params       jsonb,
  p_roles        text[] default array['owner', 'manager', 'staff']
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_locale text;
  v_count  integer;
begin
  select coalesce(s.languages[1], 'en') into v_locale from public.salons s where s.id = p_salon_id;

  -- Only an ACTIVE login with a live device, in the roles asked for (0111, 0112).
  insert into public.notifications
    (salon_id, user_id, purpose, category, locale, template_key, params, status)
  select p_salon_id, u.id, p_purpose, 'transactional', coalesce(v_locale, 'en'),
         p_template_key, coalesce(p_params, '{}'::jsonb), 'pending'
    from public.users u
   where u.salon_id = p_salon_id
     and u.active
     and u.role::text = any(p_roles)
     and exists (select 1 from public.notification_tokens nt
                  where nt.user_id = u.id and nt.dead_at is null);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function app.notify_staff(uuid, text, text, jsonb, text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Billing notices, pushed to the owner.
-- ---------------------------------------------------------------------------

create or replace function app.on_billing_notice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.notify_staff(new.salon_id, 'staff_billing_' || new.kind, 'staff_billing_' || new.kind,
    jsonb_build_object('kind', new.kind, 'due_at', new.due_at), array['owner']);
  return null;
end;
$$;

revoke all on function app.on_billing_notice() from public, anon, authenticated;

drop trigger if exists billing_notices_tell_owner on public.billing_notices;
create trigger billing_notices_tell_owner
  after insert on public.billing_notices
  for each row execute function app.on_billing_notice();

-- Every push names the salon and never the product (the white-label trigger).
insert into public.message_templates (salon_id, template_key, locale, channel, body) values
  (null, 'staff_billing_grace_started', 'en', 'push', '{{salon}}: your app subscription is due. Renew within 7 days to keep taking bookings.'),
  (null, 'staff_billing_grace_started', 'hi', 'push', '{{salon}}: आपके ऐप की सदस्यता का भुगतान बाकी है। बुकिंग चालू रखने के लिए 7 दिनों में रिन्यू करें।'),
  (null, 'staff_billing_grace_started', 'hi_Latn', 'push', '{{salon}}: aapke app ki subscription ka bhugtan baaki hai. Booking chaalu rakhne ke liye 7 dinon mein renew karein.'),
  (null, 'staff_billing_suspended', 'en', 'push', '{{salon}}: the app is now read-only until the subscription is renewed. Customers can still see their wallets.'),
  (null, 'staff_billing_suspended', 'hi', 'push', '{{salon}}: सदस्यता रिन्यू होने तक ऐप सिर्फ़ देखने के लिए है। ग्राहक अपना वॉलेट अब भी देख सकते हैं।'),
  (null, 'staff_billing_suspended', 'hi_Latn', 'push', '{{salon}}: subscription renew hone tak app sirf dekhne ke liye hai. Customer apna wallet ab bhi dekh sakte hain.'),
  (null, 'staff_billing_retention_60', 'en', 'push', '{{salon}}: your salon''s data will be deleted in 30 days unless the subscription is renewed.'),
  (null, 'staff_billing_retention_60', 'hi', 'push', '{{salon}}: सदस्यता रिन्यू न होने पर आपके सैलून का डेटा 30 दिनों में मिटा दिया जाएगा।'),
  (null, 'staff_billing_retention_60', 'hi_Latn', 'push', '{{salon}}: subscription renew na hone par aapke salon ka data 30 dinon mein mita diya jaayega.'),
  (null, 'staff_billing_retention_80', 'en', 'push', '{{salon}}: your salon''s data will be deleted in 10 days unless the subscription is renewed.'),
  (null, 'staff_billing_retention_80', 'hi', 'push', '{{salon}}: सदस्यता रिन्यू न होने पर आपके सैलून का डेटा 10 दिनों में मिटा दिया जाएगा।'),
  (null, 'staff_billing_retention_80', 'hi_Latn', 'push', '{{salon}}: subscription renew na hone par aapke salon ka data 10 dinon mein mita diya jaayega.'),
  (null, 'staff_billing_purge_due', 'en', 'push', '{{salon}}: your salon''s data is now due for deletion. Contact your account manager today.'),
  (null, 'staff_billing_purge_due', 'hi', 'push', '{{salon}}: आपके सैलून का डेटा अब मिटाए जाने वाला है। आज ही अपने अकाउंट मैनेजर से संपर्क करें।'),
  (null, 'staff_billing_purge_due', 'hi_Latn', 'push', '{{salon}}: aapke salon ka data ab mitaaye jaane wala hai. Aaj hi apne account manager se sampark karein.'),
  (null, 'staff_daily_summary', 'en', 'push', '{{salon}}: today - {{completed}} visits done, {{amount}} billed.'),
  (null, 'staff_daily_summary', 'hi', 'push', '{{salon}}: आज - {{completed}} विज़िट पूरी, {{amount}} का बिल।'),
  (null, 'staff_daily_summary', 'hi_Latn', 'push', '{{salon}}: aaj - {{completed}} visit poori, {{amount}} ka bill.');

-- ---------------------------------------------------------------------------
-- 2. The owner's daily summary, from the minute-by-minute automations.
-- ---------------------------------------------------------------------------

create or replace function app.queue_daily_summary(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz    text;
  v_day   date;
  v_row   record;
  v_sent  integer;
begin
  select coalesce(s.timezone, 'Asia/Kolkata') into v_tz from public.salons s where s.id = p_salon_id;
  -- 9 pm in the SALON's time: the day is mostly over, the owner is still up.
  if extract(hour from (now() at time zone v_tz)) < 21 then
    return jsonb_build_object('ok', true, 'queued', 0);
  end if;
  v_day := app.salon_day(p_salon_id, now());

  -- Once a day: the minute after the first send finds it already queued.
  if exists (select 1 from public.notifications n
              where n.salon_id = p_salon_id and n.purpose = 'staff_daily_summary'
                and n.params ->> 'day' = v_day::text) then
    return jsonb_build_object('ok', true, 'queued', 0);
  end if;

  select m.completed, m.revenue_paise into v_row
    from public.daily_salon_metrics m
   where m.salon_id = p_salon_id and m.day = v_day;

  -- A day with no visits needs no message.
  if coalesce(v_row.completed, 0) = 0 then
    return jsonb_build_object('ok', true, 'queued', 0);
  end if;

  v_sent := app.notify_staff(p_salon_id, 'staff_daily_summary', 'staff_daily_summary',
    jsonb_build_object('day', v_day, 'completed', v_row.completed,
                       'amount_paise', coalesce(v_row.revenue_paise, 0)),
    array['owner', 'manager']);
  return jsonb_build_object('ok', true, 'queued', v_sent);
end;
$$;

revoke all on function app.queue_daily_summary(uuid) from public, anon, authenticated;

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
    'summaries', v_summaries, 'salons_failed', v_failed);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. No photos for a child.
-- ---------------------------------------------------------------------------

create or replace function app.no_marketing_to_children()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Offers, WhatsApp (0110) and photos (0112): none of them for a customer
  -- declared under 18, from any path (DPDP s.9).
  if new.granted
     and new.purpose in ('promotional', 'whatsapp', 'photos')
     and exists (select 1 from public.customers c where c.id = new.customer_id and c.is_minor) then
    raise exception 'consent: a customer under 18 cannot be sent offers or reminders, or photographed (DPDP s.9)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.record_age_declaration(p_auth_user_id uuid, p_age jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_adult    boolean;
  v_guardian text;
  v_customer record;
begin
  if p_age is null or jsonb_typeof(p_age) <> 'object' or not p_age ? 'adult' then
    return jsonb_build_object('ok', false, 'reason', 'not_declared');
  end if;
  v_adult := (p_age ->> 'adult')::boolean;
  v_guardian := nullif(btrim(coalesce(p_age ->> 'guardian_name', '')), '');

  if not v_adult and (v_guardian is null or length(v_guardian) < 2
                      or coalesce((p_age ->> 'guardian_confirms')::boolean, false) is not true) then
    return jsonb_build_object('ok', false, 'reason', 'guardian_required');
  end if;

  update public.customers c
     set is_minor = not v_adult,
         guardian_name = case when v_adult then null else left(v_guardian, 120) end,
         age_declared_at = now(),
         updated_at = now()
   where c.auth_user_id = p_auth_user_id
     and c.anonymised_at is null
  returning c.id, c.salon_id into v_customer;

  if v_customer.id is null then
    return jsonb_build_object('ok', true, 'recorded', false);
  end if;

  if not v_adult then
    -- Whatever was ticked, a child gets no marketing and no photos: withdrawn,
    -- on the record (0110, photos 0112).
    insert into public.consents (salon_id, customer_id, purpose, granted, source)
    values (v_customer.salon_id, v_customer.id, 'promotional', false, 'age_declaration'),
           (v_customer.salon_id, v_customer.id, 'whatsapp', false, 'age_declaration'),
           (v_customer.salon_id, v_customer.id, 'photos', false, 'age_declaration');
  end if;

  return jsonb_build_object('ok', true, 'recorded', true, 'minor', not v_adult);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Nomination (DPDP s.14).
-- ---------------------------------------------------------------------------

create table if not exists public.customer_nominees (
  id           uuid primary key default gen_random_uuid(),
  salon_id     uuid not null references public.salons(id) on delete cascade,
  customer_id  uuid not null unique references public.customers(id) on delete cascade,
  name         text not null check (length(btrim(name)) between 2 and 120),
  phone        text not null,
  relationship text check (relationship is null or length(btrim(relationship)) <= 60),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.customer_nominees is
  'DPDP s.14: the person a customer names to exercise their rights if they die or cannot (0112). Set only by the customer, through set_nominee; erased with the identity.';

alter table public.customer_nominees enable row level security;
alter table public.customer_nominees force row level security;

-- The salon reads it - it is the Data Fiduciary a nominee comes to. Writes go
-- through set_nominee / clear_nominee only: no direct insert or update policy.
create policy customer_nominees on public.customer_nominees
  for select using (salon_id = app.current_salon_id());
create policy customer_scope on public.customer_nominees as restrictive
  using ((app.current_app_role() <> 'customer') or (customer_id = app.current_customer_id()))
  with check ((app.current_app_role() <> 'customer') or (customer_id = app.current_customer_id()));

grant select on public.customer_nominees to authenticated;

create or replace function public.my_nominee()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('name', n.name, 'phone', n.phone, 'relationship', n.relationship,
                            'updated_at', n.updated_at)
    from public.customer_nominees n
   where n.customer_id = app.current_customer_id()
$$;

create or replace function public.set_nominee(p_name text, p_phone text, p_relationship text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
  v_salon    uuid := app.current_salon_id();
  v_phone    text;
begin
  -- The customer's own right: no staff path names a nominee for them. Not
  -- gated on the salon being writable - a right outlives a lapsed subscription.
  if v_customer is null or v_salon is null then
    raise exception 'set_nominee: only the customer names their nominee' using errcode = '42501';
  end if;
  if coalesce(length(btrim(p_name)), 0) < 2 then
    return jsonb_build_object('ok', false, 'reason', 'name_required');
  end if;
  v_phone := app.phone_or_null(p_phone);
  if v_phone is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid_phone');
  end if;

  insert into public.customer_nominees (salon_id, customer_id, name, phone, relationship)
  values (v_salon, v_customer, btrim(p_name), v_phone, nullif(btrim(coalesce(p_relationship, '')), ''))
  on conflict (customer_id) do update
     set name = excluded.name, phone = excluded.phone,
         relationship = excluded.relationship, updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.clear_nominee()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
begin
  if v_customer is null then
    raise exception 'clear_nominee: only the customer removes their nominee' using errcode = '42501';
  end if;
  delete from public.customer_nominees where customer_id = v_customer;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.my_nominee() from public, anon;
revoke all on function public.set_nominee(text, text, text) from public, anon;
revoke all on function public.clear_nominee() from public, anon;
grant execute on function public.my_nominee() to authenticated;
grant execute on function public.set_nominee(text, text, text) to authenticated;
grant execute on function public.clear_nominee() to authenticated;

-- Erasure takes the nominee with the identity.
create or replace function app.erase_nominee_with_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.anonymised_at is not null and old.anonymised_at is null then
    delete from public.customer_nominees where customer_id = new.id;
  end if;
  return null;
end;
$$;

revoke all on function app.erase_nominee_with_identity() from public, anon, authenticated;

drop trigger if exists customers_erase_nominee on public.customers;
create trigger customers_erase_nominee
  after update of anonymised_at on public.customers
  for each row execute function app.erase_nominee_with_identity();

-- The copy of their data names their nominee too.
do $patch$
declare
  v_def text := pg_get_functiondef('app_admin.access_request_export(uuid,uuid)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def,
    $old$    'consents', coalesce((select jsonb_agg(jsonb_build_object($old$,
    $new$    'nominee', (select jsonb_build_object('name', nm.name, 'phone', nm.phone,
                                          'relationship', nm.relationship, 'since', nm.created_at)
                  from public.customer_nominees nm where nm.customer_id = v_req.customer_id),
    'consents', coalesce((select jsonb_agg(jsonb_build_object($new$);
  if v_new = v_def then
    raise exception '0112: access_request_export moved - the nominee was not added';
  end if;
  execute v_new;
end;
$patch$;

-- ---------------------------------------------------------------------------
-- 5. Reversing a subscription payment recorded by mistake.
-- ---------------------------------------------------------------------------

alter table public.subscription_payments
  add column if not exists reverses_id bigint unique references public.subscription_payments(id),
  add column if not exists reason      text;

alter table public.subscription_payments drop constraint if exists subscription_payments_amount_paise_check;
alter table public.subscription_payments drop constraint if exists subscription_payments_months_check;
alter table public.subscription_payments add constraint subscription_payments_amount_and_months check (
  (reverses_id is null and amount_paise > 0 and months between 1 and 24)
  or (reverses_id is not null and amount_paise < 0 and months between -24 and -1
      and length(btrim(coalesce(reason, ''))) > 0));

comment on column public.subscription_payments.reverses_id is
  'A reversal row (0112): negative amount and months, pointing at the payment it undoes. One per payment.';

create or replace function app_admin.reverse_subscription_payment(
  p_actor_admin_id uuid,
  p_payment_id     bigint,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay    record;
  v_renews timestamptz;
  v_id     bigint;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a reversal needs a reason - it is the audit entry';
  end if;

  select * into v_pay from public.subscription_payments where id = p_payment_id;
  if v_pay.id is null then
    raise exception 'app_admin: no such payment';
  end if;
  if v_pay.reverses_id is not null then
    raise exception 'app_admin: a reversal cannot itself be reversed - record the payment again';
  end if;
  if exists (select 1 from public.subscription_payments r where r.reverses_id = v_pay.id) then
    raise exception 'app_admin: that payment has already been reversed';
  end if;

  select renews_at into v_renews
    from public.subscriptions where salon_id = v_pay.salon_id for update;

  insert into public.subscription_payments
    (salon_id, amount_paise, months, period_start, period_end, reference, paid_on, recorded_by,
     reverses_id, reason)
  values
    (v_pay.salon_id, -v_pay.amount_paise, -v_pay.months, v_pay.period_start, v_pay.period_end,
     'reversal of ' || v_pay.reference, current_date, p_actor_admin_id, v_pay.id, btrim(p_reason))
  returning id into v_id;

  -- The months the mistaken payment added come off the paid-until date.
  update public.subscriptions
     set renews_at = renews_at - make_interval(months => v_pay.months), updated_at = now()
   where salon_id = v_pay.salon_id;

  perform app.run_billing_lifecycle();

  perform app_admin.audit(
    v_pay.salon_id, p_actor_admin_id, 'subscription.payment_reversed', 'subscription_payments',
    v_id::text, btrim(p_reason), jsonb_build_object('renews_at', v_renews, 'payment_id', v_pay.id),
    jsonb_build_object('renews_at', v_renews - make_interval(months => v_pay.months)));

  return app.billing_dates(v_pay.salon_id);
end;
$$;

-- The console's payments table shows what was reversed, and by what.
do $patch$
declare
  v_def text := pg_get_functiondef('app_admin.billing_overview(uuid,uuid)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def,
    $old$'recorded_by', a.name) order by p.created_at desc)$old$,
    $new$'recorded_by', a.name, 'reverses_id', p.reverses_id, 'reason', p.reason,
                   'reversed', exists (select 1 from public.subscription_payments r
                                        where r.reverses_id = p.id)) order by p.created_at desc)$new$);
  if v_new = v_def then
    raise exception '0112: billing_overview moved - the reversal fields were not added';
  end if;
  execute v_new;
end;
$patch$;

select app_admin.close_privileges();
