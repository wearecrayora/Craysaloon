-- 0070 ON CONFLICT could not match a PARTIAL unique index
--
-- 0069's counter-payment insert used `on conflict (salon_id, idempotency_key)`.
-- The index is `unique (salon_id, idempotency_key) where idempotency_key is not
-- null` - partial - and PostgreSQL will not infer a partial index unless the
-- ON CONFLICT clause repeats its predicate. The statement raises at runtime:
-- "there is no unique or exclusion constraint matching the ON CONFLICT
-- specification".
--
-- **plpgsql_check found this before any test ran**, which is the whole argument
-- for adding it: 0069 applied cleanly, PostgreSQL accepted the body, and the
-- first person to discover it would otherwise have been an owner trying to take
-- payment at a counter.

create or replace function public.checkout_visit(
  p_visit_id         uuid,
  p_client_action_id uuid,
  p_use_wallet       boolean default true,
  p_other_method     public.payment_method default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit     record;
  v_role      text := app.current_app_role();
  v_salon     uuid := app.current_salon_id();
  v_due       bigint;
  v_settled   bigint;
  v_balance   bigint;
  v_from_wallet bigint := 0;
  v_from_other  bigint := 0;
  v_result    jsonb;
begin
  if v_role not in ('owner', 'manager', 'staff') then
    raise exception 'checkout_visit: only the salon may take payment'
      using errcode = '42501';
  end if;
  if p_client_action_id is null then
    raise exception 'checkout_visit: a client action id is required - this runs offline';
  end if;

  select v.id, v.salon_id, v.customer_id, v.final_amount_paise, v.tip_paise,
         v.payment_status
    into v_visit
    from public.visits v
   where v.id = p_visit_id
   for update;

  if v_visit.id is null or v_visit.salon_id <> v_salon then
    -- Same answer for "not yours" as for "does not exist".
    return jsonb_build_object('ok', false, 'reason', 'no_such_visit');
  end if;
  if v_visit.payment_status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'payment_status', 'paid');
  end if;

  v_due := coalesce(v_visit.final_amount_paise, 0) + coalesce(v_visit.tip_paise, 0);

  select coalesce(sum(p.amount_paise), 0) into v_settled
    from public.payments p
   where p.visit_id = p_visit_id and p.status = 'captured';

  v_due := v_due - v_settled;

  if v_due <= 0 then
    update public.visits set payment_status = 'paid' where id = p_visit_id;
    return jsonb_build_object('ok', true, 'already', true, 'payment_status', 'paid');
  end if;

  if p_use_wallet and v_visit.customer_id is not null then
    select coalesce(w.balance_paise, 0) into v_balance
      from public.wallet_accounts w
     where w.customer_id = v_visit.customer_id;

    v_from_wallet := least(coalesce(v_balance, 0), v_due);

    if v_from_wallet > 0 then
      v_result := app.wallet_debit_at_checkout(
        v_visit.salon_id, v_visit.customer_id, v_from_wallet,
        p_visit_id, p_client_action_id);

      if v_result ->> 'ok' <> 'true' then
        -- Someone else spent it between the read and the lock. Not an error:
        -- the counter takes the whole amount instead.
        v_from_wallet := 0;
      end if;
    end if;
  end if;

  v_from_other := v_due - v_from_wallet;

  if v_from_other > 0 then
    insert into public.payments
      (salon_id, customer_id, visit_id, method, amount_paise, status, captured_at,
       idempotency_key)
    values
      (v_visit.salon_id, v_visit.customer_id, p_visit_id, p_other_method, v_from_other,
       'captured', now(), p_client_action_id::text || ':counter')
    -- The predicate is repeated because the index is PARTIAL, and PostgreSQL
    -- will not infer a partial index without it (0070).
    on conflict (salon_id, idempotency_key) where idempotency_key is not null
      do nothing;
  end if;

  -- Recount rather than assume: a concurrent settlement, a retried action and a
  -- refused wallet debit all land here, and the status must describe the rows
  -- that exist rather than the ones this call meant to write.
  select coalesce(sum(p.amount_paise), 0) into v_settled
    from public.payments p
   where p.visit_id = p_visit_id and p.status = 'captured';

  update public.visits
     set payment_status = case
           when v_settled >= coalesce(v_visit.final_amount_paise, 0)
                              + coalesce(v_visit.tip_paise, 0)
             then 'paid'::public.visit_payment_status
           when v_settled > 0 then 'partial'::public.visit_payment_status
           else 'unpaid'::public.visit_payment_status
         end
   where id = p_visit_id;

  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  select v_visit.salon_id, 'visit.paid', p_visit_id,
         jsonb_build_object('customer_id', v_visit.customer_id,
                            'from_wallet_paise', v_from_wallet,
                            'from_counter_paise', v_from_other)
   where exists (select 1 from public.visits v
                  where v.id = p_visit_id and v.payment_status = 'paid');

  return jsonb_build_object(
    'ok', true, 'already', false,
    'from_wallet_paise', v_from_wallet,
    'from_counter_paise', v_from_other,
    'payment_status',
      (select v.payment_status::text from public.visits v where v.id = p_visit_id));
end;
$$;

comment on function public.checkout_visit is
  'Settles a completed visit: wallet first as far as it goes, the rest at the counter. The AMOUNT comes from the visit, never from the caller. Partial is a normal outcome. Idempotent on the client action id, because mark-complete works offline and the settlement after it must too.';
