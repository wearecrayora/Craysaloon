-- 0102 SMS and WhatsApp actually send, through the salon's Message Central.
--
-- Found 13 Oct 2026 by the PRD 20 audit: the paid rungs of the ladder had never
-- delivered anything. The dispatcher sent SMS and WhatsApp to Message
-- Central's OTP endpoint as a JSON body, with NO recipient phone number - and
-- for SMS there was no text either, because no SMS template existed, so every
-- attempt ended as `no_template` before it even reached the provider. Built
-- now from Message Central's own documents (MessageNow SMS API; WhatsApp Now
-- API V1), which Crayora supplied:
--
--   SMS        POST /verification/v3/send  type=SMS flowType=SMS countryCode
--              mobileNumber senderId message messageType=TRANSACTION|PROMOTIONAL
--   WhatsApp   POST /verification/v3/send  flowType=WHATSAPP type=BROADCAST
--              templateName senderId(WABA number) countryCode mobileNumber
--              langId variables
--
-- No DLT: Message Central's SMS needs none (confirmed with its sales team,
-- 13 Oct 2026), so there is no templateId/entityId anywhere.
--
-- 1. OTP: NO per-salon daily cap. 0101 added one; Crayora decided against it
--    the same day. Removed here - otp_begin is back to phone and address.
-- 2. SMS text is the push text. render_template falls back to the push body
--    for SMS when a salon has no SMS-specific wording: one set of words to
--    keep white-labelled and translated, not two.
-- 3. The ladder only offers a rung the salon can actually send. SMS needs the
--    salon's Message Central credential and its SMS sender ID; WhatsApp needs
--    approved templates AND the salon's WhatsApp Business number. A rung that
--    cannot send is not there - the ladder moves on or ends, as it already did
--    for RCS - instead of "sending" into a failure that still waits out a
--    window.
-- 4. The batch carries what each channel needs and nothing more: the
--    recipient's number ONLY for an SMS or WhatsApp row (a push never needs
--    it), the sender, the category (TRANSACTION vs PROMOTIONAL), and for
--    WhatsApp the approved template's name, language and variable values.
-- 5. Crayora sets the sender IDs, the WhatsApp number and status, and each
--    WhatsApp template, in the console - audited, never an owner (RULES 8.12).

-- ---------------------------------------------------------------------------
-- 1. otp_begin without the per-salon cap
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.otp_begin(text, text)'::regprocedure);
  v_new := regexp_replace(v_def,
    '  -- Per salon per day \(0101\).*?  end if;\n\n  return jsonb_build_object\(',
    '  return jsonb_build_object(', 's');
  if v_new = v_def then
    raise exception '0102: the 0101 cap was not found in otp_begin';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. SMS speaks the push text
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('app.render_template(uuid, text, text, public.message_channel, jsonb)'::regprocedure);
  v_new := replace(v_def,
    $o$     and t.channel = p_channel$o$,
    $n$     and (t.channel = p_channel or (p_channel = 'sms' and t.channel = 'push'))$n$);
  v_new := replace(v_new,
    $o$   order by (t.salon_id is not null) desc, (t.locale = p_locale) desc$o$,
    $n$   order by (t.channel = p_channel) desc, (t.salon_id is not null) desc, (t.locale = p_locale) desc$n$);
  if v_new = v_def or position('p_channel = ''sms''' in v_new) = 0
     or position('(t.channel = p_channel) desc' in v_new) = 0 then
    raise exception '0102: render_template did not change as expected';
  end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. WhatsApp templates: name, language, and which values fill {{1}}, {{2}}...
-- ---------------------------------------------------------------------------

alter table public.message_templates
  add column if not exists provider_lang      text,
  add column if not exists provider_variables text[];

comment on column public.message_templates.provider_template_id is
  'WhatsApp: the APPROVED template name as Message Central returned it (lower_snake). Set by Crayora in the console (0102).';
comment on column public.message_templates.provider_lang is
  'WhatsApp: the template''s language as approved, e.g. en or hi (Message Central langId).';
comment on column public.message_templates.provider_variables is
  'WhatsApp: which value fills each placeholder, in order - {{1}} is the first. ''salon'' is the salon''s name; anything else is a key of the notification''s params (0102).';

-- ---------------------------------------------------------------------------
-- 4. The ladder offers only what can send
-- ---------------------------------------------------------------------------

