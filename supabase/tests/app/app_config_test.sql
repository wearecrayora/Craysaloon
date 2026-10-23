-- RELEASE GATE: the app run from the console (0119). Never skipped, never
-- deleted, never narrowed to pass.
--
--   * a salon reads its own config and announcements - nobody else's
--   * nobody writes them through the API; only audited console functions do
--   * only what a customer may see: an announcement outside its dates is not
--     readable at all
--   * a change customers should see (here: the menu) moves the pulse
--   * forcing an update is a super-admin's act, for every salon

select plan(14);

insert into auth.users (id) values
  ('a1a1a1a1-aaaa-4000-8000-00000000000a'),
  ('a1a1a1a1-aaaa-4000-8000-00000000000b'),
  ('a1a1a1a1-aaaa-4000-8000-00000000000f'),
  ('a1a1a1a1-aaaa-4000-8000-00000000000e');

insert into public.platform_admins (id, email, name, is_super, active) values
  ('a1a1a1a1-aaaa-4000-8000-00000000000f', 'cfg-super@crayora.test', 'Super', true, true),
  ('a1a1a1a1-aaaa-4000-8000-00000000000e', 'cfg-op@crayora.test', 'Operator', false, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           activated_by, activated_at)
values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'Config Salon A Ltd', 'Config A', 'CRAY-CFGAAA',
   'active', 'Asia/Kolkata', 'a1a1a1a1-aaaa-4000-8000-00000000000f', now()),
  ('a1a1a1a1-0000-4000-8000-000000000002', 'Config Salon B Ltd', 'Config B', 'CRAY-CFGBBB',
   'active', 'Asia/Kolkata', 'a1a1a1a1-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash) values
  ('a1a1a1a1-1111-4000-8000-00000000000a', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-aaaa-4000-8000-00000000000a', 'Asha', app.phone_hash('9799900051'));

select is((select count(*)::int from public.salon_app_config
            where salon_id in ('a1a1a1a1-0000-4000-8000-000000000001',
                               'a1a1a1a1-0000-4000-8000-000000000002')),
  2, 'every salon gets its config row the moment it exists');

select ok((app_admin.set_app_config('a1a1a1a1-aaaa-4000-8000-00000000000e',
  'a1a1a1a1-0000-4000-8000-000000000001',
  array['bookings', 'book'], array['services', 'quick'], '{"referrals": false}',
  'Bookings first for this salon') ->> 'ok')::boolean,
  'an operator rearranges a salon''s home, with a reason');

select throws_ok(
  $q$select app_admin.set_app_config('a1a1a1a1-aaaa-4000-8000-00000000000e',
       'a1a1a1a1-0000-4000-8000-000000000001', array['book', 'nonsense'], array['quick'], '{}', 'x')$q$,
  'P0001', NULL, 'a tile the app does not know is refused');

select throws_ok(
  $q$select app_admin.set_app_config('a1a1a1a1-aaaa-4000-8000-00000000000e',
       'a1a1a1a1-0000-4000-8000-000000000001', array['book'], array['quick'], '{"wallet_topup": "no"}', 'x')$q$,
  'P0001', NULL, 'a switch is true or false, nothing else');

select is((select count(*)::int from public.audit_log
            where action = 'app_config.changed' and salon_id = 'a1a1a1a1-0000-4000-8000-000000000001'),
  1, 'and the change is in the audit log');

select throws_ok(
  $q$select app_admin.set_app_versions('a1a1a1a1-aaaa-4000-8000-00000000000e', 5, 6, null, 'x')$q$,
  '42501', NULL, 'forcing an update is a super-admin''s act');

select is((app_admin.publish_announcement('a1a1a1a1-aaaa-4000-8000-00000000000e',
  array['a1a1a1a1-0000-4000-8000-000000000001'::uuid], 'Closed on Diwali', 'Back on the 2nd',
  null, null, 'event', now() - interval '1 hour', now() + interval '2 days') ->> 'salons')::int,
  1, 'an announcement is published to the salon chosen');

insert into public.salon_announcements (salon_id, title, starts_at, ends_at)
values ('a1a1a1a1-0000-4000-8000-000000000001', 'Old news', now() - interval '10 days',
        now() - interval '9 days');

-- Asha, a customer of salon A.
select set_config('request.jwt.claims',
  '{"sub":"a1a1a1a1-aaaa-4000-8000-00000000000a","role":"authenticated","app_role":"customer",'
  '"salon_id":"a1a1a1a1-0000-4000-8000-000000000001","customer_id":"a1a1a1a1-1111-4000-8000-00000000000a"}',
  true);
set local role authenticated;

select is((public.my_app_config() -> 'home_tiles'), '["bookings", "book"]'::jsonb,
  'the customer''s app reads its salon''s home, as set');
select is((public.my_app_config() -> 'switches' ->> 'referrals'), 'false',
  'and its switches');
select is((select count(*)::int from public.salon_app_config), 1,
  'and only its own salon''s config');
select is((select array_agg(title order by title) from public.salon_announcements),
  array['Closed on Diwali'],
  'only the live announcement is readable - not the expired one');

select throws_ok(
  $q$update public.salon_app_config set home_tiles = array['book']$q$,
  '42501', NULL, 'nobody writes the config through the API');
select throws_ok(
  $q$insert into public.salon_announcements (salon_id, title, ends_at)
     values ('a1a1a1a1-0000-4000-8000-000000000001', 'Fake offer', now() + interval '1 day')$q$,
  '42501', NULL, 'nor an announcement');

reset role;

-- The menu changes; the pulse moves, so the app re-reads it.
create temp table before_pulse as
  select version from public.salon_app_config where salon_id = 'a1a1a1a1-0000-4000-8000-000000000001';
insert into public.services (salon_id, name, price_paise, duration_minutes)
values ('a1a1a1a1-0000-4000-8000-000000000001', 'Keratin', 350000, 120);
select cmp_ok(
  (select version from public.salon_app_config where salon_id = 'a1a1a1a1-0000-4000-8000-000000000001'),
  '>', (select version from before_pulse),
  'a change to the menu moves the pulse the app watches');

select * from finish();
