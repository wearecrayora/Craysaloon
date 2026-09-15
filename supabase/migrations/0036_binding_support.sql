-- 0036 Customer binding support: super-admin only, looked up, disclosed
--
-- What the console's Customer binding screen (IMPLEMENTATION K12) needs, and
-- one defect in 0034/0035 that it exposed.
--
-- 1. DEFECT: unbind_customer and transfer_customer checked for an ACTIVE
--    platform admin. RULES 4.5 and ARCHITECTURE 14.3 (invariant 7) say
--    SUPER-admin only: a binding change moves a customer between businesses,
--    and an ordinary operator account must not be able to do it. The bind-flow
--    gate used a non-super operator and passed - the fixture was wrong, not the
--    rule. Both functions now call assert_super_admin.
--
-- 2. app_admin.lookup_binding. RULES 4.6 says support must have LOOKED UP and
--    DISCLOSED the balance before a transfer; nothing let them look it up.
--    RULES 2 forbids a global phone-number lookup across salons. Both hold
--    because this is not a search: one complete number, typed by a super-admin,
--    with a reason, written to audit_log on every call - including calls that
--    find nothing, so probing numbers leaves a trail. No partial match, no list,
--    no tenant role can reach it.
--
-- 3. A transfer's acknowledged balance must EQUAL the balance. 0034 accepted
--    any non-negative number, so "0" satisfied the parameter without anyone
--    looking. Now the number the operator types must match what the customer
--    actually holds at that moment; if a top-up lands in between, the transfer
--    is refused and the new figure has to be disclosed.

-- ---------------------------------------------------------------------------
-- assert_super_admin
-- ---------------------------------------------------------------------------

create or replace function app_admin.assert_super_admin(p_actor_admin_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if not exists (
    select 1 from public.platform_admins
     where id = p_actor_admin_id and active and is_super
  ) then
    raise exception 'app_admin: this action is for a Crayora super-admin only'
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- The balance a customer would leave behind: one definition, used by the
-- lookup and by the transfer, so the figure disclosed is the figure checked.
-- ---------------------------------------------------------------------------

create or replace function app_admin.binding_balance(p_customer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'balance_paise',
      coalesce((select balance_paise from public.wallet_accounts where customer_id = p_customer_id), 0),
    'paid_paise',
      coalesce((select sum(remaining_paise) from public.wallet_lots
                 where customer_id = p_customer_id and kind = 'paid'), 0),
    'bonus_paise',
      coalesce((select sum(remaining_paise) from public.wallet_lots
                 where customer_id = p_customer_id and kind = 'bonus'
                   and expired_at is null and (expires_at is null or expires_at > now())), 0)
  )
$$;

-- ---------------------------------------------------------------------------
-- lookup_binding
-- ---------------------------------------------------------------------------

create or replace function app_admin.lookup_binding(
  p_actor_admin_id uuid,
  p_phone          text,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash    bytea;
  v_row     record;
  v_result  jsonb;
  v_wallet  int;
  v_book    int;
  v_visit   int;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: a lookup needs a reason - it is recorded';
  end if;

  -- canonical_phone raises on anything that is not one complete number, so
  -- there is no partial or pattern match to probe with.
  perform app.canonical_phone(p_phone);
  v_hash := app.phone_hash(p_phone);

  select ci.salon_id, ci.customer_id, ci.bound_at, s.display_name, s.join_code,
         s.status::text as salon_status, c.status::text as customer_status
    into v_row
    from public.customer_identities ci
    join public.salons s on s.id = ci.salon_id
    join public.customers c on c.id = ci.customer_id
   where ci.phone_hash = v_hash;

  if v_row.salon_id is null then
    v_result := jsonb_build_object('bound', false);
  else
    select count(*) into v_wallet from public.wallet_transactions where customer_id = v_row.customer_id;
    select count(*) into v_book from public.bookings where customer_id = v_row.customer_id;
    select count(*) into v_visit
      from public.visits v join public.bookings b on b.id = v.booking_id
     where b.customer_id = v_row.customer_id;

    v_result := jsonb_build_object(
      'bound', true,
      'salon_id', v_row.salon_id,
      'salon_name', v_row.display_name,
      'join_code', v_row.join_code,
      'salon_status', v_row.salon_status,
      'customer_status', v_row.customer_status,
      'bound_at', v_row.bound_at,
      'wallet_transactions', v_wallet,
      'bookings', v_book,
      'visits', v_visit,
      -- The same rule unbind_customer enforces, so the screen offers the
      -- action that will actually work.
      'can_unbind', (v_wallet = 0 and v_book = 0 and v_visit = 0)
    ) || app_admin.binding_balance(v_row.customer_id);
  end if;

  -- Every lookup is recorded, found or not. Last four digits only: the audit
  -- log is read by more people than this screen is.
  perform app_admin.audit(
    v_row.salon_id, p_actor_admin_id, 'customer.binding_looked_up', 'customer_identities',
    'xxxxxx' || right(app.canonical_phone(p_phone), 4), p_reason, null,
    jsonb_build_object('bound', v_row.salon_id is not null));

  return v_result;
end;
$$;

comment on function app_admin.lookup_binding is
  'Super-admin only. One complete number, a reason, and an audit row on every call - found or not. The support half of RULES 4.6; not a search (RULES 2).';

-- ---------------------------------------------------------------------------
-- unbind_customer: super-admin only (0034 body otherwise unchanged)
-- ---------------------------------------------------------------------------

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
  perform app_admin.assert_super_admin(p_actor_admin_id);

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

  -- Fires customer_identities_changed (0035): the customer's sessions end.
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

-- ---------------------------------------------------------------------------
-- transfer_customer: super-admin only, and the acknowledged balance must be
-- the real one (0035 body otherwise unchanged)
-- ---------------------------------------------------------------------------

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
  v_hash    bytea;
  v_row     record;
  v_new     uuid;
  v_balance bigint;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

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

  -- The figure disclosed must be the figure they hold. Locked with the
  -- identity row above, so it cannot change between this check and the move.
  select balance_paise into v_balance
    from public.wallet_accounts where customer_id = v_row.customer_id
   for update;
  v_balance := coalesce(v_balance, 0);
  if p_acknowledged_balance_paise <> v_balance then
    raise exception
      'app_admin: the acknowledged balance does not match what the customer holds - look the number up again and tell them the current figure';
  end if;

  -- The old record stays with the old salon: history, loyalty, packages and
  -- the wallet. Marked so the old salon can see what happened.
  update public.customers set status = 'transferred_out', updated_at = now()
   where id = v_row.customer_id;

  -- Fresh at the new salon: zero balance, zero points, empty history - and the
  -- number, so the new salon can reach the customer it has just been given.
  insert into public.customers (salon_id, auth_user_id, phone_hash, phone)
  values (p_to_salon_id, v_row.auth_user_id, v_hash, app.canonical_phone(p_phone))
  returning id into v_new;

  -- Fires customer_identities_changed (0035): customer.bound at the new salon,
  -- and every session minted under the old binding ends.
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
