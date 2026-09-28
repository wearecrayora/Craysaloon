-- RELEASE GATE: Refer & Earn (M9)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PHASES M9 names three conditions, and every one of them is a way somebody
-- gets paid for nothing:
--
--   * a reward releases only after a completed, **PAID** first visit
--   * self-referral is rejected by a **constraint**, not by code
--   * a cancelled or refunded visit releases nothing
--
-- The fourth is not in the milestone card but is the one that would actually
-- happen: the sweep runs every minute, so the release must pay ONCE however
-- many times it is called.

select plan(20);

select set_config('app.phone_hash_pepper', 'referral-test-pepper', true);

insert into auth.users (id) values
  ('11111111-bbbb-4000-8000-00000000000a'),
  ('11111111-bbbb-4000-8000-00000000000b'),
  ('11111111-bbbb-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('11111111-bbbb-4000-8000-00000000000f', 'refer@crayora.test', 'Refer Op', true, true);

-- Rs 100 to the referrer, Rs 50 to the friend. The shape the console writes.
insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at, reward_rule)
values ('11111111-0000-4000-8000-000000000001', 'Refer Salon Ltd', 'Refer Salon',
        'CRAY-RFRSAB', 'active', '11111111-bbbb-4000-8000-00000000000f', now(),
        '{"referrer_paise": 10000, "referred_paise": 5000, "bonus_expiry_days": 90}'::jsonb);

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('11111111-1111-4000-8000-00000000000a', '11111111-0000-4000-8000-000000000001',
   '11111111-bbbb-4000-8000-00000000000a', 'Meera', app.phone_hash('9733300011')),
  ('11111111-1111-4000-8000-00000000000b', '11111111-0000-4000-8000-000000000001',
   '11111111-bbbb-4000-8000-00000000000b', 'Farah', app.phone_hash('9733300012'));

insert into public.staff (id, salon_id, name, active)
values ('11111111-3333-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001',
        'Refer stylist', true);

-- ---------------------------------------------------------------------------
-- Meera gets a code
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-bbbb-4000-8000-00000000000a",'
  '"app_role":"customer",'
  '"salon_id":"11111111-0000-4000-8000-000000000001"}',
  true
);

create temp table meera as select public.my_referral_code() as r;
grant select on meera to public;

select matches((select r ->> 'code' from meera), '^[A-HJKMNP-Z2-9]{6}$',
  'the code uses the unambiguous alphabet - it gets read aloud and typed by somebody else');

select is((select r ->> 'referrer_paise' from meera), '10000',
  'and the screen is told what the ledger will actually pay');

select is(
  (select r ->> 'code' from meera),
  (public.my_referral_code() ->> 'code'),
  'asking twice returns the SAME code - one already given to a friend must keep working');

select is(
  (public.claim_referral((select r ->> 'code' from meera)) ->> 'reason'),
  'self_referral',
  'and Meera cannot refer herself');

reset role;

-- The constraint refuses it too, independently of the function above.
select throws_ok(
  $q$update public.referrals
        set referred_customer_id = referrer_id
      where salon_id = '11111111-0000-4000-8000-000000000001'$q$,
  '23514', null,
  'self-referral is refused by a CONSTRAINT, not only by code');

-- ---------------------------------------------------------------------------
-- Farah claims it
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-bbbb-4000-8000-00000000000b",'
  '"app_role":"customer",'
  '"salon_id":"11111111-0000-4000-8000-000000000001"}',
  true
);

select is(
  (public.claim_referral('ZZZZZZ') ->> 'reason'),
  'unknown_code',
  'an unknown code is refused');

create temp table claimed as
  select public.claim_referral((select r ->> 'code' from meera)) as r;
grant select on claimed to public;

select is((select r ->> 'ok' from claimed), 'true', 'a friend can claim it');

select is((select r ->> 'referred_paise' from claimed), '5000',
  'and is told what they get');

select is(
  (public.claim_referral((select r ->> 'code' from meera)) ->> 'reason'),
  'already_referred',
  'but only once - a second referrer is refused');

reset role;

select is(
  (select status::text from public.referrals
    where salon_id = '11111111-0000-4000-8000-000000000001'),
  'pending_visit',
  'the referral waits for a visit');

-- ---------------------------------------------------------------------------
-- Nothing is paid until the visit is PAID
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('11111111-4444-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001',
        '11111111-1111-4000-8000-00000000000b', '11111111-3333-4000-8000-000000000001',
        now(), now() + interval '30 minutes', 'completed');

insert into public.visits (id, salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values ('11111111-5555-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001',
        '11111111-4444-4000-8000-000000000001', '11111111-1111-4000-8000-00000000000b',
        '11111111-3333-4000-8000-000000000001', 60000, now());

select is(
  (app.release_due_referrals('11111111-0000-4000-8000-000000000001') ->> 'released'),
  '0',
  'a COMPLETED visit releases nothing - completing is not paying (RULES 10)');

select is(
  (select coalesce(sum(balance_paise), 0)::bigint from public.wallet_accounts
    where salon_id = '11111111-0000-4000-8000-000000000001'),
  0::bigint,
  'and no money has moved');

-- Now pay for it, as the salon.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-bbbb-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"11111111-0000-4000-8000-000000000001"}',
  true
);

select is(
  (public.checkout_visit('11111111-5555-4000-8000-000000000001',
                         '11111111-9999-4000-8000-000000000001') ->> 'payment_status'),
  'paid',
  'the salon takes the money at the counter');

reset role;

create temp table released as
  select app.release_due_referrals('11111111-0000-4000-8000-000000000001') as r;
grant select on released to public;

select is((select r ->> 'released' from released), '1',
  'and NOW the reward releases (Automation D)');

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '11111111-1111-4000-8000-00000000000a'),
  10000::bigint,
  'the referrer is credited Rs 100');

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = '11111111-1111-4000-8000-00000000000b'),
  5000::bigint,
  'and the friend Rs 50 - both rewards, not one');

select is(
  (select count(*)::int from public.wallet_lots
    where salon_id = '11111111-0000-4000-8000-000000000001'
      and kind = 'paid'),
  0,
  'as BONUS credit, never paid: paid credit is money a customer handed over');

select is(
  (select count(*)::int from public.wallet_lots
    where salon_id = '11111111-0000-4000-8000-000000000001'
      and kind = 'bonus' and expires_at is null),
  0,
  'carrying the salon''s own expiry, captured onto the lot at issue');

-- THE ONE THAT WOULD ACTUALLY HAPPEN: the sweep runs every minute.
select is(
  (app.release_due_referrals('11111111-0000-4000-8000-000000000001') ->> 'released'),
  '0',
  'a second sweep pays nothing - the status transition is the guard');

select is(
  (select sum(balance_paise)::bigint from public.wallet_accounts
    where salon_id = '11111111-0000-4000-8000-000000000001'),
  15000::bigint,
  'and the salon has paid out exactly once');

select is(
  (select count(*)::int from public.notifications
    where purpose = 'referral_rewarded'),
  2,
  'both of them are told - a reward nobody hears about retains nobody');

select * from finish();
