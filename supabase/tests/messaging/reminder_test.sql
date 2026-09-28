-- RELEASE GATE: reminders, the ladder, and the ack (M8)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- Three claims, each of which costs a salon money or a customer's trust when it
-- stops being true:
--
--   * **exactly one reminder per cycle, enforced by an INDEX** - a replayed
--     offline mark-complete, a retried job and a duplicate event are all no-ops
--   * **escalation is gated on an ACK**, never on FCM's response. FCM reports
--     "accepted by Google", and a ladder that trusts it either never escalates
--     or always does - the second spends the salon's money on every message
--   * **a salon with no WhatsApp templates and no RCS agent still works
--     completely** - the rungs it cannot use are skipped, never errored on

select plan(26);

insert into auth.users (id) values
  ('eeeeeeee-aaaa-4000-8000-00000000000a'),
  ('eeeeeeee-aaaa-4000-8000-00000000000b'),
  ('eeeeeeee-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('eeeeeeee-aaaa-4000-8000-00000000000f', 'm8@crayora.test', 'M8 Op', true, true);

-- A salon with NOTHING configured: no WhatsApp templates, no RCS agent. The
-- hardest case for the ladder, and the normal case on day one.
insert into public.salons (id, legal_name, display_name, join_code, status,
                           default_reminder_cycle_days, activated_by, activated_at)
values ('eeeeeeee-0000-4000-8000-000000000001', 'Bare Salon Ltd', 'Bare Salon',
        'CRAY-BARESA', 'active', 30,
        'eeeeeeee-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash, language)
values
  ('eeeeeeee-1111-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-000000000001',
   'eeeeeeee-aaaa-4000-8000-00000000000a', 'Asha', app.phone_hash('9788800011'), 'hi'),
  ('eeeeeeee-1111-4000-8000-00000000000d', 'eeeeeeee-0000-4000-8000-000000000001',
   'eeeeeeee-aaaa-4000-8000-00000000000b', 'Vikram', app.phone_hash('9788800012'), 'en');

-- Asha took service messages and refused marketing. Vikram took both.
insert into public.consents (salon_id, customer_id, purpose, granted, source)
values
  ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-1111-4000-8000-00000000000c',
   'service_communication', true, 'binding'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-1111-4000-8000-00000000000c',
   'promotional', false, 'binding'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-1111-4000-8000-00000000000d',
   'service_communication', true, 'binding'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-1111-4000-8000-00000000000d',
   'promotional', true, 'binding');

-- Provisioning creates one row per provider (0017). A salon inserted by hand
-- has none, so the ladder finds nothing to read - which is itself the "salon
-- with nothing configured" case asserted below, before these are switched on.
insert into public.salon_integrations (salon_id, provider, status)
values
  ('eeeeeeee-0000-4000-8000-000000000001', 'razorpay', 'missing'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'message_central', 'missing'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'whatsapp', 'missing'),
  ('eeeeeeee-0000-4000-8000-000000000001', 'rcs', 'missing');

insert into public.services (id, salon_id, name, price_paise, duration_minutes)
values ('eeeeeeee-2222-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'Haircut', 45000, 30);

insert into public.staff (id, salon_id, name, active)
values ('eeeeeeee-3333-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'Suresh', true);

-- ---------------------------------------------------------------------------
-- Automation A: one visit, one reminder
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('eeeeeeee-4444-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-1111-4000-8000-00000000000c', 'eeeeeeee-3333-4000-8000-000000000001',
        now() - interval '40 days', now() - interval '40 days' + interval '30 minutes',
        'completed');

insert into public.booking_items
  (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
values ('eeeeeeee-4444-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'service', 'eeeeeeee-2222-4000-8000-000000000001', 'Haircut', 45000, 30);

insert into public.visits (id, salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values ('eeeeeeee-5555-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-4444-4000-8000-000000000001', 'eeeeeeee-1111-4000-8000-00000000000c',
        'eeeeeeee-3333-4000-8000-000000000001', 45000, now() - interval '40 days');

create temp table a1 as
  select app.on_visit_completed('eeeeeeee-5555-4000-8000-000000000001') as r;

select isnt((select r ->> 'reminder_id' from a1), null,
  'a completed visit schedules a reminder');

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c' and status = 'scheduled'),
  1,
  'exactly one');

select is(
  (select round(extract(epoch from (scheduled_for - (now() - interval '40 days')))
                / 86400.0)::int
     from public.reminders where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c'),
  30,
  'due one salon cycle after the visit - there is no history to learn from yet');

select is((select r ->> 'median_days' from a1), null,
  'and no learned interval is claimed from a single visit');

select is(
  (select last_visit_at is not null from public.customers
    where id = 'eeeeeeee-1111-4000-8000-00000000000c'),
  true,
  'the customer''s last visit is recorded');

select is(
  (select completed from public.daily_salon_metrics
    where salon_id = 'eeeeeeee-0000-4000-8000-000000000001'),
  1,
  'and today''s numbers move with it');

-- THE IDEMPOTENCY CLAIM. The offline outbox replays; the job retries; the event
-- is delivered twice. All three arrive here as the same visit.
select is(
  (app.on_visit_completed('eeeeeeee-5555-4000-8000-000000000001') ->> 'reminder_id'),
  null,
  'replaying the SAME visit schedules nothing new - the index decides, not the caller');

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c'
      and status in ('scheduled', 'sent', 'delivered')),
  1,
  'so a replayed offline mark-complete still leaves exactly one reminder');

-- ---------------------------------------------------------------------------
-- A second visit supersedes rather than duplicates
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('eeeeeeee-4444-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-1111-4000-8000-00000000000c', 'eeeeeeee-3333-4000-8000-000000000001',
        now() - interval '20 days', now() - interval '20 days' + interval '30 minutes',
        'completed');

insert into public.booking_items
  (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
values ('eeeeeeee-4444-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000001',
        'service', 'eeeeeeee-2222-4000-8000-000000000001', 'Haircut', 45000, 30);

insert into public.visits (id, salon_id, booking_id, customer_id, staff_id,
                           final_amount_paise, completed_at)
values ('eeeeeeee-5555-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-4444-4000-8000-000000000002', 'eeeeeeee-1111-4000-8000-00000000000c',
        'eeeeeeee-3333-4000-8000-000000000001', 45000, now() - interval '20 days');

create temp table a2 as
  select app.on_visit_completed('eeeeeeee-5555-4000-8000-000000000002') as r;

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c'
      and status in ('scheduled', 'sent', 'delivered')),
  1,
  'a SECOND visit replaces the schedule rather than adding to it');

select is((select r ->> 'median_days' from a2), '20',
  'and two visits make an interval worth learning: the median of their own gaps');

select is(
  (select median_days::int from public.customer_service_intervals
    where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c'),
  20,
  'recorded where the next reminder can read it (ARCHITECTURE 6.7)');

-- ---------------------------------------------------------------------------
-- Automation C: booking confirmed
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status)
values ('eeeeeeee-4444-4000-8000-000000000003', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-1111-4000-8000-00000000000c', 'eeeeeeee-3333-4000-8000-000000000001',
        now() + interval '2 days', now() + interval '2 days' + interval '30 minutes',
        'confirmed');

insert into public.booking_items
  (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
values ('eeeeeeee-4444-4000-8000-000000000003', 'eeeeeeee-0000-4000-8000-000000000001',
        'service', 'eeeeeeee-2222-4000-8000-000000000001', 'Haircut', 45000, 30);

create temp table c1 as
  select app.on_booking_confirmed('eeeeeeee-4444-4000-8000-000000000003') as r;

select is((select r ->> 'reminders_converted' from c1), '1',
  'booking stops the reminder that would have nagged someone who already booked');

select is(
  (select count(*)::int from public.reminders
    where customer_id = 'eeeeeeee-1111-4000-8000-00000000000c' and status = 'converted'),
  2,
  'and `converted` is what makes reminder conversion measurable later');

select is(
  (select locale from public.notifications
    where id = (select (r ->> 'notification_id')::uuid from c1)),
  'hi',
  'the confirmation is written in the customer''s OWN language, not the salon''s');

select is(
  (select status::text from public.notifications
    where id = (select (r ->> 'notification_id')::uuid from c1)),
  'pending',
  'and it is queued, because a booking confirmation is the service, not marketing');

-- ---------------------------------------------------------------------------
-- Consent decides before a paisa is spent
-- ---------------------------------------------------------------------------

-- Captured into a table FIRST. app.notify is volatile, and a volatile function
-- in a WHERE clause runs once per row scanned - creating a notification each
-- time. This codebase has made that mistake once already, in 0048's gate.
create temp table refused as
  select app.notify('eeeeeeee-0000-4000-8000-000000000001',
                    'eeeeeeee-1111-4000-8000-00000000000c',
                    'service_due', 'marketing', 'service_due') as id;

create temp table agreed as
  select app.notify('eeeeeeee-0000-4000-8000-000000000001',
                    'eeeeeeee-1111-4000-8000-00000000000d',
                    'service_due', 'marketing', 'service_due') as id;

select is(
  (select n.status::text from public.notifications n
     join refused r on r.id = n.id),
  'suppressed',
  'a customer who refused marketing is not sent marketing');

select is(
  (select n.status::text from public.notifications n
     join agreed a on a.id = n.id),
  'pending',
  'and one who agreed to it is');

select is(
  (select count(*)::int from public.notifications where status = 'suppressed'),
  1,
  'the suppression is WRITTEN DOWN - "we did not send this, and why" answers a complaint');

-- ---------------------------------------------------------------------------
-- The ladder, on a salon that has configured nothing
-- ---------------------------------------------------------------------------

select is(
  app.next_channel('eeeeeeee-0000-4000-8000-000000000001', 'transactional', '{push}')::text,
  'sms',
  'with no approved templates and no RCS agent, transactional falls to SMS - and WORKS');

select is(
  app.next_channel('eeeeeeee-0000-4000-8000-000000000001', 'marketing', '{push}')::text,
  'sms',
  'marketing goes to SMS, never to WhatsApp Marketing at six times the price');

select is(
  app.next_channel('eeeeeeee-0000-4000-8000-000000000001', 'marketing', '{push,sms}')::text,
  null,
  'and when the owner has not opted in, the ladder ends rather than spending their money');

update public.salon_integrations set whatsapp_template_status = 'approved'
 where salon_id = 'eeeeeeee-0000-4000-8000-000000000001' and provider = 'whatsapp';

select is(
  app.next_channel('eeeeeeee-0000-4000-8000-000000000001', 'transactional', '{push}')::text,
  'whatsapp',
  'once templates are approved, transactional prefers WhatsApp Utility - CHEAPER than SMS');

update public.salon_integrations set rcs_agent_status = 'verified'
 where salon_id = 'eeeeeeee-0000-4000-8000-000000000001' and provider = 'rcs';

select is(
  app.next_channel('eeeeeeee-0000-4000-8000-000000000001', 'transactional', '{push}')::text,
  'rcs',
  'and a verified RCS agent sits above it: cheaper still, and branded in the Messages app');

-- ---------------------------------------------------------------------------
-- Automation K: the ack is what gates the spend
-- ---------------------------------------------------------------------------

insert into public.notification_deliveries
  (id, salon_id, notification_id, channel, provider_status, sent_at)
select 'eeeeeeee-6666-4000-8000-000000000001',
       'eeeeeeee-0000-4000-8000-000000000001', (r ->> 'notification_id')::uuid,
       'push', 'sent',
       -- Sent seven minutes ago. A booking confirmation waits five.
       now() - interval '7 minutes'
  from c1;

select is(
  (app.escalate_due_deliveries('eeeeeeee-0000-4000-8000-000000000001') ->> 'escalated'),
  '1',
  'a push unacked past its window escalates - FCM having accepted it proves nothing');

select is(
  (select count(*)::int from public.notification_deliveries
    where notification_id = (select (r ->> 'notification_id')::uuid from c1)
      and channel = 'rcs' and provider_status = 'queued'),
  1,
  'onto the next rung the salon can actually use, queued for the dispatcher');

-- Now the ack arrives for a second, identical case.
insert into public.notifications (id, salon_id, customer_id, purpose, category, locale, template_key)
values ('eeeeeeee-7777-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-1111-4000-8000-00000000000c', 'booking_confirmed', 'transactional',
        'hi', 'booking_confirmed');

insert into public.notification_deliveries
  (id, salon_id, notification_id, channel, provider_status, sent_at, acked_at)
values ('eeeeeeee-6666-4000-8000-000000000002', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-7777-4000-8000-000000000001', 'push', 'sent',
        now() - interval '7 minutes', now() - interval '6 minutes');

select is(
  (app.escalate_due_deliveries('eeeeeeee-0000-4000-8000-000000000001') ->> 'escalated'),
  '0',
  'an ACKED push escalates nothing - which is the whole saving (ARCH 12.4)');

-- The ack belongs to the recipient, and to nobody else.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-aaaa-4000-8000-00000000000b",'
  '"app_role":"customer",'
  '"salon_id":"eeeeeeee-0000-4000-8000-000000000001"}',
  true
);

select is(
  (public.ack_notification('eeeeeeee-6666-4000-8000-000000000001') ->> 'reason'),
  'not_found',
  'another customer cannot acknowledge a message that was not theirs');

reset role;

select * from finish();
