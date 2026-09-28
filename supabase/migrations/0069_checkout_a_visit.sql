-- 0069 The wallet had no way to be spent
--
-- `app.wallet_debit_at_checkout` has existed since 0048 and **nothing has ever
-- called it**. Nothing sets `visits.payment_status` either, so every visit this
-- system has recorded is still `unpaid`. A customer could top up and could
-- never spend it; an owner could mark a visit complete and could never take the
-- money for it.
--
-- It went unnoticed because both halves are individually correct and both are
-- gated: the money test exercises the debit directly, and the booking test
-- exercises mark-complete. Nothing in between asserts that a completed visit can
-- be paid for, because nothing in between existed. The same shape as the
-- reminder that was scheduled and never sent (0066) - each piece proven, the
-- seam untested.
--
-- It also blocks M9 entirely: a referral reward releases only after a completed
-- **paid** first visit (RULES 10), and no visit could ever be paid.
--
-- Design notes that are rules rather than choices:
--
--   * **The amount comes from the visit, never from the caller.** A checkout
--     that accepts an amount is a checkout where a mistyped number is money.
--   * **The wallet is drawn down first, and only as far as it goes.** Partial
--     is a normal outcome, not an error: someone with Rs 200 of credit and a
--     Rs 450 bill pays Rs 200 from the wallet and Rs 250 at the counter.
--   * **Idempotent on the client action id**, because mark-complete works
--     offline and so must the settlement that follows it (RULES 13).

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
    -- A customer cannot settle their own bill: the salon decides what was
    -- delivered and what it cost.
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

  if v_visit.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_such_visit');
  end if;
  if v_visit.salon_id <> v_salon then
    -- RLS would hide it from a SELECT; this is a definer function, so the check
    -- is written out. Same answer as a visit that does not exist.
    return jsonb_build_object('ok', false, 'reason', 'no_such_visit');
  end if;
  if v_visit.payment_status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'payment_status', 'paid');
  end if;

  -- What is owed, from the VISIT. The tip is part of what the customer hands
  -- over, so it is part of what is settled.
  v_due := coalesce(v_visit.final_amount_paise, 0) + coalesce(v_visit.tip_paise, 0);

  select coalesce(sum(p.amount_paise), 0) into v_settled
    from public.payments p
   where p.visit_id = p_visit_id and p.status = 'captured';

  v_due := v_due - v_settled;

  if v_due <= 0 then
    update public.visits set payment_status = 'paid' where id = p_visit_id;
    return jsonb_build_object('ok', true, 'already', true, 'payment_status', 'paid');
  end if;

  -- The wallet, as far as it goes.
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
    -- Cash at the counter, or a card machine, or UPI to the salon's own QR.
    -- Recorded as a payment so the visit's settlement reads the same whatever
    -- it was paid with (ARCHITECTURE 6.3).
    insert into public.payments
      (salon_id, customer_id, visit_id, method, amount_paise, status, captured_at,
       idempotency_key)
    values
      (v_visit.salon_id, v_visit.customer_id, p_visit_id, p_other_method, v_from_other,
       'captured', now(), p_client_action_id::text || ':counter')
    on conflict (salon_id, idempotency_key) do nothing;
  end if;

  -- Recount rather than assume. A concurrent settlement, a retried action or a
  -- refused wallet debit all land here, and the status must describe the rows
  -- that exist, not the ones this call meant to write.
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
    'payment_status', (select v.payment_status::text from public.visits v where v.id = p_visit_id));
end;
$$;

comment on function public.checkout_visit is
  'Settles a completed visit: wallet first as far as it goes, the rest at the counter. The AMOUNT comes from the visit, never from the caller - a checkout that accepts an amount is a checkout where a mistyped number is money. Partial is a normal outcome. Idempotent on the client action id, because mark-complete works offline and the settlement after it must too.';

revoke all on function public.checkout_visit(uuid, uuid, boolean, public.payment_method)
  from public, anon;
grant execute on function public.checkout_visit(uuid, uuid, boolean, public.payment_method)
  to authenticated;
