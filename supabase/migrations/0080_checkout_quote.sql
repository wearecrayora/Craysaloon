-- 0080 How much cash to collect, before collecting it
--
-- Checkout draws the customer's wallet down first and records the rest as
-- collected at the counter (0069). That leaves the owner one question the app
-- has to answer truthfully: HOW MUCH do I take in cash?
--
-- Offline, the app cannot know: the balance on the phone is a cached copy, and
-- a guess that turned out high would have the server record cash the owner
-- never collected - the books wrong in the salon's favour on paper and against
-- it in the till. So the answer comes from here, online, read-only, and the app
-- says plainly when it cannot get one (RULES 9: money does not move offline).
--
-- Same arithmetic as checkout_visit, so the quote cannot disagree with the
-- settlement it precedes - the lesson of 0058.

create or replace function public.checkout_quote(p_booking_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon   uuid := app.current_salon_id();
  v_visit   record;
  v_settled bigint;
  v_due     bigint;
  v_balance bigint;
  v_wallet  bigint;
begin
  if app.current_app_role() not in ('owner', 'manager', 'staff') then
    raise exception 'checkout_quote: only the salon may take payment' using errcode = '42501';
  end if;

  select v.id, v.customer_id, v.final_amount_paise, v.tip_paise, v.payment_status
    into v_visit
    from public.visits v
   where v.booking_id = p_booking_id and v.salon_id = v_salon;

  if v_visit.id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_completed');
  end if;

  select coalesce(sum(p.amount_paise), 0) into v_settled
    from public.payments p
   where p.visit_id = v_visit.id and p.status = 'captured';

  v_due := greatest(coalesce(v_visit.final_amount_paise, 0)
                    + coalesce(v_visit.tip_paise, 0) - v_settled, 0);

  select coalesce(w.balance_paise, 0) into v_balance
    from public.wallet_accounts w where w.customer_id = v_visit.customer_id;

  v_wallet := least(coalesce(v_balance, 0), v_due);

  return jsonb_build_object(
    'ok', true,
    'due_paise', v_due,
    'wallet_available_paise', coalesce(v_balance, 0),
    'from_wallet_paise', v_wallet,
    'from_counter_paise', v_due - v_wallet,
    'already_paid', v_due = 0);
end;
$$;

comment on function public.checkout_quote is
  'Read-only: what checkout_booking WOULD take from the wallet and what the owner must collect at the counter. Online only by design - a guessed split made offline could record cash that was never collected. Same arithmetic as checkout_visit (0069).';

revoke all on function public.checkout_quote(uuid) from public, anon;
grant execute on function public.checkout_quote(uuid) to authenticated;
