-- 0053 Every salon names the person who answers a privacy request
--
-- Decision taken 28 Sep 2026: **the salon answers, Crayora escalates.** The
-- salon is the Data Fiduciary (RULES 11.7), so the contact a customer sees is
-- the salon's; Crayora is the escalation when a salon does not answer in time.
--
-- DPDP s.5 requires the consent notice to say how to contact the Fiduciary with
-- a question or complaint, and s.13 gives a right to grievance redressal. A
-- contact that is optional is a contact that is missing on the salon that
-- eventually needs it, so this is REQUIRED BEFORE ACTIVATION: a salon cannot
-- take its first customer without one.
--
-- It is published deliberately. `resolve_join_code` returns it with the salon's
-- name and branding, because the notice has to be readable BEFORE anyone logs
-- in - at the moment consent is asked for, which is the only moment it matters.
-- It is a business contact, not personal data of a data principal, and it is the
-- one thing a customer needs in order to complain about us.

alter table public.salons
  add column grievance_name  text,
  add column grievance_email text,
  add column grievance_phone text;

comment on column public.salons.grievance_name is
  'The person at the salon who answers privacy questions and erasure requests (DPDP ss.5, 13). Required before activation (0053); shown in the app''s consent notice.';

create or replace function app_admin.set_grievance_contact(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_name           text,
  p_email          text,
  p_phone          text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_name), '') = '' then
    raise exception 'app_admin: name the person, not a department - a customer needs someone to ask';
  end if;
  -- One reachable channel at minimum. Both is better; neither is not a contact.
  if coalesce(btrim(p_email), '') = '' and coalesce(btrim(p_phone), '') = '' then
    raise exception 'app_admin: an email or a phone number is required - a name alone is unreachable';
  end if;
  if p_email is not null and btrim(p_email) <> '' and position('@' in p_email) = 0 then
    raise exception 'app_admin: that is not an email address';
  end if;

  select jsonb_build_object('name', grievance_name, 'email', grievance_email,
                            'phone', grievance_phone)
    into v_before
    from public.salons where id = p_salon_id;

  if v_before is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  update public.salons
     set grievance_name  = btrim(p_name),
         grievance_email = nullif(btrim(coalesce(p_email, '')), ''),
         grievance_phone = nullif(btrim(coalesce(p_phone, '')), ''),
         updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.grievance_contact_set', 'salons',
    p_salon_id::text, null, v_before,
    jsonb_build_object('name', btrim(p_name), 'email', p_email, 'phone', p_phone));
end;
$$;

comment on function app_admin.set_grievance_contact is
  'The salon''s named privacy contact (DPDP ss.5, 13). A name plus at least one reachable channel; required before the salon can be activated (0053).';

-- ---------------------------------------------------------------------------
-- Activation now requires it
-- ---------------------------------------------------------------------------
--
-- 0017's body, with one added refusal. Activation is the moment a salon starts
-- taking real customers' data, and it is the last moment this can be caught
-- cheaply.

create or replace function app_admin.activate_salon(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_reason         text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status    public.salon_status;
  v_grievance text;
  v_email     text;
  v_phone     text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  select status, grievance_name, grievance_email, grievance_phone
    into v_status, v_grievance, v_email, v_phone
    from public.salons where id = p_salon_id for update;

  if v_status is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  if v_status <> 'setup' then
    raise exception
      'app_admin: only a salon in setup can be activated (this one is %). Use '
      'set_salon_status to move between active, grace and suspended.', v_status;
  end if;

  -- DPDP ss.5 and 13: the consent notice must tell a customer who to ask and how
  -- to complain. A salon with no named contact cannot show that notice, and
  -- without the notice its customers' consent is not valid consent (RULES 11.6a).
  if coalesce(btrim(coalesce(v_grievance, '')), '') = ''
     or (coalesce(btrim(coalesce(v_email, '')), '') = ''
         and coalesce(btrim(coalesce(v_phone, '')), '') = '') then
    raise exception
      'app_admin: this salon has no privacy contact. Set one (name + email or '
      'phone) before activating - its customers must be told who answers a '
      'question or a complaint about their data.';
  end if;

  update public.salons
     set status       = 'active'::public.salon_status,
         activated_by = p_actor_admin_id,
         activated_at = now(),
         updated_at   = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.activated', 'salons', p_salon_id::text,
    p_reason, jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'active'));
end;
$$;

comment on function app_admin.activate_salon is
  'RULES 6.3. The ONLY path from setup to active, and it requires a named human. No payment event, timer or form save may call it. Since 0053 it also refuses a salon with no privacy contact: without one its customers cannot be shown a valid consent notice.';

-- ---------------------------------------------------------------------------
-- The notice needs it before anyone logs in
-- ---------------------------------------------------------------------------

create or replace function app.resolve_join_code(
  p_code       text,
  p_device_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  if not app.rate_limit_hit('resolve_code', coalesce(p_device_key, app.caller_key()), 60, 60) then
    raise exception 'resolve_join_code: too many attempts' using errcode = '53400';
  end if;

  select s.id, s.display_name, s.grievance_name, s.grievance_email, s.grievance_phone,
         b.version, b.tokens
    into v_row
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.join_code = app.normalise_join_code(p_code)
     and s.status = 'active';

  if v_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'salon_id',         v_row.id,
    'display_name',     v_row.display_name,
    'branding_version', v_row.version,
    'branding',         v_row.tokens,
    -- Published on purpose: the consent notice has to say who to ask and how to
    -- complain, and it is shown BEFORE login. A business contact, never a data
    -- principal's details (DPDP s.5, RULES 11.6a).
    'grievance',        jsonb_build_object(
                          'name',  v_row.grievance_name,
                          'email', v_row.grievance_email,
                          'phone', v_row.grievance_phone));
end;
$$;

comment on function app.resolve_join_code is
  'The only pre-auth read in the system. Returns display name, branding and the salon''s PRIVACY CONTACT for an ACTIVE salon; null for anything else, including a code that exists but belongs to a salon in setup - so a leaked QR cannot bind customers before the operator switches the salon on. The grievance contact is published deliberately: the consent notice is shown before login and must say who to complain to (0053).';

select app_admin.close_privileges();
