-- 0017 The admin plane: app_admin.*
--
-- M2's server side. RULES 6 in one file:
--
--   6.1  salons are created only through the console      -> provision_salon
--   6.2  provisioning is ONE transaction                  -> one function, one txn
--   6.3  activation is a deliberate human action          -> activate_salon, separate
--   6.4  the setup fee is collected offline               -> record_setup_fee, no gateway
--   6.5  every admin mutation writes audit_log in the
--        SAME transaction                                 -> app_admin.audit(), gated
--   6.6  the service role calls app_admin.* and nothing
--        else                                             -> grants at the bottom
--   6.9  the console can change status, never delete      -> set_salon_status only
--
-- Why a separate schema. `public` is what PostgREST exposes; anything in it is
-- one missing grant away from being callable by a tenant. `app_admin` is not in
-- PostgREST's search path at all, so reaching these functions requires a direct
-- connection holding the service role. Two independent things must go wrong
-- rather than one.

-- ---------------------------------------------------------------------------
-- Vault. Required, not optional: set_integration_secret has nowhere else to
-- put a credential.
-- ---------------------------------------------------------------------------
--
-- Hosted Supabase ships this pre-installed, so this is normally a no-op. If a
-- CI image lacks it the migration fails HERE, with a message that says what to
-- do, rather than failing later inside a function with "schema vault does not
-- exist" - or worse, silently skipping the secret tests.

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'supabase_vault') then
    begin
      create extension supabase_vault with schema vault;
    exception when others then
      raise exception
        'supabase_vault is not installed and could not be created (%). The admin '
        'plane stores per-salon credentials in Vault and has no fallback; install '
        'the extension in this environment before applying 0017.', sqlerrm;
    end;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- The join code alphabet must match PRD 6.3
-- ---------------------------------------------------------------------------
--
-- 6.3 says the alphabet excludes 0/O and 1/I/L. The constraint written in 0003
-- was `[A-HJ-NP-Z2-9]`, which excludes I and O and 0 and 1 - but J-N includes
-- **L**. A customer reading `CRAY-L4M2K9` off a printed mirror sticker in a
-- salon with bad lighting has to guess between L and 1, which is exactly the
-- failure the unambiguous alphabet exists to prevent.
--
-- Safe to tighten: no salon exists yet.

do $$
declare
  v_name text;
begin
  select con.conname into v_name
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'salons'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) like '%CRAY-%';

  if v_name is null then
    raise exception '0017: no join_code check constraint found on public.salons';
  end if;

  execute format('alter table public.salons drop constraint %I', v_name);
end;
$$;

alter table public.salons
  add constraint salons_join_code_check
  check (join_code ~ '^CRAY-[A-HJKMNP-Z2-9]{6}$');

comment on column public.salons.join_code is
  'Globally unique, human-typable. Alphabet excludes 0/O and 1/I/L so a customer can read it off print without guessing (PRD 6.3).';

-- ---------------------------------------------------------------------------
-- The owner exists before the owner logs in
-- ---------------------------------------------------------------------------
--
-- Provisioning creates the owner's user row and sends an SMS invite; the owner
-- then logs into the same Android app by OTP, days later. So at provisioning
-- time there is no Auth user to point at, and `users.id` cannot be the Auth
-- uid as PRD 8.1 assumed.
--
-- Mirrors `customers`, which already separates its own id from auth_user_id.
-- Nothing depended on the old assumption: every `users` policy keys off
-- salon_id, and app_role comes from the JWT, not from this table.

alter table public.users
  add column if not exists auth_user_id uuid unique references auth.users(id);

comment on column public.users.auth_user_id is
  'Attached at first OTP login, not at provisioning - the owner row is created by the console before the owner has ever opened the app. Null means invited but never logged in.';

-- ---------------------------------------------------------------------------
-- The schema itself
-- ---------------------------------------------------------------------------

create schema if not exists app_admin;

comment on schema app_admin is
  'The Crayora admin plane. Not exposed through PostgREST; callable only by service_role over a direct connection. Every mutating function writes audit_log in the same transaction (RULES 6.5).';

revoke all on schema app_admin from public;

-- ---------------------------------------------------------------------------
-- app_admin.audit - the reason a route handler cannot forget the audit
-- ---------------------------------------------------------------------------

