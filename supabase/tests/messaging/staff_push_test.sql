-- RELEASE GATE: push only, push for the salon's own people, and messages that
-- read as sentences (0108).
--
-- Never skipped, never deleted, never narrowed to pass.
--
--   * an owner's device registers, and the owner hears about what a CUSTOMER
--     did - a booking, a cancellation, "I'll pay at the counter", a bill paid -
--     and nothing about what the salon did itself
--   * nobody without a device is queued for, and stylists are not told
--   * a staff message names the customer at SEND time; the stored params hold
--     an id, never a name, so an erased customer leaves none behind
--   * only the recipient acknowledges - a customer cannot ack the owner's push
--   * {{when}} and {{amount}} are filled; no message ever shows raw braces
--   * the wallet receipt is actually sent when a top-up is captured
--   * staff messages never escalate

select plan(22);

insert into auth.users (id) values
  ('7a7a7a7a-aaaa-4000-8000-00000000000a'),   -- Asha, a customer
  ('7a7a7a7a-aaaa-4000-8000-0000000000a1'),   -- the owner
  ('7a7a7a7a-aaaa-4000-8000-0000000000a2'),   -- a manager, no device
  ('7a7a7a7a-aaaa-4000-8000-0000000000a3'),   -- a stylist, with a device
  ('7a7a7a7a-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('7a7a7a7a-aaaa-4000-8000-00000000000f', 'push@crayora.test', 'Push Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values ('7a7a7a7a-0000-4000-8000-000000000001', 'Push Salon Ltd', 'Push Salon',
        'CRAY-PVSHST', 'active', 'Asia/Kolkata',
        '7a7a7a7a-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values ('7a7a7a7a-1111-4000-8000-00000000000a', '7a7a7a7a-0000-4000-8000-000000000001',
        '7a7a7a7a-aaaa-4000-8000-00000000000a', 'Asha Rao', app.phone_hash('9766600011'));

insert into public.users (id, salon_id, role, name, phone, phone_hash, active, auth_user_id)
values
  ('7a7a7a7a-2222-4000-8000-0000000000a1', '7a7a7a7a-0000-4000-8000-000000000001', 'owner',
   'Owner', '+919766600021', app.phone_hash('9766600021'), true, '7a7a7a7a-aaaa-4000-8000-0000000000a1'),
  ('7a7a7a7a-2222-4000-8000-0000000000a2', '7a7a7a7a-0000-4000-8000-000000000001', 'manager',
   'Manager', '+919766600022', app.phone_hash('9766600022'), true, '7a7a7a7a-aaaa-4000-8000-0000000000a2'),
  ('7a7a7a7a-2222-4000-8000-0000000000a3', '7a7a7a7a-0000-4000-8000-000000000001', 'staff',
   'Stylist', '+919766600023', app.phone_hash('9766600023'), true, '7a7a7a7a-aaaa-4000-8000-0000000000a3');

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

select is(app.format_rupees(12050000), '₹1,20,500', 'money in a message has Indian grouping');
select is(app.format_rupees(55050), '₹550.50', 'and paise only when there are any');

select is(
  strpos(app.render_template('7a7a7a7a-0000-4000-8000-000000000001', 'booking_confirmed', 'en', 'push',
         jsonb_build_object('starts_at', '2026-10-16T11:00:00Z')), '{{'),
  0,
  'a booking confirmation no longer says "confirmed for {{when}}"');

select matches(
  app.render_template('7a7a7a7a-0000-4000-8000-000000000001', 'booking_confirmed', 'en', 'push',
         jsonb_build_object('starts_at', '2026-10-16T11:00:00Z')),
  'Push Salon: .*16 Oct, 4:30 PM',
  'it says when, in the SALON''s time');

select is(
  app.render_template('7a7a7a7a-0000-4000-8000-000000000001', 'wallet_receipt', 'en', 'push',
         jsonb_build_object('amount_paise', 100000)),
  'Push Salon: ₹1,000 added to your wallet.',
  'the wallet receipt reads as a sentence');

select is(
  strpos(app.render_template('7a7a7a7a-0000-4000-8000-000000000001', 'staff_new_booking', 'en', 'push',
         '{}'::jsonb), '{{'),
  0,
  'a value that is missing is left out, never shown as braces');

-- ---------------------------------------------------------------------------
-- The owner's device
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"7a7a7a7a-aaaa-4000-8000-0000000000a1","role":"authenticated","app_role":"owner",'
  '"salon_id":"7a7a7a7a-0000-4000-8000-000000000001"}', true);
