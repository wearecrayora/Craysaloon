-- 0034 Claims hook and binding - a customer becomes a salon's customer
--
-- Two pieces that only work together.
--
-- 1. THE CLAIMS HOOK (PHASES M3, still outstanding). Every RLS policy in this
--    schema reads `salon_id` and `app_role` from the session token. Until now no
--    token carried either, so a logged-in customer could read nothing at all -
--    the live test on 2026-09-15 saw zero rows of every tenant table. Supabase
--    calls this function every time it mints or refreshes a token.
--
-- 2. BINDING (PHASES M4). RULES 4.3: binding completes in the same step as
--    first login. Since ADR-36 moved the OTP to Message Central, that step is the
--    otp-verify Edge Function, so it calls otp_finish_login() BEFORE it mints the
--    session. The customer's very first token therefore already carries their
--    salon - there is no unbound interval to design a screen for.
--
-- The claims are a CACHE of the database, never the source of truth
-- (ARCHITECTURE 5.2). The hook reads the database on every mint.

-- ---------------------------------------------------------------------------
-- 1. The custom access token hook
-- ---------------------------------------------------------------------------
--
-- Precedence, most privileged role that applies first:
--   staff row (owner | manager | staff) -> that salon
--   customer binding                    -> that salon, as customer
--   platform admin                      -> platform_admin, and NEVER a salon_id
--                                          (RULES 6.7)
--   otherwise                           -> customer_unbound, no salon_id
--
-- A token for a salon that is blocked (0033) is still issued: reads stay open
-- so a customer can see money the salon owes them. Writes are refused by
-- salon_writable, which does not trust the token either.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_claims jsonb;
  v_role   text;
  v_salon  uuid;
begin
  v_uid := (event ->> 'user_id')::uuid;
  v_claims := coalesce(event -> 'claims', '{}'::jsonb);

  select u.role::text, u.salon_id into v_role, v_salon
    from public.users u
   where u.auth_user_id = v_uid and u.active
   limit 1;

  if v_role is null then
    select 'customer', ci.salon_id into v_role, v_salon
      from public.customer_identities ci
     where ci.auth_user_id = v_uid;
  end if;

  if v_role is null and exists (
    select 1 from public.platform_admins where id = v_uid and active
  ) then
    v_role := 'platform_admin';
    v_salon := null;
  end if;

  v_role := coalesce(v_role, 'customer_unbound');

  v_claims := jsonb_set(v_claims, '{app_role}', to_jsonb(v_role));
  if v_salon is not null then
    v_claims := jsonb_set(v_claims, '{salon_id}', to_jsonb(v_salon::text));
  else
    -- Never let a stale salon_id survive a refresh after an unbind.
    v_claims := v_claims - 'salon_id';
  end if;

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

comment on function public.custom_access_token_hook is
  'Supabase Auth calls this on every token mint and refresh. Stamps app_role and salon_id from the DATABASE, never from anything the client sent. Platform admins never receive a salon_id (RULES 6.7).';

-- Only Supabase Auth may call it. In `public` because that is where Auth looks,
-- so it must be closed to the roles PostgREST serves.
revoke all on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant usage on schema public to supabase_auth_admin;
    grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Binding, in the same step as first login
-- ---------------------------------------------------------------------------
--
-- The challenge carries the canonical phone number for its short life.
--
-- The salon needs its customer's number to contact them (PRD 8.2), and the
-- only moment the server holds the plaintext is otp-send. At verify time the
-- client deliberately sends no phone, and it must not: the stored number has
-- to be the one Message Central verified, not one the client names. So the
-- number rides on the challenge - a table with forced RLS, no policies and no
-- tenant grants - and otp_finish_login wipes it the moment it runs.

alter table public.otp_challenges add column phone text;

comment on column public.otp_challenges.phone is
  'Canonical 10-digit number, held only between otp-send and the end of login, then wiped by otp_finish_login (0034). The verified number, so the salon''s copy is never client-supplied.';

