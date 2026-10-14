-- 0108 Push only, for now - and push for the salon's own people.
--
-- Decided 14 Oct 2026: the SMS / WhatsApp fallback is switched OFF platform-wide.
-- Message Central has discontinued the API it ran on (the OTP is a different
-- product and is untouched), and no salon has it configured. The ladder is kept,
-- tested, behind ONE switch - app.paid_fallback_enabled() - so turning it back on
-- is a one-line migration, not a rebuild.
--
-- Found while doing it, and fixed here:
--
--   * Every booking confirmation said "confirmed for {{when}}." - the template
--     asks for {{when}}, the caller passes starts_at, and nothing converted one
--     to the other. Likewise {{amount}}. render_template now fills both from
--     the data, and strips any placeholder left over: a customer is never shown
--     raw braces again.
--   * The wallet receipt was NEVER SENT. The template existed; nothing queued it.
--     A captured top-up now does.
--
-- And the gap the audit named: owners and managers got no notifications at all -
-- register_push_token refused anyone but a customer. Now their devices register,
-- and they hear about a customer's booking, a customer's cancellation, a customer
-- choosing to pay at the counter, and a bill paid online. Push only, never
-- escalated: these are for the salon, not paid messages to a customer.
--
-- A staff message names the customer by looking them up AT SEND TIME (params
-- carry the customer_id, never the name), so an erased customer leaves no name
-- behind in the notification log.

-- ---------------------------------------------------------------------------
-- 1. The switch.
-- ---------------------------------------------------------------------------

create or replace function app.paid_fallback_enabled()
returns boolean
language sql
stable
set search_path = ''
as $$
  -- Off unless a session says otherwise. The reminder test turns it on for its
  -- own transaction, so the ladder behind the switch stays proven (0108).
  select coalesce(current_setting('cray.paid_fallback', true), 'off') = 'on'
$$;

comment on function app.paid_fallback_enabled() is
  'The SMS / WhatsApp / RCS fallback, platform-wide. OFF since 0108: push is the only channel. To turn it back on, replace this body with `select true` in a migration.';

create or replace function app.next_channel(p_salon_id uuid, p_category public.message_category, p_tried public.message_channel[])
returns public.message_channel
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rcs_ok      boolean;
  v_whatsapp_ok boolean;
  v_sms_ok      boolean;
  v_mc_ok       boolean;
  v_prefs       jsonb;
begin
  -- Push is the only channel while the paid fallback is off (0108).
  if not app.paid_fallback_enabled() then
    return null;
  end if;

  select (i.rcs_agent_status = 'verified') into v_rcs_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'rcs';

  select (i.vault_secret_id is not null and i.status <> 'failing'), (i.sender_id is not null)
    into v_mc_ok, v_sms_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'message_central';
  v_sms_ok := coalesce(v_mc_ok, false) and coalesce(v_sms_ok, false);

  select (i.whatsapp_template_status = 'approved' and i.sender_id is not null)
    into v_whatsapp_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'whatsapp';
  v_whatsapp_ok := coalesce(v_mc_ok, false) and coalesce(v_whatsapp_ok, false);

  select coalesce(s.notification_prefs, '{}'::jsonb) into v_prefs
    from public.salons s where s.id = p_salon_id;

  if coalesce(v_rcs_ok, false) and not ('rcs' = any(p_tried)) then
    return 'rcs'::public.message_channel;
  end if;

  if p_category = 'transactional' then
    if v_whatsapp_ok and not ('whatsapp' = any(p_tried)) then
      return 'whatsapp'::public.message_channel;
    end if;
    if v_sms_ok and not ('sms' = any(p_tried)) then
      return 'sms'::public.message_channel;
    end if;
    return null;
  end if;

  if v_sms_ok and not ('sms' = any(p_tried)) then
    return 'sms'::public.message_channel;
  end if;
  if (v_prefs ->> 'marketing_escalation') = 'whatsapp'
     and v_whatsapp_ok
     and not ('whatsapp' = any(p_tried)) then
    return 'whatsapp'::public.message_channel;
  end if;

  return null;
end;
$$;