set local role authenticated;
select is((public.register_push_token('fcm-owner-push-test', 'android') ->> 'ok'), 'true',
  'an owner''s device registers for push - it was refused before 0108');
reset role;

select is(
  (select user_id from public.notification_tokens where token = 'fcm-owner-push-test'),
  '7a7a7a7a-2222-4000-8000-0000000000a1'::uuid,
  'and the token belongs to the owner, not to any customer');

-- The stylist has a device too - and is not who these messages are for.
insert into public.notification_tokens (salon_id, user_id, token, platform)
values ('7a7a7a7a-0000-4000-8000-000000000001', '7a7a7a7a-2222-4000-8000-0000000000a3',
        'fcm-stylist-push-test', 'android');

-- ---------------------------------------------------------------------------
-- What the owner hears
-- ---------------------------------------------------------------------------

-- The salon books someone itself: nothing to announce.
insert into public.bookings (id, salon_id, customer_id, starts_at, ends_at, status, total_paise, source)
values ('7a7a7a7a-4444-4000-8000-000000000001', '7a7a7a7a-0000-4000-8000-000000000001',
        '7a7a7a7a-1111-4000-8000-00000000000a', now() + interval '1 day',
        now() + interval '1 day 45 minutes', 'confirmed', 60000, 'walk_in');

select is((select count(*)::int from public.notifications
            where salon_id = '7a7a7a7a-0000-4000-8000-000000000001' and user_id is not null),
  0, 'a booking the salon made itself is not announced to the salon');

-- The customer books from the app.
select set_config('request.jwt.claims',
  '{"sub":"7a7a7a7a-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"7a7a7a7a-0000-4000-8000-000000000001","customer_id":"7a7a7a7a-1111-4000-8000-00000000000a"}',
  true);
insert into public.bookings (id, salon_id, customer_id, starts_at, ends_at, status, total_paise, source)
values ('7a7a7a7a-4444-4000-8000-000000000002', '7a7a7a7a-0000-4000-8000-000000000001',
        '7a7a7a7a-1111-4000-8000-00000000000a', now() + interval '2 days',
        now() + interval '2 days 45 minutes', 'confirmed', 60000, 'app');

select results_eq(
  $q$select user_id, purpose from public.notifications
      where salon_id = '7a7a7a7a-0000-4000-8000-000000000001' and user_id is not null$q$,
  $q$values ('7a7a7a7a-2222-4000-8000-0000000000a1'::uuid, 'staff_new_booking'::text)$q$,
  'a customer''s booking is announced to the owner - not to a manager with no device, not to a stylist');

select is(
  (select position('Asha' in params::text) from public.notifications where purpose = 'staff_new_booking'
     and user_id = '7a7a7a7a-2222-4000-8000-0000000000a1'),
  0,
  'the stored message holds the customer''s id, never their name');

select matches(
  (select app.render_template(salon_id, template_key, locale, 'push', params) from public.notifications
    where purpose = 'staff_new_booking' and user_id = '7a7a7a7a-2222-4000-8000-0000000000a1'),
  '^Push Salon: new booking - Asha Rao, ',
  'the name is read when the message is sent');

-- The customer cancels it.
update public.bookings set status = 'cancelled' where id = '7a7a7a7a-4444-4000-8000-000000000002';
select is((select count(*)::int from public.notifications
            where purpose = 'staff_booking_cancelled' and salon_id = '7a7a7a7a-0000-4000-8000-000000000001'),
  1, 'and so is the customer''s cancellation');

-- ...and asks to pay a bill at the counter.
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into public.visits (id, salon_id, booking_id, customer_id, final_amount_paise)
values ('7a7a7a7a-5555-4000-8000-000000000001', '7a7a7a7a-0000-4000-8000-000000000001',
        '7a7a7a7a-4444-4000-8000-000000000001', '7a7a7a7a-1111-4000-8000-00000000000a', 60000);
