-- 0085 The customer pays their own bill: wallet, UPI, or the counter
--
-- Requested 29 Sep 2026: when the stylist marks the work complete, the customer
-- is told the bill is ready and pays it themselves - from their wallet, by UPI
-- through Razorpay, or with cash at the counter. Decided the same day:
--
--   * **Cash is confirmed by STAFF.** The customer's "I'll pay at the counter"
--     only tells the counter; the visit becomes paid when someone takes the
--     money (the Take payment sheet, 0069/0079). A customer can never mark their
--     own bill paid.
--
-- Two rules shape the money here:
--
--   * **The amount is the server's**, always: what the visit cost, less what is
--     already settled. The app sends a visit id, never a number.
--   * **A Razorpay payment for a BILL settles the visit; it does not credit the
--     wallet.** Until now every captured payment was a top-up, and
--     record_payment_captured credited the wallet. A bill payment that did that
--     would turn the customer's haircut into wallet credit and leave the visit
--     unpaid - so the capture now branches on whether the payment belongs to a
--     visit. Both kinds settle into the SALON's own Razorpay account; the
--     licensing boundary is unchanged (RULES 8).

alter table public.visits
  add column counter_payment_requested_at timestamptz;

comment on column public.visits.counter_payment_requested_at is
  'The customer said they will pay at the counter. It changes NOTHING about whether the visit is paid - staff confirm the cash (decision of 29 Sep 2026). Shown on the day view so the counter knows.';

-- ---------------------------------------------------------------------------
-- 1. One definition of "is this visit paid"
-- ---------------------------------------------------------------------------
--
-- checkout_visit (0070) computes the same rule inline: settled >= price + tip
-- is paid, anything settled is partial. It is left alone here because it is
-- gated and working; the two are asserted to agree by the start-and-pay gate.

create or replace function app.refresh_visit_payment_status(p_visit_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit   record;
  v_due     bigint;
  v_settled bigint;
  v_status  public.visit_payment_status;
begin
  select v.id, v.salon_id, v.customer_id, v.final_amount_paise, v.tip_paise,
         v.payment_status
    into v_visit
    from public.visits v
   where v.id = p_visit_id
   for update;

  if v_visit.id is null then
    return null;
  end if;

  v_due := coalesce(v_visit.final_amount_paise, 0) + coalesce(v_visit.tip_paise, 0);

  select coalesce(sum(p.amount_paise), 0) into v_settled
    from public.payments p
   where p.visit_id = p_visit_id and p.status = 'captured';

  v_status := case when v_settled >= v_due then 'paid'::public.visit_payment_status
                   when v_settled > 0 then 'partial'::public.visit_payment_status
                   else 'unpaid'::public.visit_payment_status end;

  update public.visits set payment_status = v_status where id = p_visit_id;

  -- visit.paid ONCE, on the transition - it is what a referral reward keys off.
  if v_status = 'paid' and v_visit.payment_status <> 'paid' then
    insert into public.domain_events (salon_id, type, aggregate_id, payload)
    values (v_visit.salon_id, 'visit.paid', p_visit_id,
            jsonb_build_object('customer_id', v_visit.customer_id, 'settled_paise', v_settled));
  end if;

  -- Paid twice - UPI landed after the counter had already taken cash. The money
  -- has moved and cannot be un-moved here; the owner has to see it to refund it
  -- from their own Razorpay dashboard.
  if v_settled > v_due and not exists (
       select 1 from public.domain_events e
        where e.type = 'visit.overpaid' and e.aggregate_id = p_visit_id) then
    insert into public.domain_events (salon_id, type, aggregate_id, payload)
    values (v_visit.salon_id, 'visit.overpaid', p_visit_id,
            jsonb_build_object('due_paise', v_due, 'settled_paise', v_settled));
  end if;

  return v_status::text;
end;
$$;

revoke all on function app.refresh_visit_payment_status(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. The customer's bills
-- ---------------------------------------------------------------------------

create or replace function public.my_bills()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
begin
  if v_salon is null or v_customer is null then
    raise exception 'my_bills: no customer in this session' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'visit_id', v.id,
             'completed_at', v.completed_at,
             'services', (select string_agg(bi.name_snapshot, ', ' order by bi.created_at)
                            from public.booking_items bi
                           where bi.booking_id = v.booking_id),
             'total_paise', coalesce(v.final_amount_paise, 0) + coalesce(v.tip_paise, 0),
             -- What is LEFT to pay: the price less what has already settled.
             'due_paise', coalesce(v.final_amount_paise, 0) + coalesce(v.tip_paise, 0)
                          - coalesce((select sum(p.amount_paise) from public.payments p
                                       where p.visit_id = v.id and p.status = 'captured'), 0),
             'counter_requested', v.counter_payment_requested_at is not null)
           order by v.completed_at desc)
      from public.visits v
     where v.salon_id = v_salon
       and v.customer_id = v_customer
       and v.payment_status in ('unpaid', 'partial')
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.my_bills() from public, anon;
grant execute on function public.my_bills() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Paying from the wallet
-- ---------------------------------------------------------------------------