-- Staff messages are never escalated: they are for the salon's own people.
create or replace function app.escalation_window(p_purpose text)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case
    when p_purpose like 'staff\_%' then null
    else case p_purpose
      when 'booking_confirmed' then interval '5 minutes'
      when 'wallet_receipt'    then interval '15 minutes'
      when 'service_due'       then interval '6 hours'
      when 'billing'           then interval '1 hour'
      when 'visit_completed'   then null
      else interval '1 hour'
    end
  end
$$;

-- ---------------------------------------------------------------------------
-- 2. Rendering: {{when}}, {{amount}}, {{customer}}, and no raw braces, ever.
-- ---------------------------------------------------------------------------

-- Rs 120500.00 -> "₹1,20,500"; paise only when there are any (DESIGN 6.1).
create or replace function app.format_rupees(p_paise bigint)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rupees text := (abs(coalesce(p_paise, 0)) / 100)::text;
  v_paise  int  := (abs(coalesce(p_paise, 0)) % 100)::int;
  v_out    text;
begin
  if length(v_rupees) > 3 then
    v_out := regexp_replace(left(v_rupees, length(v_rupees) - 3), '(\d)(?=(\d\d)+$)', '\1,', 'g')
             || ',' || right(v_rupees, 3);
  else
    v_out := v_rupees;
  end if;
  return case when coalesce(p_paise, 0) < 0 then '-' else '' end
         || '₹' || v_out
         || case when v_paise > 0 then '.' || lpad(v_paise::text, 2, '0') else '' end;
end;
$$;

create or replace function app.render_template(p_salon_id uuid, p_template_key text, p_locale text, p_channel public.message_channel, p_params jsonb default '{}'::jsonb)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_body   text;
  v_salon  text;
  v_tz     text;
  v_params jsonb;
  v_key    text;
  v_val    text;
  v_name   text;
