-- 0082 The console wrappers audit what only they know
--
-- The admin-plane gate requires every mutating app_admin function to write
-- audit_log itself. 0081's two wrappers mutate by DELEGATION - to
-- wallet_correct and anonymise_customer, which both audit - and the gate does
-- not credit delegation. It should not: the day a wrapper delegates to
-- something that does NOT audit, a credited delegation is a silent mutation.
--
-- So each wrapper records the one fact the function it calls cannot:
--
--   * carry_out_erasure  -> WHICH REQUEST was executed. anonymise_customer logs
--                           the customer; only the wrapper knows the request
--                           that justified it, and that link is the evidence a
--                           regulator would ask for (DPDP s.12(3)).
--   * wallet_correct_by_phone -> that the correction was located BY PHONE, with
--                           only the last four digits - the lookup trail the
--                           binding desk keeps for everything else.

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
  v_row   record;
  v_entry bigint;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  select ci.customer_id, ci.salon_id into v_row
    from public.customer_identities ci
   where ci.phone_hash = app.phone_hash(p_phone);

  if v_row.customer_id is null then
    raise exception 'app_admin: that number is not bound to any salon';
  end if;

  -- The ONE function that posts a correction, and it audits the correction.
  v_entry := app_admin.wallet_correct(p_actor_admin_id, v_row.customer_id,
                                      p_amount_paise, p_reason);

  -- What only this wrapper knows: how the customer was found. Last four digits
  -- only, as lookup_binding records them (0036).
  perform app_admin.audit(
    v_row.salon_id, p_actor_admin_id, 'wallet.correction_located', 'customer_identities',
    v_row.customer_id::text, p_reason, null,
    jsonb_build_object('phone_last4', right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 4),
                       'ledger_entry', v_entry));

  return v_entry;
end;
$$;

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
  v_req    record;
  v_result jsonb;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  select r.customer_id, r.salon_id into v_req
    from public.data_rights_requests r
   where r.id = p_request_id
     and r.kind = 'erasure'
     and r.status in ('open', 'in_progress');

  if v_req.customer_id is null then
    raise exception 'app_admin: no open erasure request with that id';
  end if;

  -- anonymise_customer asserts, audits, anonymises and closes the request with
  -- an outcome (0051).
  v_result := app_admin.anonymise_customer(p_actor_admin_id, v_req.customer_id, p_reason);

  -- What only this wrapper knows: the REQUEST that justified the erasure.
  perform app_admin.audit(
    v_req.salon_id, p_actor_admin_id, 'data_right.erasure_executed', 'data_rights_requests',
    p_request_id::text, p_reason, null, v_result);

  return v_result;
end;
$$;

select app_admin.close_privileges();