create or replace function public.otp_record_challenge(
  p_phone           text,
  p_salon_id        uuid,
  p_verification_id text,
  p_sender          text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash bytea;
  v_id   uuid;
begin
  v_hash := app.phone_hash(p_phone);

  -- One live challenge per phone. Superseded ones lose their number at once.
  update public.otp_challenges
     set consumed_at = now(), phone = null
   where phone_hash = v_hash and consumed_at is null;

  insert into public.otp_challenges (phone_hash, salon_id, verification_id, sender, phone)
  values (v_hash, p_salon_id, p_verification_id, p_sender, app.canonical_phone(p_phone))
  returning id into v_id;

  return v_id;
end;
$$;
--
-- Called by otp-verify (service_role) after Message Central has confirmed the
-- code and the Auth account exists, BEFORE the session is minted.
--
-- Keyed on the challenge, not on anything the client sends, for the same reason
-- as otp_link_identity: it can only act for the phone and salon of a
-- verification that genuinely completed a moment ago.
--
-- Outcomes:
--   staff      an active users row for this phone at this salon: attach the
--              Auth account to it. The owner created at provisioning arrives
--              here on their first login. No customer row is made.
--   bound      a first join: customer row, identity, binding event, consent
--              defaults, all in this one transaction (RULES 4.3).
--   returning  already this salon's customer: nothing changes, including
--              consent - a later login must not overwrite choices already made.
--   already_bound  bound to a DIFFERENT salon. The response names no salon,
--              no id, nothing (RULES 4.4). The person has proved they own the
--              number, but a third party reading the response must learn
--              nothing, and "which salon" is not something this step needs.
--
-- CONSENT DEFAULTS (DPDP 2023)
--   service_communication  granted. Bookings, receipts and wallet messages are
--                          the service the customer signed up for - a
--                          legitimate use under s.7 - and remain withdrawable.
--   promotional, whatsapp  granted ONLY if the customer ticked it on the join
--                          screen. DPDP requires a clear affirmative action; a
--                          default of "yes" is not consent.
--   photos                 never granted here. Asked when a photo is taken
--                          (PRD: "explicit consent required").

create or replace function public.otp_finish_login(
  p_challenge_id uuid,
  p_auth_user_id uuid,
  p_consents     jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash     bytea;
  v_salon    uuid;
  v_staff    record;
  v_bound    record;
  v_customer uuid;
  v_phone    text;
begin
  select phone_hash, salon_id, phone into v_hash, v_salon, v_phone
    from public.otp_challenges
   where id = p_challenge_id
     and consumed_at is not null
     and consumed_at > now() - interval '5 minutes';

  if v_hash is null then
    raise exception 'otp_finish_login: no recently completed challenge %', p_challenge_id;
  end if;

  -- The plaintext number has done its only job the moment we are here. Wipe
  -- it now, whichever way this login turns out.
  update public.otp_challenges set phone = null where id = p_challenge_id;

  -- The salon can have been blocked in the seconds between send and verify.
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  -- Staff first: an owner is not their own salon's customer.
  select id, role::text as role, auth_user_id into v_staff
    from public.users
   where salon_id = v_salon and phone_hash = v_hash and active
   limit 1;

  if v_staff.id is not null then
    if v_staff.auth_user_id is not null and v_staff.auth_user_id <> p_auth_user_id then
      -- The staff row is already attached to a different Auth account. Never
      -- re-point it silently: that would hand an owner's access to whoever
      -- logged in second.
      return jsonb_build_object('ok', false, 'reason', 'account_conflict');
    end if;
    update public.users set auth_user_id = p_auth_user_id, updated_at = now()
     where id = v_staff.id and auth_user_id is null;
    return jsonb_build_object('ok', true, 'outcome', 'staff', 'role', v_staff.role);
  end if;

  select salon_id, customer_id, auth_user_id into v_bound
    from public.customer_identities where phone_hash = v_hash;

  if v_bound.salon_id is not null then
    if v_bound.salon_id <> v_salon then
      -- RULES 4.4: name no salon.
      return jsonb_build_object('ok', false, 'reason', 'already_bound');
    end if;
    return jsonb_build_object('ok', true, 'outcome', 'returning');
  end if;

  -- A first join. Everything below is one transaction.
  -- The salon's own copy of the number, so it can contact its customer. It
  -- comes from the challenge - the number Message Central actually verified -
  -- never from the client, which could otherwise store someone else's number
  -- against this account.
  insert into public.customers (salon_id, auth_user_id, phone_hash, phone)
  values (v_salon, p_auth_user_id, v_hash, v_phone)
  returning id into v_customer;

  insert into public.customer_identities (phone_hash, auth_user_id, salon_id, customer_id)
  values (v_hash, p_auth_user_id, v_salon, v_customer);

  insert into public.binding_events (phone_hash, kind, to_salon_id)
  values (v_hash, 'bind', v_salon);

  insert into public.consents (salon_id, customer_id, purpose, granted, source)
  values
    (v_salon, v_customer, 'service_communication', true, 'binding'),
    (v_salon, v_customer, 'promotional',
       coalesce((p_consents ->> 'promotional')::boolean, false), 'binding'),
    (v_salon, v_customer, 'whatsapp',
       coalesce((p_consents ->> 'whatsapp')::boolean, false), 'binding'),
    (v_salon, v_customer, 'photos', false, 'binding');

  -- The intent has done its job.
  delete from public.join_intents where phone_hash = v_hash;

  return jsonb_build_object('ok', true, 'outcome', 'bound');
end;
$$;

revoke all on function public.otp_finish_login(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.otp_finish_login(uuid, uuid, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Unbind and transfer - Crayora support only (ARCHITECTURE 5.4, RULES 4.5)
-- ---------------------------------------------------------------------------

-- Wrong QR scanned, nothing done since. Refused if the customer has done
-- anything at all: once there is history, it is a transfer, with a balance
-- acknowledged.
create or replace function app_admin.unbind_customer(
  p_actor_admin_id uuid,
  p_phone          text,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash bytea;
  v_row  record;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: an unbind needs a reason';
  end if;

  v_hash := app.phone_hash(p_phone);
  select salon_id, customer_id into v_row
    from public.customer_identities where phone_hash = v_hash
   for update;

  if v_row.salon_id is null then
    raise exception 'app_admin: that number is not bound to any salon';
  end if;

  if exists (select 1 from public.wallet_transactions where customer_id = v_row.customer_id)
     or exists (select 1 from public.bookings where customer_id = v_row.customer_id)
     or exists (select 1 from public.visits v
                  join public.bookings b on b.id = v.booking_id
                 where b.customer_id = v_row.customer_id) then
    raise exception
      'app_admin: this customer has history at the salon - use transfer_customer, which '
      'records the balance they were told they would leave behind';
  end if;

  delete from public.customer_identities where phone_hash = v_hash;

  -- No activity, so this is not a financial record; a soft delete keeps the
  -- row for the audit trail without listing them as the salon's customer.
  update public.customers set deleted_at = now(), updated_at = now()
   where id = v_row.customer_id;

  insert into public.binding_events (phone_hash, kind, from_salon_id, actor_admin_id, reason)
  values (v_hash, 'unbind', v_row.salon_id, p_actor_admin_id, p_reason);

  perform app_admin.audit(
    v_row.salon_id, p_actor_admin_id, 'customer.unbound', 'customer_identities',
    v_row.customer_id::text, p_reason, null, null);
end;
$$;

-- The customer genuinely wants to move. The binding moves; NOTHING ELSE DOES
-- (RULES 4.6). The wallet was paid into the old salon's own Razorpay account
-- and Crayora has no mechanism to move it, so the acknowledged balance is a
-- required parameter: support cannot complete this without having looked it up
-- and told the customer.
create or replace function app_admin.transfer_customer(
  p_actor_admin_id             uuid,
  p_phone                      text,
  p_to_salon_id                uuid,
  p_reason                     text,
  p_acknowledged_balance_paise bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   bytea;
  v_row    record;
  v_auth   uuid;
  v_new    uuid;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: a transfer needs a reason';
  end if;
  if p_acknowledged_balance_paise is null or p_acknowledged_balance_paise < 0 then
    raise exception
      'app_admin: a transfer needs the balance the customer was told they would leave behind';
  end if;

  v_hash := app.phone_hash(p_phone);
  select salon_id, customer_id, auth_user_id into v_row
    from public.customer_identities where phone_hash = v_hash
   for update;

  if v_row.salon_id is null then
    raise exception 'app_admin: that number is not bound to any salon';
  end if;
  if v_row.salon_id = p_to_salon_id then
    raise exception 'app_admin: the customer is already at that salon';
  end if;
  if not app.salon_writable(p_to_salon_id) then
    raise exception 'app_admin: the destination salon is not active';
  end if;

  -- The old record stays with the old salon: history, loyalty, packages and
  -- the wallet. Marked so the old salon can see what happened.
  update public.customers set status = 'transferred_out', updated_at = now()
   where id = v_row.customer_id;

  -- Fresh at the new salon: zero balance, zero points, empty history.
  insert into public.customers (salon_id, auth_user_id, phone_hash)
  values (p_to_salon_id, v_row.auth_user_id, v_hash)
  returning id into v_new;

  update public.customer_identities
     set salon_id = p_to_salon_id, customer_id = v_new, bound_at = now()
   where phone_hash = v_hash;

  -- Consent does not travel between Data Fiduciaries: each salon is its own
  -- (RULES 11.6). Service messages only; marketing is asked afresh.
  insert into public.consents (salon_id, customer_id, purpose, granted, source)
  values
    (p_to_salon_id, v_new, 'service_communication', true, 'transfer'),
    (p_to_salon_id, v_new, 'promotional', false, 'transfer'),
    (p_to_salon_id, v_new, 'whatsapp', false, 'transfer'),
    (p_to_salon_id, v_new, 'photos', false, 'transfer');

  insert into public.binding_events
    (phone_hash, kind, from_salon_id, to_salon_id, actor_admin_id, reason,
     acknowledged_balance_paise)
  values
    (v_hash, 'transfer', v_row.salon_id, p_to_salon_id, p_actor_admin_id, p_reason,
     p_acknowledged_balance_paise);

  perform app_admin.audit(
    p_to_salon_id, p_actor_admin_id, 'customer.transferred', 'customer_identities',
    v_new::text, p_reason,
    jsonb_build_object('from_salon_id', v_row.salon_id, 'customer_id', v_row.customer_id),
    jsonb_build_object('to_salon_id', p_to_salon_id, 'customer_id', v_new,
                       'acknowledged_balance_paise', p_acknowledged_balance_paise));

  return v_new;
end;
$$;

select app_admin.close_privileges();