create or replace function app_admin.audit(
  p_salon_id       uuid,
  p_actor_admin_id uuid,
  p_action         text,
  p_entity         text,
  p_entity_id      text,
  p_reason         text default null,
  p_before         jsonb default null,
  p_after          jsonb default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_log
    (salon_id, actor_user_id, actor_kind, action, entity, entity_id,
     reason, before_state, after_state)
  values
    (p_salon_id, p_actor_admin_id, 'platform_admin', p_action, p_entity,
     p_entity_id, p_reason, p_before, p_after);
$$;

comment on function app_admin.audit is
  'Called by every mutating app_admin function, in the same transaction as the mutation. A rollback takes the audit row with it, so the log can never claim something that did not happen.';

-- ---------------------------------------------------------------------------
-- app_admin.assert_admin - who is allowed to act
-- ---------------------------------------------------------------------------

create or replace function app_admin.assert_admin(p_actor_admin_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_actor_admin_id is null then
    raise exception 'app_admin: an actor is required - every admin action is attributable';
  end if;

  if not exists (
    select 1 from public.platform_admins
     where id = p_actor_admin_id and active
  ) then
    raise exception 'app_admin: % is not an active platform admin', p_actor_admin_id
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- app_admin.generate_join_code
-- ---------------------------------------------------------------------------

create or replace function app_admin.generate_join_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- 31 characters. No I, L, O, 0 or 1 (PRD 6.3).
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code     text;
  v_attempt  int := 0;
begin
  loop
    v_attempt := v_attempt + 1;

    select 'CRAY-' || string_agg(
             substr(v_alphabet,
                    1 + (get_byte(extensions.gen_random_bytes(1), 0) % 31),
                    1),
             '')
      into v_code
      from generate_series(1, 6);

    exit when not exists (select 1 from public.salons where join_code = v_code);

    -- 31^6 is about 887 million codes, so a collision means either a great
    -- deal of salons or a broken RNG. Either way, stop rather than spin.
    if v_attempt >= 20 then
      raise exception
        'app_admin: could not generate an unused join code in % attempts', v_attempt;
    end if;
  end loop;

  return v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- app_admin.provision_salon - RULES 6.2, one transaction
-- ---------------------------------------------------------------------------
--
-- A function, not a sequence of route-handler calls, precisely so that a
-- failure at the last step leaves no salon, no join code and no owner behind.
-- The status it creates is `setup`: provisioning does NOT switch a salon on.

create or replace function app_admin.provision_salon(
  p_actor_admin_id  uuid,
  p_legal_name      text,
  p_display_name    text,
  p_owner_name      text,
  p_owner_phone     text,
  p_plan            text,
  p_setup_fee_paise bigint,
  p_phone           text default null,
  p_email           text default null,
  p_address         text default null,
  p_gst_number      text default null,
  p_timezone        text default 'Asia/Kolkata',
  p_languages       text[] default array['en', 'hi'],
  p_settings        jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon_id uuid := extensions.gen_random_uuid();
  v_owner_id uuid := extensions.gen_random_uuid();
  v_code     text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'app_admin: display_name is required - it appears in every message';
  end if;

  if p_setup_fee_paise < 0 then
    raise exception 'app_admin: setup fee cannot be negative';
  end if;

  v_code := app_admin.generate_join_code();

  insert into public.salons (
    id, legal_name, display_name, join_code, status,
    address, phone, email, gst_number, timezone, languages,
    working_hours, wallet_rule, reward_rule, loyalty_rule,
    default_reminder_cycle_days, notification_prefs, cancellation_policy
  )
  values (
    v_salon_id, p_legal_name, p_display_name, v_code, 'setup'::public.salon_status,
    p_address, p_phone, p_email, p_gst_number, p_timezone, p_languages,
    coalesce(p_settings -> 'working_hours', '{}'::jsonb),
    coalesce(p_settings -> 'wallet_rule',   '{}'::jsonb),
    coalesce(p_settings -> 'reward_rule',   '{}'::jsonb),
    coalesce(p_settings -> 'loyalty_rule',  '{}'::jsonb),
    coalesce((p_settings ->> 'default_reminder_cycle_days')::int, 30),
    coalesce(p_settings -> 'notification_prefs', '{}'::jsonb),
    p_settings ->> 'cancellation_policy'
  );

  -- The subscription exists from provisioning, with the fee recorded as
  -- unpaid. Marking it paid is a separate, attributable action (6.4).
  insert into public.subscriptions (
    salon_id, plan, status, setup_fee_paise, setup_fee_status, billing_starts_on
  )
  values (
    v_salon_id, p_plan, 'active'::public.subscription_status,
    p_setup_fee_paise, 'unpaid'::public.setup_fee_status,
    (p_settings ->> 'billing_starts_on')::date
  );

  -- The owner, invited but not yet logged in: auth_user_id stays null until
  -- their first OTP login attaches it.
  insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
  values (
    v_owner_id, v_salon_id, 'owner'::public.user_role, p_owner_name,
    p_owner_phone, app.phone_hash(p_owner_phone), true
  );

  -- Every integration starts as `missing`, so the console's readiness view is
  -- driven by rows that exist rather than by rows that do not.
  insert into public.salon_integrations (salon_id, provider, status)
  select v_salon_id, p.provider, 'missing'::public.integration_status
    from unnest(enum_range(null::public.integration_provider)) as p(provider);

  perform app_admin.audit(
    v_salon_id, p_actor_admin_id, 'salon.provisioned', 'salons', v_salon_id::text,
    null, null,
    jsonb_build_object(
      'display_name', p_display_name,
      'join_code',    v_code,
      'plan',         p_plan,
      'status',       'setup')
  );

  return jsonb_build_object(
    'salon_id',      v_salon_id,
    'join_code',     v_code,
    'owner_user_id', v_owner_id,
    'status',        'setup'
  );
end;
$$;

comment on function app_admin.provision_salon is
  'RULES 6.2: one transaction. A failure anywhere creates nothing - no salon, no join code, no owner, no orphaned integration rows. Creates the salon in `setup`; switching it on is activate_salon.';

-- ---------------------------------------------------------------------------
-- app_admin.record_setup_fee - RULES 6.4, collected offline
-- ---------------------------------------------------------------------------

create or replace function app_admin.record_setup_fee(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_status         text,
  p_reference      text default null,
  p_paid_on        date default null
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

  if p_status not in ('unpaid', 'paid', 'waived') then
    raise exception 'app_admin: setup fee status must be unpaid, paid or waived';
  end if;

  -- A fee marked paid without a reference is not a record of anything. The
  -- money moved outside the system, so the reference is the only evidence.
  if p_status = 'paid' and coalesce(trim(p_reference), '') = '' then
    raise exception
      'app_admin: a paid setup fee needs a reference - it was collected offline '
      'and this is the only record that it was collected at all';
  end if;

  select jsonb_build_object(
           'setup_fee_status', s.setup_fee_status,
           'setup_fee_reference', s.setup_fee_reference,
           'setup_fee_paid_on', s.setup_fee_paid_on)
    into v_before
    from public.subscriptions s where s.salon_id = p_salon_id;

  if v_before is null then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;

  update public.subscriptions
     set setup_fee_status    = p_status::public.setup_fee_status,
         setup_fee_reference = p_reference,
         setup_fee_paid_on   = case when p_status = 'paid'
                                    then coalesce(p_paid_on, current_date) end,
         updated_at          = now()
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.setup_fee_recorded', 'subscriptions',
    p_salon_id::text, p_reference, v_before,
    jsonb_build_object('setup_fee_status', p_status,
                       'setup_fee_reference', p_reference)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- app_admin.activate_salon - RULES 6.3, a deliberate human action
-- ---------------------------------------------------------------------------
--
-- Deliberately NOT gated on the setup fee or on integration readiness. PRD 6.2
-- is explicit: the console *warns* if the fee is unrecorded but does not block
-- the operator, who may have a reason; and messaging readiness "blocks nothing
-- that matters" because login works from day one and push carries every
-- notification. Enforcing either here would be a stricter product than the one
-- that was specified.

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
  v_status public.salon_status;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  select status into v_status from public.salons where id = p_salon_id for update;

  if v_status is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  if v_status <> 'setup' then
    raise exception
      'app_admin: only a salon in setup can be activated (this one is %). Use '
      'set_salon_status to move between active, grace and suspended.', v_status;
  end if;

  update public.salons
     set status       = 'active'::public.salon_status,
         activated_by = p_actor_admin_id,
         activated_at = now(),
         updated_at   = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.activated', 'salons', p_salon_id::text,
    p_reason,
    jsonb_build_object('status', 'setup'),
    jsonb_build_object('status', 'active')
  );
end;
$$;

comment on function app_admin.activate_salon is
  'RULES 6.3. The ONLY path from setup to active, and it requires a named human. No payment event, timer or form save may call it.';

-- ---------------------------------------------------------------------------
-- app_admin.set_salon_status - RULES 6.9, status changes but never deletion
-- ---------------------------------------------------------------------------

create or replace function app_admin.set_salon_status(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_status         text,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.salon_status;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception
      'app_admin: a status change needs a reason - suspending a salon stops a '
      'real business from taking bookings';
  end if;

  -- `setup` is not reachable from here: a salon that has met customers cannot
  -- be put back into a state that pretends it has not. And `active` is only
  -- reachable through activate_salon, so 6.3 has exactly one door.
  if p_status not in ('grace', 'suspended') then
    raise exception
      'app_admin: set_salon_status handles grace and suspended only. Use '
      'activate_salon to switch a salon on.';
  end if;

  select status into v_before from public.salons where id = p_salon_id for update;

  if v_before is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  update public.salons
     set status = p_status::public.salon_status, updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.status_changed', 'salons',
    p_salon_id::text, p_reason,
    jsonb_build_object('status', v_before),
    jsonb_build_object('status', p_status)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- app_admin.set_integration_secret - ARCHITECTURE 8.2, write-only
-- ---------------------------------------------------------------------------
--
-- There is deliberately NO read counterpart. The console displays provider,
-- last4 and status; nothing in this schema returns a credential, and the
-- admin-plane gate asserts that no function ever does.

create or replace function app_admin.set_integration_secret(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_provider       text,
  p_secret         text,
  p_public_key_id  text default null,
  p_sender_id      text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret_id uuid;
  v_last4     text;
  v_old       uuid;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(p_secret, '') = '' then
    raise exception 'app_admin: refusing to store an empty secret';
  end if;

  if not exists (select 1 from public.salons where id = p_salon_id) then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;

  v_last4 := right(p_secret, 4);

  select vault_secret_id into v_old
    from public.salon_integrations
   where salon_id = p_salon_id and provider = p_provider::public.integration_provider;

  -- A new Vault secret each time, and the reference flipped. The old secret is
  -- left in place for the rotation grace window described in ARCHITECTURE 8.2;
  -- destroying it is a separate, scheduled step, because in-flight webhooks
  -- signed against it must still verify.
  v_secret_id := vault.create_secret(
    p_secret,
    format('salon:%s:%s:%s', p_salon_id, p_provider, extensions.gen_random_uuid()),
    format('Per-salon %s credential. Written by app_admin.set_integration_secret; never read back through any API.', p_provider)
  );

  update public.salon_integrations
     set vault_secret_id = v_secret_id,
         public_key_id   = coalesce(p_public_key_id, public_key_id),
         sender_id       = coalesce(p_sender_id, sender_id),
         last4           = v_last4,
         status          = 'untested'::public.integration_status,
         last_tested_at  = null,
         updated_at      = now()
   where salon_id = p_salon_id
     and provider = p_provider::public.integration_provider;

  if not found then
    raise exception 'app_admin: salon % has no % integration row', p_salon_id, p_provider;
  end if;

  -- The audit records THAT a credential was set, and nothing about what it is.
  -- last4 is already displayed in the console, so it leaks nothing further.
  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'integration.secret_set', 'salon_integrations',
    p_provider, null,
    jsonb_build_object('had_previous_secret', v_old is not null),
    jsonb_build_object('provider', p_provider, 'last4', v_last4,
                       'status', 'untested')
  );
end;
$$;

comment on function app_admin.set_integration_secret is
  'Write-only by design (ARCHITECTURE 8.2). No function in this schema returns a credential, and the admin-plane gate fails the build if one ever does.';

-- ---------------------------------------------------------------------------
-- app_admin.record_integration_test - the result, never the credential
-- ---------------------------------------------------------------------------

create or replace function app_admin.record_integration_test(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_provider       text,
  p_ok             boolean,
  p_detail         text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  update public.salon_integrations
     set status = case when p_ok then 'ok'::public.integration_status
                       else 'failing'::public.integration_status end,
         last_tested_at = now(),
         updated_at     = now()
   where salon_id = p_salon_id
     and provider = p_provider::public.integration_provider;

  if not found then
    raise exception 'app_admin: salon % has no % integration row', p_salon_id, p_provider;
  end if;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'integration.tested', 'salon_integrations',
    p_provider, p_detail, null,
    jsonb_build_object('provider', p_provider, 'ok', p_ok)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants - RULES 6.6
-- ---------------------------------------------------------------------------
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, which would undo the
-- whole point of putting these in their own schema. Revoke first, then grant
-- to exactly one role.

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app_admin'
  loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('revoke all on function %s from anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end;
$$;

grant usage on schema app_admin to service_role;

-- Guard: if a future migration adds a function here and forgets the grant
-- dance above, say so now rather than at the first call in production.
do $$
declare
  v_open int;
begin
  select count(*) into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_admin'
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
       or has_function_privilege('anon', p.oid, 'EXECUTE'));

  if v_open > 0 then
    raise exception
      '% app_admin function(s) are executable by a tenant role - the admin '
      'plane is not separate', v_open;
  end if;
end;
$$;
