-- 0101 OTP sends are capped per salon per day (PRD 20).
--
-- Found 13 Oct 2026 by the PRD 20 release audit: "OTP is rate-limited per
-- phone, IP, device AND PER SALON PER DAY". otp_begin limited the phone (3 per
-- 10 minutes) and the caller's address (10 per 10 minutes) - and nothing else.
-- Every send is paid from the SALON's own Message Central balance, so someone
-- walking a salon's customer numbers from many addresses could spend that
-- balance without limit: joins are capped at 500 a salon a day (start_join),
-- but a re-login of an already bound number goes straight to otp_begin.
--
-- Now: 1,000 sends per salon per UTC day - twice the join cap, so a busy QR
-- day at the counter (every join an OTP, some resent) fits; at Message
-- Central's per-OTP price it bounds the worst day to a few hundred rupees.
-- Counted only for a send that will actually happen (after the blocked check).
-- The first refusal of the day says so (`first_refusal`), and otp-send alerts
-- on exactly that one - an attack or a genuinely enormous day, either of which
-- Crayora should hear about once, not a thousand times.
--
-- "Device" in PRD 20 is the caller's address here: the app has no device id
-- an attacker could not rotate per request, which is why the caller bucket
-- (0030) is keyed on the customer's address.

do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.otp_begin(text, text)'::regprocedure);
  v_new := replace(v_def,
$old$  return jsonb_build_object(
    'ok', true,$old$,
$new$  -- Per salon per day (0101): every send spends the salon's own balance.
  if not app.rate_limit_hit(
       'otp_send_salon:' || (v_sender ->> 'salon_id'), 1000, interval '1 day') then
    return jsonb_build_object(
      'ok', false, 'reason', 'salon_daily_limit',
      -- For otp-send's alert only; never sent on to the caller.
      'salon_id', v_sender ->> 'salon_id',
      'first_refusal', (select c.count = 1001 from public.rate_limit_counters c
                         where c.bucket = 'otp_send_salon:' || (v_sender ->> 'salon_id')
                         order by c.window_start desc limit 1));
  end if;

  return jsonb_build_object(
    'ok', true,$new$);
  if v_new = v_def then
    raise exception '0101: otp_begin did not change - its return block moved';
  end if;
  execute v_new;
end;
$$;