begin
  select t.body into v_body
    from public.message_templates t
   where t.template_key = p_template_key
     and (t.channel = p_channel or (p_channel = 'sms' and t.channel = 'push'))
     and t.locale in (p_locale, 'en')
     and (t.salon_id = p_salon_id or t.salon_id is null)
   order by (t.channel = p_channel) desc, (t.salon_id is not null) desc, (t.locale = p_locale) desc
   limit 1;

  if v_body is null then
    return null;
  end if;

  select s.display_name, coalesce(s.timezone, 'Asia/Kolkata') into v_salon, v_tz
    from public.salons s where s.id = p_salon_id;
  v_body := replace(v_body, '{{salon}}', coalesce(v_salon, ''));

  v_params := case when jsonb_typeof(p_params) = 'object' then p_params else '{}'::jsonb end;

  -- Derived values (0108): the callers pass data, the template asks for words.
  if strpos(v_body, '{{when}}') > 0 and v_params ? 'starts_at' and not v_params ? 'when' then
    v_params := v_params || jsonb_build_object('when',
      to_char((v_params ->> 'starts_at')::timestamptz at time zone v_tz, 'Dy FMDD Mon, FMHH12:MI AM'));
  end if;
  if strpos(v_body, '{{amount}}') > 0 and not v_params ? 'amount' then
    if v_params ? 'amount_paise' then
      v_params := v_params || jsonb_build_object('amount', app.format_rupees((v_params ->> 'amount_paise')::bigint));
    elsif v_params ? 'total_paise' then
      v_params := v_params || jsonb_build_object('amount', app.format_rupees((v_params ->> 'total_paise')::bigint));
    end if;
  end if;
  -- The customer's name is read NOW, never stored in the params: an erased
  -- customer leaves no name in the notification log (0108).
  if strpos(v_body, '{{customer}}') > 0 and v_params ? 'customer_id' and not v_params ? 'customer' then
    select coalesce(nullif(btrim(c.name), ''), '****' || right(coalesce(c.phone, ''), 4))
      into v_name
      from public.customers c
     where c.id = (v_params ->> 'customer_id')::uuid and c.salon_id = p_salon_id;
    v_params := v_params || jsonb_build_object('customer', coalesce(v_name, ''));
  end if;

  for v_key, v_val in select key, value #>> '{}' from jsonb_each(v_params)
  loop
    v_body := replace(v_body, '{{' || v_key || '}}', coalesce(v_val, ''));
  end loop;

  -- Anything still in braces had no value: drop it rather than show it.
  v_body := regexp_replace(v_body, '\{\{[a-z_]+\}\}', '', 'g');
  return btrim(regexp_replace(v_body, '\s{2,}', ' ', 'g'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Who is signed in, if it is one of the salon's own people.
-- ---------------------------------------------------------------------------

create or replace function app.current_staff_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
    from public.users u
   where u.auth_user_id = auth.uid()
     and u.salon_id = app.current_salon_id()
     and u.active
     and app.current_app_role() in ('owner', 'manager', 'staff')
   limit 1
$$;

revoke all on function app.current_staff_user_id() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Their devices register; their pushes can be acknowledged.
-- ---------------------------------------------------------------------------

create or replace function public.register_push_token(p_token text, p_platform text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_user     uuid;
begin
  if v_salon is null then
    raise exception 'register_push_token: no salon in this session' using errcode = '42501';
  end if;
  if v_customer is null then
    v_user := app.current_staff_user_id();
    if v_user is null then
      raise exception 'register_push_token: no customer or staff member in this session'
        using errcode = '42501';
    end if;
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'register_push_token: a token is required';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'register_push_token: platform must be android or ios';
  end if;

  -- The token is globally unique and follows whoever now holds the device - a
  -- customer or one of the salon's people, never both (notification_tokens_has_owner).
  insert into public.notification_tokens
    (salon_id, customer_id, user_id, token, platform, dead_at, updated_at)
  values (v_salon, v_customer, v_user, btrim(p_token), p_platform, null, now())
  on conflict (token) do update
     set salon_id = excluded.salon_id,
         customer_id = excluded.customer_id,
         user_id = excluded.user_id,
         platform = excluded.platform,
         dead_at = null,
         updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.ack_notification(p_delivery_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
  v_user     uuid;
  v_row      record;
begin
  if v_customer is null then
    v_user := app.current_staff_user_id();
  end if;
  if v_customer is null and v_user is null then
    raise exception 'ack_notification: only the recipient may acknowledge'
      using errcode = '42501';
  end if;

  select d.id, d.acked_at, n.id as notification_id, n.status
    into v_row
    from public.notification_deliveries d
    join public.notifications n on n.id = d.notification_id
   where d.id = p_delivery_id
     and ((v_customer is not null and n.customer_id = v_customer)
       or (v_user is not null and n.user_id = v_user));

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v_row.acked_at is not null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.notification_deliveries set acked_at = now() where id = p_delivery_id;

  update public.notifications
     set status = 'acked'
   where id = v_row.notification_id and status in ('pending', 'sent');

  return jsonb_build_object('ok', true, 'already', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The dispatcher finds a staff member's device too.
-- ---------------------------------------------------------------------------

create or replace function app.claim_notification_batch(p_salon_id uuid, p_limit integer default 50)
returns table(delivery_id uuid, notification_id uuid, channel public.message_channel, customer_id uuid,
              token text, platform text, body text, purpose text, category public.message_category,
              phone text, sender_id text, wa_template text, wa_lang text, wa_variables text[])
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into public.notification_deliveries (salon_id, notification_id, channel, provider_status)
  select n.salon_id, n.id,
         case when t.token is not null then 'push'::public.message_channel
              else app.next_channel(n.salon_id, n.category, '{push}') end,
         'queued'
    from public.notifications n
    left join lateral (
      select nt.token from public.notification_tokens nt
       where nt.dead_at is null
         and ((n.customer_id is not null and nt.customer_id = n.customer_id)
           or (n.user_id is not null and nt.user_id = n.user_id))
       order by nt.updated_at desc limit 1
    ) t on true
   where n.salon_id = p_salon_id
     and n.status = 'pending'
     and not exists (
       select 1 from public.notification_deliveries d where d.notification_id = n.id)
     and (t.token is not null
          or (app.escalation_window(n.purpose) is not null
              and app.next_channel(n.salon_id, n.category, '{push}') is not null))
   limit greatest(coalesce(p_limit, 50), 1);

  return query
    with picked as (
      select d.id
        from public.notification_deliveries d
       where d.salon_id = p_salon_id
         and d.provider_status = 'queued'
         and d.sent_at is null
         and (d.claimed_at is null or d.claimed_at < now() - interval '5 minutes')
       order by d.created_at
       limit greatest(coalesce(p_limit, 50), 1)
       for update skip locked
    ), claimed as (
      update public.notification_deliveries d
         set claimed_at = now()
        from picked p
       where d.id = p.id
      returning d.id, d.notification_id, d.channel, d.created_at
    )
    select c.id, c.notification_id, c.channel, n.customer_id,
           t.token, t.platform,
           app.render_template(n.salon_id, n.template_key, n.locale, c.channel, n.params),
           n.purpose,
           n.category,
           case when c.channel in ('sms', 'whatsapp')
                then app.phone_or_null(coalesce(cu.phone, us.phone)) end,
           case c.channel when 'sms' then mc.sender_id
                          when 'whatsapp' then wa.sender_id end,
           wt.provider_template_id,
           wt.provider_lang,
           case when wt.provider_template_id is not null then
             (select array_agg(case v when 'salon' then coalesce(s.display_name, '')
                                      else coalesce(n.params ->> v, '') end
                               order by o)
                from unnest(wt.provider_variables) with ordinality as u(v, o))
           end
      from claimed c
      join public.notifications n on n.id = c.notification_id
      join public.salons s on s.id = n.salon_id
      left join public.customers cu on cu.id = n.customer_id
      left join public.users us on us.id = n.user_id
      left join public.salon_integrations mc
             on mc.salon_id = n.salon_id and mc.provider = 'message_central'
      left join public.salon_integrations wa
             on wa.salon_id = n.salon_id and wa.provider = 'whatsapp'
      left join lateral (
        select nt.token, nt.platform from public.notification_tokens nt
         where nt.dead_at is null
           and ((n.customer_id is not null and nt.customer_id = n.customer_id)
             or (n.user_id is not null and nt.user_id = n.user_id))
         order by nt.updated_at desc limit 1
      ) t on true
      left join lateral (
        select mt.provider_template_id, mt.provider_lang, mt.provider_variables
          from public.message_templates mt
         where c.channel = 'whatsapp'
           and mt.channel = 'whatsapp'
           and mt.template_key = n.template_key
           and mt.salon_id = n.salon_id
           and mt.locale in (n.locale, 'en')
           and mt.provider_template_id is not null
         order by (mt.locale = n.locale) desc
         limit 1
      ) wt on true
     order by c.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Telling the salon's people.
-- ---------------------------------------------------------------------------

-- One notification per owner or manager with a live device. Nobody without a
-- device is queued for: there is no fallback for staff, so the row would only
-- wait forever.
create or replace function app.notify_staff(p_salon_id uuid, p_purpose text, p_template_key text, p_params jsonb)
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

  insert into public.notifications
    (salon_id, user_id, purpose, category, locale, template_key, params, status)
  select p_salon_id, u.id, p_purpose, 'transactional', coalesce(v_locale, 'en'),
         p_template_key, coalesce(p_params, '{}'::jsonb), 'pending'
    from public.users u
   where u.salon_id = p_salon_id
     and u.active
     and u.role in ('owner', 'manager')
     and exists (select 1 from public.notification_tokens nt
                  where nt.user_id = u.id and nt.dead_at is null);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function app.notify_staff(uuid, text, text, jsonb) from public, anon, authenticated;

-- A booking the CUSTOMER made, or cancelled. The salon's own bookings and
-- cancellations need no announcement - the person who made them is there.
create or replace function app.on_booking_for_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if app.current_app_role() <> 'customer' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform app.notify_staff(new.salon_id, 'staff_new_booking', 'staff_new_booking',
      jsonb_build_object('customer_id', new.customer_id, 'starts_at', new.starts_at,
                         'booking_id', new.id));
  elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform app.notify_staff(new.salon_id, 'staff_booking_cancelled', 'staff_booking_cancelled',
      jsonb_build_object('customer_id', new.customer_id, 'starts_at', new.starts_at,
                         'booking_id', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists bookings_tell_staff on public.bookings;
create trigger bookings_tell_staff
  after insert or update of status on public.bookings
  for each row execute function app.on_booking_for_staff();

create or replace function app.on_counter_request_for_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.counter_payment_requested_at is not null and old.counter_payment_requested_at is null then
    perform app.notify_staff(new.salon_id, 'staff_counter_payment', 'staff_counter_payment',
      jsonb_build_object('customer_id', new.customer_id, 'visit_id', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists visits_tell_staff on public.visits;
create trigger visits_tell_staff
  after update of counter_payment_requested_at on public.visits
  for each row execute function app.on_counter_request_for_staff();

-- A captured payment: the customer gets the wallet receipt that was never sent
-- (a top-up), the salon hears a bill was paid (a visit).
create or replace function app.on_payment_captured()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'captured' and old.status is distinct from 'captured' then
    if new.visit_id is null then
      perform app.notify(new.salon_id, new.customer_id, 'wallet_receipt', 'transactional',
                         'wallet_receipt',
                         jsonb_build_object('amount_paise', new.amount_paise, 'payment_id', new.id));
    else
      perform app.notify_staff(new.salon_id, 'staff_bill_paid', 'staff_bill_paid',
        jsonb_build_object('customer_id', new.customer_id, 'amount_paise', new.amount_paise,
                           'visit_id', new.visit_id));
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists payments_captured_notify on public.payments;
create trigger payments_captured_notify
  after update of status on public.payments
  for each row execute function app.on_payment_captured();

revoke all on function app.on_booking_for_staff() from public, anon, authenticated;
revoke all on function app.on_counter_request_for_staff() from public, anon, authenticated;
revoke all on function app.on_payment_captured() from public, anon, authenticated;

-- The words. Every push names the salon (PRD 6.6); none names the product.
insert into public.message_templates (salon_id, template_key, locale, channel, body) values
  (null, 'staff_new_booking', 'en', 'push', '{{salon}}: new booking - {{customer}}, {{when}}.'),
  (null, 'staff_new_booking', 'hi', 'push', '{{salon}}: नई बुकिंग - {{customer}}, {{when}}।'),
  (null, 'staff_new_booking', 'hi_Latn', 'push', '{{salon}}: nayi booking - {{customer}}, {{when}}.'),
  (null, 'staff_booking_cancelled', 'en', 'push', '{{salon}}: {{customer}} cancelled their booking for {{when}}.'),
  (null, 'staff_booking_cancelled', 'hi', 'push', '{{salon}}: {{customer}} ने {{when}} की बुकिंग रद्द की।'),
  (null, 'staff_booking_cancelled', 'hi_Latn', 'push', '{{salon}}: {{customer}} ne {{when}} ki booking cancel ki.'),
  (null, 'staff_counter_payment', 'en', 'push', '{{salon}}: {{customer}} will pay at the counter.'),
  (null, 'staff_counter_payment', 'hi', 'push', '{{salon}}: {{customer}} काउंटर पर भुगतान करेंगे।'),
  (null, 'staff_counter_payment', 'hi_Latn', 'push', '{{salon}}: {{customer}} counter par payment karenge.'),
  (null, 'staff_bill_paid', 'en', 'push', '{{salon}}: {{customer}} paid {{amount}} online.'),
  (null, 'staff_bill_paid', 'hi', 'push', '{{salon}}: {{customer}} ने {{amount}} ऑनलाइन चुकाए।'),
  (null, 'staff_bill_paid', 'hi_Latn', 'push', '{{salon}}: {{customer}} ne {{amount}} online chukaye.');

-- The receipt's second line was never filled; the sentence stands without it.
update public.message_templates
   set body = replace(body, ' {{bonus_line}}', ''), updated_at = now()
 where template_key = 'wallet_receipt' and salon_id is null;