create or replace function public.pay_bill_from_wallet(
  p_client_action_id uuid,
  p_visit_id         uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_visit    record;
  v_due      bigint;
  v_balance  bigint;
  v_take     bigint;
  v_result   jsonb;
begin
  if v_salon is null or v_customer is null then
    raise exception 'pay_bill_from_wallet: only the customer pays their own bill'
      using errcode = '42501';
  end if;

  select v.id, v.customer_id, v.final_amount_paise, v.tip_paise
    into v_visit
    from public.visits v
   where v.id = p_visit_id and v.salon_id = v_salon
   for update;

  -- Someone else's bill answers exactly like no bill at all.
  if v_visit.id is null or v_visit.customer_id <> v_customer then
    return jsonb_build_object('ok', false, 'reason', 'no_such_bill');
  end if;

  v_due := coalesce(v_visit.final_amount_paise, 0) + coalesce(v_visit.tip_paise, 0)
           - coalesce((select sum(p.amount_paise) from public.payments p
                        where p.visit_id = p_visit_id and p.status = 'captured'), 0);

  if v_due <= 0 then
    return jsonb_build_object('ok', true, 'already', true,
                              'payment_status', app.refresh_visit_payment_status(p_visit_id));
  end if;

  select coalesce(w.balance_paise, 0) into v_balance
    from public.wallet_accounts w where w.customer_id = v_customer;

  -- As far as the wallet goes, and no further. The rest is UPI or the counter.
  v_take := least(coalesce(v_balance, 0), v_due);

  if v_take > 0 then
    -- Caller 2 of five: the ONE spending path (RULES 5.2). Idempotent on the
    -- action id, so a double tap spends once.
    v_result := app.wallet_debit_at_checkout(
      v_salon, v_customer, v_take, p_visit_id, p_client_action_id);
    if v_result ->> 'ok' <> 'true' then
      return jsonb_build_object('ok', false, 'reason', coalesce(v_result ->> 'reason', 'refused'));
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'already', false,
    'from_wallet_paise', v_take,
    'remaining_paise', v_due - v_take,
    'payment_status', app.refresh_visit_payment_status(p_visit_id));
end;
$$;

comment on function public.pay_bill_from_wallet is
  'The customer spends their own wallet on their own bill, as far as it goes. Through wallet_debit_at_checkout - the one spending path - and idempotent on the action id. The amount is the server''s.';