update public.visits set counter_payment_requested_at = now()
 where id = '7a7a7a7a-5555-4000-8000-000000000001';
select is((select count(*)::int from public.notifications
            where purpose = 'staff_counter_payment' and salon_id = '7a7a7a7a-0000-4000-8000-000000000001'),
  1, '"I''ll pay at the counter" tells the owner to expect them');

-- A bill paid online, and a top-up.
insert into public.payments (id, salon_id, customer_id, visit_id, method, amount_paise, status,
                             razorpay_order_id, idempotency_key)
values
  ('7a7a7a7a-6666-4000-8000-000000000001', '7a7a7a7a-0000-4000-8000-000000000001',
   '7a7a7a7a-1111-4000-8000-00000000000a', '7a7a7a7a-5555-4000-8000-000000000001',
   'upi', 60000, 'created', 'order_push_bill', 'push-bill'),
  ('7a7a7a7a-6666-4000-8000-000000000002', '7a7a7a7a-0000-4000-8000-000000000001',
   '7a7a7a7a-1111-4000-8000-00000000000a', null,
   'upi', 100000, 'created', 'order_push_topup', 'push-topup');
update public.payments set status = 'captured'
 where id in ('7a7a7a7a-6666-4000-8000-000000000001', '7a7a7a7a-6666-4000-8000-000000000002');

select is((select count(*)::int from public.notifications
            where purpose = 'staff_bill_paid' and salon_id = '7a7a7a7a-0000-4000-8000-000000000001'),
  1, 'a bill paid online is announced to the owner');

select results_eq(
  $q$select customer_id, purpose from public.notifications
      where salon_id = '7a7a7a7a-0000-4000-8000-000000000001' and customer_id is not null$q$,
  $q$values ('7a7a7a7a-1111-4000-8000-00000000000a'::uuid, 'wallet_receipt'::text)$q$,
  'and the wallet receipt - never sent before 0108 - goes to the customer who topped up');

-- ---------------------------------------------------------------------------
-- Delivery and the ack
-- ---------------------------------------------------------------------------

create temp table claimed as
  select * from app.claim_notification_batch('7a7a7a7a-0000-4000-8000-000000000001', 50);
grant select on claimed to public;

select is(
  (select count(*)::int from claimed where token = 'fcm-owner-push-test'),
  4,
  'the dispatcher finds the owner''s device for every staff message');

select is(
  (select count(*)::int from claimed where token = 'fcm-stylist-push-test'),
  0,
  'and never sends them to the stylist');

select is(app.escalation_window('staff_new_booking'), null::interval,
  'a staff message never escalates to a channel the salon pays for');

-- A customer cannot acknowledge the owner's push.
select set_config('request.jwt.claims',
  '{"sub":"7a7a7a7a-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"7a7a7a7a-0000-4000-8000-000000000001","customer_id":"7a7a7a7a-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;
select is(
  (public.ack_notification((select delivery_id from claimed where token = 'fcm-owner-push-test' limit 1))
     ->> 'reason'),
  'not_found',
  'a customer cannot acknowledge the owner''s push');
reset role;

-- The owner can.
select set_config('request.jwt.claims',
  '{"sub":"7a7a7a7a-aaaa-4000-8000-0000000000a1","role":"authenticated","app_role":"owner",'
  '"salon_id":"7a7a7a7a-0000-4000-8000-000000000001"}', true);
set local role authenticated;
select is(
  (public.ack_notification((select delivery_id from claimed where token = 'fcm-owner-push-test' limit 1))
     ->> 'ok'),
  'true',
  'the owner acknowledges their own');
reset role;

-- And with the paid fallback off, a customer with no device is never queued
-- for SMS: the notification simply has nowhere to go.
select is(app.next_channel('7a7a7a7a-0000-4000-8000-000000000001', 'transactional', '{push}'),
  null::public.message_channel,
  'push is the only channel while the paid fallback is off (0108)');

select * from finish();