create or replace function app.next_channel(
  p_salon_id uuid, p_category public.message_category, p_tried public.message_channel[])
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
  select (i.rcs_agent_status = 'verified') into v_rcs_ok
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider = 'rcs';

  -- Everything paid rides the salon's Message Central account (0102): no
  -- usable credential, no paid rung at all.
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

  -- RCS sits above WhatsApp when the agent is verified: cheaper, and it carries
  -- the salon's name and logo natively (12.2a). Skipped entirely when it is not
  -- - a rung the salon cannot use is not an error, it is simply not there.
  if coalesce(v_rcs_ok, false) and not ('rcs' = any(p_tried)) then
    return 'rcs'::public.message_channel;
  end if;

  if p_category = 'transactional' then
    -- WhatsApp Utility is CHEAPER than SMS (Rs 0.17 vs Rs 0.22), which is the
    -- fact that surprises people and decides this order.
    if v_whatsapp_ok and not ('whatsapp' = any(p_tried)) then
      return 'whatsapp'::public.message_channel;
    end if;
    if v_sms_ok and not ('sms' = any(p_tried)) then
      return 'sms'::public.message_channel;
    end if;
    return null;
  end if;

  -- Marketing: SMS by default, because WhatsApp Marketing is six times the
  -- price of SMS and it is the SALON's money. WhatsApp only if the owner has
  -- said so explicitly.
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

-- ---------------------------------------------------------------------------
-- 5. The batch carries what each channel needs
-- ---------------------------------------------------------------------------

drop function if exists public.claim_notification_batch(uuid, integer);
drop function if exists app.claim_notification_batch(uuid, integer);

create function app.claim_notification_batch(p_salon_id uuid, p_limit integer default 50)
returns table(delivery_id uuid, notification_id uuid, channel public.message_channel,
              customer_id uuid, token text, platform text, body text, purpose text,
              category public.message_category, phone text, sender_id text,
              wa_template text, wa_lang text, wa_variables text[])
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
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
          -- Push-only purposes (window NULL, 0086) never open a paid rung.
          or (app.escalation_window(n.purpose) is not null
              and app.next_channel(n.salon_id, n.category, '{push}') is not null))
   limit greatest(coalesce(p_limit, 50), 1);

  -- Everything queued for this salon that nobody holds, STAMPED as it is handed
  -- out (0100) so overlapping dispatchers never send a row twice.
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
           -- The number goes out ONLY with a row that is sent to a number. A
           -- push is addressed to a device; it never needs - so never carries -
           -- the customer's phone.
           case when c.channel in ('sms', 'whatsapp')
                then app.canonical_phone(coalesce(cu.phone, us.phone)) end,
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
         where nt.customer_id = n.customer_id and nt.dead_at is null
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
$function$;

revoke all on function app.claim_notification_batch(uuid, integer) from public, anon, authenticated;

create function public.claim_notification_batch(p_salon_id uuid, p_limit integer default 50)
returns table(delivery_id uuid, notification_id uuid, channel public.message_channel,
              customer_id uuid, token text, platform text, body text, purpose text,
              category public.message_category, phone text, sender_id text,
              wa_template text, wa_lang text, wa_variables text[])
language sql
security definer
set search_path = ''
as $$
  select * from app.claim_notification_batch(p_salon_id, p_limit)
$$;

comment on function public.claim_notification_batch(uuid, integer) is
  'The dispatcher''s read, service_role only. Carries a phone number only for SMS and WhatsApp rows (0102).';