revoke all on function public.pay_bill_from_wallet(uuid, uuid) from public, anon;
grant execute on function public.pay_bill_from_wallet(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Paying by UPI - the payment a Razorpay order is made for
-- ---------------------------------------------------------------------------

create or replace function public.start_bill_payment(
  p_client_action_id uuid,
  p_visit_id         uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_visit    record;
  v_due      bigint;
  v_payment  uuid;
begin
  if v_salon is null or v_customer is null then
    raise exception 'start_bill_payment: only the customer pays their own bill'
      using errcode = '42501';
  end if;

  -- The same action id reaches the same payment and the same order.
  select p.id, p.amount_paise into v_payment, v_due
    from public.payments p
   where p.salon_id = v_salon and p.idempotency_key = p_client_action_id::text;
  if v_payment is not null then
    return jsonb_build_object('ok', true, 'already', true,
                              'payment_id', v_payment, 'amount_paise', v_due);
  end if;

  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  select v.id, v.customer_id, v.final_amount_paise, v.tip_paise
    into v_visit
    from public.visits v
   where v.id = p_visit_id and v.salon_id = v_salon;

  if v_visit.id is null or v_visit.customer_id <> v_customer then
    return jsonb_build_object('ok', false, 'reason', 'no_such_bill');
  end if;

  -- The amount is what is LEFT: the price, less anything already settled -
  -- including a wallet payment made a moment ago.
  v_due := coalesce(v_visit.final_amount_paise, 0) + coalesce(v_visit.tip_paise, 0)
           - coalesce((select sum(p.amount_paise) from public.payments p
                        where p.visit_id = p_visit_id and p.status = 'captured'), 0);

  if v_due <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'already_paid');
  end if;

  insert into public.payments
    (salon_id, customer_id, visit_id, method, amount_paise, status, idempotency_key)
  values
    (v_salon, v_customer, p_visit_id, 'upi', v_due, 'created', p_client_action_id::text)
  returning id into v_payment;

  return jsonb_build_object('ok', true, 'already', false,
                            'payment_id', v_payment, 'amount_paise', v_due);
end;
$$;

comment on function public.start_bill_payment is
  'Creates the payment a Razorpay order is made for, for what is LEFT on a bill. Carries the visit id, which is how the capture knows to settle the visit rather than credit the wallet (0085). Idempotent on the action id.';

revoke all on function public.start_bill_payment(uuid, uuid) from public, anon;
grant execute on function public.start_bill_payment(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. "I'll pay at the counter" - which settles nothing
-- ---------------------------------------------------------------------------

create or replace function public.request_counter_payment(p_visit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_owner    uuid;
begin
  if v_salon is null or v_customer is null then
    raise exception 'request_counter_payment: customers only' using errcode = '42501';
  end if;

  select v.customer_id into v_owner
    from public.visits v where v.id = p_visit_id and v.salon_id = v_salon;

  if v_owner is null or v_owner <> v_customer then
    return jsonb_build_object('ok', false, 'reason', 'no_such_bill');
  end if;

  -- A flag for the counter, and NOTHING about the money. The visit becomes paid
  -- when staff take the cash (decision of 29 Sep 2026).
  update public.visits
     set counter_payment_requested_at = coalesce(counter_payment_requested_at, now())
   where id = p_visit_id;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.request_counter_payment is
  'The customer will pay at the counter. Tells the counter; settles NOTHING - staff confirm the cash through Take payment, and a customer can never mark their own bill paid.';

revoke all on function public.request_counter_payment(uuid) from public, anon;
grant execute on function public.request_counter_payment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The capture branches: a bill settles its visit, a top-up credits a wallet
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into strict v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'record_payment_captured';

  -- (a) read the visit the payment belongs to, if any
  v_new := replace(v_def,
    $x$select p.id, p.salon_id, p.customer_id, p.amount_paise, p.status$x$,
    $x$select p.id, p.salon_id, p.customer_id, p.amount_paise, p.status, p.visit_id$x$);
  if v_new = v_def then
    raise exception '0085: record_payment_captured''s payment read was not where expected';
  end if;
  v_def := v_new;

  -- (b) a bill SETTLES ITS VISIT; only a top-up credits the wallet
  v_new := replace(v_def,
    $x$  -- Credit follows capture, and is itself idempotent per payment (0048).
  return jsonb_build_object('ok', true, 'already', false,
                            'credit', app.wallet_credit_from_payment(p_payment_id));$x$,
    $x$  -- A payment for a BILL settles its visit and never touches the wallet: a
  -- haircut paid by UPI is not wallet credit (0085).
  if v_payment.visit_id is not null then
    return jsonb_build_object('ok', true, 'already', false,
                              'settled', app.refresh_visit_payment_status(v_payment.visit_id));
  end if;

  -- A TOP-UP credits the wallet. Credit follows capture, and is itself
  -- idempotent per payment (0048).
  return jsonb_build_object('ok', true, 'already', false,
                            'credit', app.wallet_credit_from_payment(p_payment_id));$x$);
  if v_new = v_def then
    raise exception '0085: record_payment_captured''s credit step was not where expected';
  end if;

  execute v_new;
end;
$$;

comment on function app.record_payment_captured is
  'Marks a payment captured after RE-VERIFYING the amount against the row we created. Then branches: a payment for a visit settles that visit; a top-up credits the wallet (0085). Idempotent: a redelivered webhook does nothing twice.';

select app_admin.close_privileges();
