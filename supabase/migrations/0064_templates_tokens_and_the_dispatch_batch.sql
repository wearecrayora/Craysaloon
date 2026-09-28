-- 0064 What the dispatcher needs: a token, a body, and a batch to send
--
-- Three things M8 still owed, and one seed.
--
--   * `register_push_token` - the app's side of "push is the free channel".
--   * `render_template` - bodies live in the DATABASE, not in the Flutter ARB
--     bundle, because push, SMS and WhatsApp all originate on the server
--     (ARCHITECTURE 12.5).
--   * `claim_notification_batch` / `record_send` - the dispatcher's two calls.
--     It claims by WRITING the delivery row first, so a crash mid-send leaves a
--     row saying "we tried", never a notification that silently sends twice.
--
-- The seed is the Crayora default push templates in all three locales. Every
-- one of them says `{{salon}}`, which resolves to the salon's display name -
-- and a trigger refuses any template that hard-codes a product name, because a
-- white-labelled app that says "Cray Salon" to a customer has broken the one
-- promise the whole product is sold on (PRD 6.6).

-- ---------------------------------------------------------------------------
-- 1. The device token
-- ---------------------------------------------------------------------------

create or replace function public.register_push_token(
  p_token    text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
begin
  if v_salon is null or v_customer is null then
    raise exception 'register_push_token: no customer in this session'
      using errcode = '42501';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'register_push_token: a token is required';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'register_push_token: platform must be android or ios';
  end if;

  -- The token is globally unique: FCM can hand the same device token to a
  -- reinstalled app, and it must follow the customer it now belongs to rather
  -- than keep pointing at whoever had it before. `dead_at = null` revives a
  -- token FCM previously rejected - a reinstall is exactly how that happens.
  insert into public.notification_tokens
    (salon_id, customer_id, token, platform, dead_at, updated_at)
  values (v_salon, v_customer, btrim(p_token), p_platform, null, now())
  on conflict (token) do update
     set salon_id = excluded.salon_id,
         customer_id = excluded.customer_id,
         user_id = null,
         platform = excluded.platform,
         dead_at = null,
         updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.register_push_token is
  'The app''s side of the free channel. Upserts on the token, because FCM reissues one to a reinstalled app - and revives a token previously marked dead, since a reinstall is exactly how a dead token comes back.';

revoke all on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Bodies, and the rule that keeps them the salon's
-- ---------------------------------------------------------------------------

create or replace function app.templates_are_white_labelled()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- PRD 6.6: after binding, the app is the SALON's app. A template that names
  -- the product to a customer breaks that in the most visible place there is.
  if new.body ~* '(cray[ -]?salon|crayora)' then
    raise exception
      'message_templates: a customer-facing body may not name the product. '
      'Use {{salon}}, which resolves to the salon''s display name (ARCH 12.5).';
  end if;
  if new.channel = 'push' and new.body !~ '\{\{salon\}\}' then
    raise exception
      'message_templates: a push body must carry {{salon}} - every message is '
      'branded as the salon''s (PRD 6.6).';
  end if;
  return new;
end;
$$;

drop trigger if exists message_templates_white_label on public.message_templates;
create trigger message_templates_white_label
  before insert or update on public.message_templates
  for each row execute function app.templates_are_white_labelled();

create or replace function app.render_template(
  p_salon_id     uuid,
  p_template_key text,
  p_locale       text,
  p_channel      public.message_channel,
  p_params       jsonb default '{}'::jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_body  text;
  v_salon text;
  v_key   text;
  v_val   text;
begin
  -- The salon's own row wins; the Crayora default is the fallback. Locale falls
  -- back to English rather than to nothing: a message in the wrong language
  -- still arrives, and no message does not.
  select t.body into v_body
    from public.message_templates t
   where t.template_key = p_template_key
     and t.channel = p_channel
     and t.locale in (p_locale, 'en')
     and (t.salon_id = p_salon_id or t.salon_id is null)
   order by (t.salon_id is not null) desc, (t.locale = p_locale) desc
   limit 1;

  if v_body is null then
    return null;
  end if;

  select s.display_name into v_salon from public.salons s where s.id = p_salon_id;
  v_body := replace(v_body, '{{salon}}', coalesce(v_salon, ''));

  for v_key, v_val in select key, value #>> '{}' from jsonb_each(coalesce(p_params, '{}'::jsonb))
  loop
    v_body := replace(v_body, '{{' || v_key || '}}', coalesce(v_val, ''));
  end loop;

  return v_body;
end;
$$;

comment on function app.render_template is
  'Server-side rendering (ARCHITECTURE 12.5): push, SMS and WhatsApp all originate here, so bodies cannot live in the app''s ARB bundle. The salon''s own template beats the Crayora default; a missing locale falls back to English, because a message in the wrong language still arrives and no message does not.';

-- The Crayora defaults. Three keys, three locales, push only - WhatsApp and RCS
-- bodies are authored in the salon's own Message Central dashboard and we store
-- only the identifier (12.5a).
insert into public.message_templates (salon_id, template_key, locale, channel, body)
values
  (null, 'booking_confirmed', 'en', 'push',
   '{{salon}}: your appointment is confirmed for {{when}}.'),
  (null, 'booking_confirmed', 'hi', 'push',
   '{{salon}}: आपका अपॉइंटमेंट {{when}} के लिए तय हो गया है।'),
  (null, 'booking_confirmed', 'hi_Latn', 'push',
   '{{salon}}: aapka appointment {{when}} ke liye tay ho gaya hai.'),

  (null, 'service_due', 'en', 'push',
   '{{salon}}: it has been a while. Book your next visit whenever you are ready.'),
  (null, 'service_due', 'hi', 'push',
   '{{salon}}: काफ़ी समय हो गया है। जब सुविधा हो, अपनी अगली विज़िट बुक कर लें।'),
  (null, 'service_due', 'hi_Latn', 'push',
   '{{salon}}: kaafi samay ho gaya hai. Jab suvidha ho, apni agli visit book kar lein.'),

  (null, 'wallet_receipt', 'en', 'push',
   '{{salon}}: {{amount}} added to your wallet. {{bonus_line}}'),
  (null, 'wallet_receipt', 'hi', 'push',
   '{{salon}}: आपके वॉलेट में {{amount}} जुड़ गए। {{bonus_line}}'),
  (null, 'wallet_receipt', 'hi_Latn', 'push',
   '{{salon}}: aapke wallet mein {{amount}} jud gaye. {{bonus_line}}')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. The dispatcher's two calls
-- ---------------------------------------------------------------------------

create or replace function app.claim_notification_batch(
  p_salon_id uuid,
  p_limit    integer default 50
)
returns table (
  delivery_id     uuid,
  notification_id uuid,
  channel         public.message_channel,
  customer_id     uuid,
  token           text,
  platform        text,
  body            text,
  purpose         text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A pending notification with no delivery yet gets its first rung: push, if
  -- the customer has a live token. No token means push is skipped entirely and
  -- the ladder starts lower - waiting out a window for a device that cannot
  -- receive is the mistake token hygiene exists to prevent (12.3).
  insert into public.notification_deliveries (salon_id, notification_id, channel, provider_status)
  select n.salon_id, n.id,
         case when t.token is not null then 'push'::public.message_channel
              else app.next_channel(n.salon_id, n.category, '{push}') end,
         'queued'
    from public.notifications n
    left join lateral (
      select nt.token from public.notification_tokens nt
       where nt.customer_id = n.customer_id and nt.dead_at is null
       order by nt.updated_at desc limit 1
    ) t on true
   where n.salon_id = p_salon_id
     and n.status = 'pending'
     and not exists (
       select 1 from public.notification_deliveries d where d.notification_id = n.id)
     and (t.token is not null
          or app.next_channel(n.salon_id, n.category, '{push}') is not null)
   limit greatest(coalesce(p_limit, 50), 1);

  -- Everything queued for this salon, with what it takes to send it. Claiming
  -- is the row that already exists - a crash mid-send leaves "we tried", never
  -- a notification that quietly sends twice.
  return query
    select d.id, d.notification_id, d.channel, n.customer_id,
           t.token, t.platform,
           app.render_template(n.salon_id, n.template_key, n.locale, d.channel, n.params),
           n.purpose
      from public.notification_deliveries d
      join public.notifications n on n.id = d.notification_id
      left join lateral (
        select nt.token, nt.platform from public.notification_tokens nt
         where nt.customer_id = n.customer_id and nt.dead_at is null
         order by nt.updated_at desc limit 1
      ) t on true
     where d.salon_id = p_salon_id
       and d.provider_status = 'queued'
       and d.sent_at is null
     order by d.created_at
     limit greatest(coalesce(p_limit, 50), 1);
end;
$$;

comment on function app.claim_notification_batch is
  'The dispatcher''s read. Opens the first rung for anything pending - push when the customer has a live token, the next usable channel when they do not - and hands back the rendered body. A customer with no token does not wait out a push window for a device that cannot receive.';

create or replace function app.record_send(
  p_delivery_id  uuid,
  p_status       text,
  p_provider_message_id text default null,
  p_failure_reason text default null,
  p_cost_paise   bigint default 0
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_notification uuid;
begin
  update public.notification_deliveries
     set provider_status = p_status,
         provider_message_id = p_provider_message_id,
         failure_reason = p_failure_reason,
         cost_paise = greatest(coalesce(p_cost_paise, 0), 0),
         sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_delivery_id
  returning notification_id into v_notification;

  if v_notification is null then
    return;
  end if;

  -- `sent` is not `delivered` and is certainly not `acked`. The notification
  -- only leaves `sent` when the app says the message arrived, or when the sweep
  -- gives up on the window (12.3).
  if p_status = 'sent' then
    update public.notifications
       set status = 'sent'
     where id = v_notification and status = 'pending';
  end if;

  -- The salon's cost, not Crayora's (12.4). Reported to the owner beside the
  -- conversion it bought, never as a number on its own.
  if coalesce(p_cost_paise, 0) > 0 then
    insert into public.daily_salon_metrics (salon_id, day, messaging_cost_paise)
    select d.salon_id, (now() at time zone 'UTC')::date, p_cost_paise
      from public.notification_deliveries d where d.id = p_delivery_id
    on conflict (salon_id, day) do update
       set messaging_cost_paise = public.daily_salon_metrics.messaging_cost_paise + p_cost_paise,
           updated_at = now();
  end if;
end;
$$;

comment on function app.record_send is
  'What the provider said. `sent` means accepted by the provider - never delivered, and never acked: only the app''s ack moves a notification out of sent (ARCHITECTURE 12.3).';

select app_admin.close_privileges();