revoke all on function public.claim_notification_batch(uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_notification_batch(uuid, integer) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Crayora sets the messaging identity and the WhatsApp templates
-- ---------------------------------------------------------------------------

create or replace function app_admin.set_messaging_identity(
  p_actor_admin_id  uuid,
  p_salon_id        uuid,
  p_sms_sender_id   text,
  p_whatsapp_number text,
  p_whatsapp_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sms    text := nullif(btrim(coalesce(p_sms_sender_id, '')), '');
  v_wa     text := nullif(regexp_replace(coalesce(p_whatsapp_number, ''), '[^0-9]', '', 'g'), '');
  v_status text := coalesce(nullif(btrim(p_whatsapp_status), ''), 'not_started');
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if v_sms is not null and v_sms !~ '^[A-Za-z0-9]{3,15}$' then
    raise exception 'app_admin: an SMS sender ID is 3 to 15 letters or digits, as Message Central issued it';
  end if;
  if v_wa is not null and v_wa !~ '^[1-9][0-9]{9,14}$' then
    raise exception 'app_admin: the WhatsApp Business number goes in with its country code, e.g. 919812345678';
  end if;
  if v_status not in ('not_started', 'pending', 'approved', 'rejected') then
    raise exception 'app_admin: WhatsApp status must be not_started, pending, approved or rejected';
  end if;
  if v_status = 'approved' and v_wa is null then
    raise exception 'app_admin: WhatsApp cannot be approved without the salon''s WhatsApp Business number';
  end if;

  select jsonb_object_agg(i.provider::text,
           jsonb_build_object('sender_id', i.sender_id,
                              'whatsapp_template_status', i.whatsapp_template_status))
    into v_before
    from public.salon_integrations i
   where i.salon_id = p_salon_id and i.provider in ('message_central', 'whatsapp');

  update public.salon_integrations
     set sender_id = v_sms, updated_at = now()
   where salon_id = p_salon_id and provider = 'message_central';
  if not found then
    raise exception 'app_admin: salon % has no message_central integration row', p_salon_id;
  end if;

  update public.salon_integrations
     set sender_id = v_wa, whatsapp_template_status = v_status, updated_at = now()
   where salon_id = p_salon_id and provider = 'whatsapp';
  if not found then
    raise exception 'app_admin: salon % has no whatsapp integration row', p_salon_id;
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'integration.messaging_identity_set', 'salon_integrations',
    p_salon_id::text, null, v_before,
    jsonb_build_object('sms_sender_id', v_sms, 'whatsapp_number', v_wa,
                       'whatsapp_template_status', v_status));
end;
$$;

comment on function app_admin.set_messaging_identity is
  'Crayora only: the salon''s SMS sender ID (Message Central), WhatsApp Business number and template approval status. Gates the SMS and WhatsApp rungs of the ladder (0102). Audited.';

create or replace function app_admin.set_whatsapp_template(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_template_key   text,
  p_locale         text,
  p_template_name  text,
  p_lang           text,
  p_variables      text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name    text := nullif(btrim(coalesce(p_template_name, '')), '');
  v_lang    text := nullif(btrim(coalesce(p_lang, '')), '');
  v_allowed text[];
  v_bad     text;
  v_before  jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_locale not in ('en', 'hi', 'hi_Latn') then
    raise exception 'app_admin: locale must be en, hi or hi_Latn';
  end if;

  -- The values a template may use are the ones its own push wording uses:
  -- {{salon}} and the notification's params. A variable naming anything else
  -- would send an empty slot to a customer.
  select array_agg(distinct m[1])
    into v_allowed
    from public.message_templates t,
         regexp_matches(t.body, '\{\{([a-z_]+)\}\}', 'g') m
   where t.salon_id is null and t.channel = 'push' and t.template_key = p_template_key;
  if v_allowed is null then
    raise exception 'app_admin: % is not a message this product sends', p_template_key;
  end if;

  select to_jsonb(t) - 'id' - 'created_at' - 'updated_at' into v_before
    from public.message_templates t
   where t.salon_id = p_salon_id and t.template_key = p_template_key
     and t.locale = p_locale and t.channel = 'whatsapp';

  if v_name is null then
    -- Clearing a mapping: that message goes back to SMS for this language.
    delete from public.message_templates
     where salon_id = p_salon_id and template_key = p_template_key
       and locale = p_locale and channel = 'whatsapp';
  else
    if v_name !~ '^[a-z0-9_]{1,512}$' then
      raise exception 'app_admin: use the template name exactly as Message Central returned it - lower case, digits and _';
    end if;
    if v_lang is null or v_lang !~ '^[a-z]{2,3}(_[A-Z]{2})?$' then
      raise exception 'app_admin: the template language is its WhatsApp code, e.g. en, en_US or hi';
    end if;
    select v into v_bad from unnest(coalesce(p_variables, '{}')) v
     where not (v = any(v_allowed)) limit 1;
    if v_bad is not null then
      raise exception 'app_admin: % is not a value this message has (it has: %)',
        v_bad, array_to_string(v_allowed, ', ');
    end if;

    insert into public.message_templates
      (salon_id, template_key, locale, channel, body, provider_template_id,
       provider_lang, provider_variables)
    values
      (p_salon_id, p_template_key, p_locale, 'whatsapp', null, v_name, v_lang,
       coalesce(p_variables, '{}'))
    on conflict (salon_id, template_key, locale, channel) where salon_id is not null
    do update set provider_template_id = excluded.provider_template_id,
                  provider_lang        = excluded.provider_lang,
                  provider_variables   = excluded.provider_variables,
                  updated_at           = now();
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'messaging.whatsapp_template_set', 'message_templates',
    p_template_key || ':' || p_locale, null, v_before,
    case when v_name is null then null
         else jsonb_build_object('template', v_name, 'lang', v_lang,
                                 'variables', to_jsonb(coalesce(p_variables, '{}'))) end);
end;
$$;

comment on function app_admin.set_whatsapp_template is
  'Crayora only: maps one message (key, locale) to the salon''s Meta-approved WhatsApp template - its name, language and which values fill its placeholders. A null name clears it (0102). Audited.';

select app_admin.close_privileges();
