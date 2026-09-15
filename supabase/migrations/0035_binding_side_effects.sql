-- 0035 What a binding change must also do - on every path, present and future
--
-- Two things ARCHITECTURE 5.2 and 5.4 require that 0034 did not do, plus one
-- defect in 0034.
--
-- 1. EMIT customer.bound. The welcome automation (J) and everything else that
--    reacts to a new customer read domain_events. 0034 bound customers silently.
--
-- 2. END OLD SESSIONS WHEN A BINDING MOVES OR GOES. RLS reads salon_id from the
--    token, and a token lives an hour. After an unbind or a transfer, a session
--    minted before it would keep refreshing with the old salon_id - the hook
--    stamps the new one only on the NEXT mint, and a refresh token keeps an old
--    session alive indefinitely. The spec's answer was a client-honoured `cver`
--    bump; deleting the sessions is stronger because it needs no cooperation
--    from the client: the refresh fails, the app must log in again, and the new
--    token carries the new salon. The access token already issued lives out
--    its remaining hour at most - and RULES 4 already requires money paths to
--    re-check the binding in the database, never trust the token alone.
--
-- Both are a TRIGGER on customer_identities rather than lines in each function,
-- so a path written later cannot forget them.
--
-- 3. DEFECT: transfer_customer created the destination customer with no phone
--    number, so the new salon could not contact the customer it had just been
--    given. The operator types the number and it hashes to the binding, so it
--    is the verified number; it is now stored, canonicalised.

-- ---------------------------------------------------------------------------
-- 1 + 2. The trigger
-- ---------------------------------------------------------------------------

create or replace function app.on_binding_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.domain_events (salon_id, type, aggregate_id, payload)
    values (new.salon_id, 'customer.bound', new.customer_id, jsonb_build_object('via', 'join'));
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.salon_id is distinct from old.salon_id then
      insert into public.domain_events (salon_id, type, aggregate_id, payload)
      values (new.salon_id, 'customer.bound', new.customer_id,
              jsonb_build_object('via', 'transfer'));
    else
      return new;
    end if;
  end if;

  -- UPDATE that moved the salon, or DELETE: every session minted under the old
  -- binding ends now. Guarded because GoTrue, not this schema, owns the table.
  if to_regclass('auth.sessions') is not null then
    delete from auth.sessions where user_id = old.auth_user_id;
  end if;

  return coalesce(new, old);
end;
$$;

comment on function app.on_binding_changed is
  'A binding is created, moved or removed: emit customer.bound for a new or moved binding, and end every Auth session of the customer whose binding moved or went (0035).';

revoke all on function app.on_binding_changed() from public, anon, authenticated;

create trigger customer_identities_changed
  after insert or update of salon_id or delete on public.customer_identities
  for each row execute function app.on_binding_changed();

-- ---------------------------------------------------------------------------
-- 3. transfer_customer stores the destination's copy of the number
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
  v_hash   bytea;
  v_row    record;
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

  -- Fresh at the new salon: zero balance, zero points, empty history - and the
  -- number, so the new salon can reach the customer it has just been given.
  -- p_phone hashed to this binding above, so it is the bound number.
  insert into public.customers (salon_id, auth_user_id, phone_hash, phone)
  values (p_to_salon_id, v_row.auth_user_id, v_hash, app.canonical_phone(p_phone))
  returning id into v_new;

  -- Fires customer_identities_changed: customer.bound at the new salon, and
  -- every session minted under the old binding ends.
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
