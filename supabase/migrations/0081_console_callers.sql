-- 0081 Three app_admin functions that no screen could reach
--
-- The orphan check (scripts/db/orphan-check.mjs) lists three functions that
-- are correct, gated, and callable by nothing that ships:
--
--   * app_admin.wallet_correct      - ledger caller 5 of five, the only human
--                                     path to a balance, with no console screen
--   * app_admin.anonymise_customer  - DPDP erasure (s.12(3)); requests could be
--                                     RAISED by customers and never CARRIED OUT
--   * app_admin.set_service_add_on  - so no add-on was ever offered with any
--                                     service, and create_booking refuses an
--                                     add-on that is not: add-ons could be
--                                     created and never sold
--
-- The third needs only a console form (0082's caller is in the console). The
-- first two need something to call them BY that does not widen what the
-- console can see:
--
--   * the binding desk works by PHONE NUMBER, resolved inside the database, and
--     never hands the console a customer id - so correction does the same, as a
--     thin wrapper over wallet_correct, which stays the one function that posts
--   * the erasure queue lists requests with NO customer name or number. The
--     operator acts on the request id; the database resolves the customer.

-- ---------------------------------------------------------------------------
-- Correction, by phone number
-- ---------------------------------------------------------------------------

create or replace function app_admin.wallet_correct_by_phone(
  p_actor_admin_id uuid,
  p_phone          text,
  p_amount_paise   bigint,
  p_reason         text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid;
begin
  -- wallet_correct asserts super-admin and requires a reason itself; asserting
  -- here too means an ordinary operator learns nothing, not even whether the
  -- number is bound.
  perform app_admin.assert_super_admin(p_actor_admin_id);

  select ci.customer_id into v_customer
    from public.customer_identities ci
   where ci.phone_hash = app.phone_hash(p_phone);

  if v_customer is null then
    raise exception 'app_admin: that number is not bound to any salon';
  end if;

  -- The ONE function that posts a correction. This is only how it is found.
  return app_admin.wallet_correct(p_actor_admin_id, v_customer, p_amount_paise, p_reason);
end;
$$;

comment on function app_admin.wallet_correct_by_phone is
  'How the console reaches wallet_correct (ledger caller 5): by phone number, resolved in the database, the way the binding desk already works - so the console is never handed a customer id. Super-admin only; wallet_correct audits it.';

-- ---------------------------------------------------------------------------
-- The erasure queue
-- ---------------------------------------------------------------------------

create or replace function app_admin.list_data_rights_requests(p_actor_admin_id uuid)
returns table (
  request_id   uuid,
  salon_name   text,
  kind         text,
  status       text,
  requested_at timestamptz,
  due_at       timestamptz,
  overdue      boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  -- No customer name, number or id. The operator acts on the REQUEST, and the
  -- database resolves whose it is - the console never needs to know.
  return query
    select r.id, s.display_name, r.kind, r.status, r.requested_at, r.due_at,
           (r.due_at < now() and r.status in ('open', 'in_progress'))
      from public.data_rights_requests r
      join public.salons s on s.id = r.salon_id
     where r.status in ('open', 'in_progress')
     order by r.due_at;
end;
$$;

comment on function app_admin.list_data_rights_requests is
  'Open data-rights requests across salons, oldest deadline first, with NO customer identifiers - the operator acts on the request id. Crayora is the escalation when a salon does not answer in 30 days (RULES 11.7a).';

create or replace function app_admin.carry_out_erasure(
  p_actor_admin_id uuid,
  p_request_id     uuid,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid;
begin
  select r.customer_id into v_customer
    from public.data_rights_requests r
   where r.id = p_request_id
     and r.kind = 'erasure'
     and r.status in ('open', 'in_progress');

  if v_customer is null then
    raise exception 'app_admin: no open erasure request with that id';
  end if;

  -- anonymise_customer asserts the actor, audits, anonymises and closes the
  -- request WITH an outcome (0051). This is only how the console reaches it.
  return app_admin.anonymise_customer(p_actor_admin_id, v_customer, p_reason);
end;
$$;

comment on function app_admin.carry_out_erasure is
  'How the console reaches anonymise_customer: by REQUEST id, so an erasure can only be carried out against a request the customer actually made, and the console never handles the customer''s identity.';

select app_admin.close_privileges();
