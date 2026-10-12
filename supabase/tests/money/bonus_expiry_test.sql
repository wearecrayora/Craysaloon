-- GATE: the owner sets bonus expiry (0097; RULES 5.3.3, 5.3.4)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- The owner - and only the owner - decides how long BONUS credit lasts; the
-- choice is captured onto each lot when it is issued, so changing it never
-- touches credit already given; and the console's rules save must not quietly
-- put it back to the default.

select plan(12);

insert into auth.users (id) values
  ('bbbbeeee-aaaa-4000-8000-00000000000f'),
  ('bbbbeeee-aaaa-4000-8000-00000000000c');

insert into public.platform_admins (id, email, name, is_super, active)
values ('bbbbeeee-aaaa-4000-8000-00000000000f', 'expiry@crayora.test', 'Expiry Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at, wallet_rule)
values ('bbbbeeee-0000-4000-8000-000000000001', 'Expiry Salon Ltd', 'Expiry Salon',
        'CRAY-EXPQ22', 'active', 'bbbbeeee-aaaa-4000-8000-00000000000f', now(),
        '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 10000}'::jsonb);

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values ('bbbbeeee-1111-4000-8000-00000000000c', 'bbbbeeee-0000-4000-8000-000000000001',
        'bbbbeeee-aaaa-4000-8000-00000000000c', 'Expiry cust', app.phone_hash('9744400011'));

create function pg_temp.as_role(p_role text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', 'bbbbeeee-aaaa-4000-8000-00000000000f', 'app_role', p_role,
                      'salon_id', 'bbbbeeee-0000-4000-8000-000000000001')::text, true);
$$;

-- ---------------------------------------------------------------------------
-- Only the owner
-- ---------------------------------------------------------------------------

set local role authenticated;

select pg_temp.as_role('manager');
select throws_ok($$select public.set_bonus_expiry(90)$$, '42501', null,
  'a manager cannot set bonus expiry - it is the owner''s (RULES 5.3.3)');

select pg_temp.as_role('staff');
select throws_ok($$select public.set_bonus_expiry(90)$$, '42501', null,
  'nor a stylist');

select pg_temp.as_role('customer');
select throws_ok($$select public.set_bonus_expiry(3650)$$, '42501', null,
  'nor, of course, a customer');

select pg_temp.as_role('owner');
select throws_ok($$select public.set_bonus_expiry(7)$$, '22023', null,
  'a week is refused: 0 (never) or 30 to 730 days');

select is((public.set_bonus_expiry(90) ->> 'ok'), 'true', 'the owner sets 90 days');

reset role;

select is(
  (select (wallet_rule ->> 'bonus_expiry_days')::int from public.salons
    where id = 'bbbbeeee-0000-4000-8000-000000000001'),
  90, 'and it is stored beside the salon''s bonus rule, which is otherwise untouched');

select is(
  (select actor_kind || ':' || (after_state ->> 'bonus_expiry_days') from public.audit_log
    where action = 'salon.bonus_expiry_set' and salon_id = 'bbbbeeee-0000-4000-8000-000000000001'),
  'owner:90', 'the change is audited as the owner''s act');

-- ---------------------------------------------------------------------------
-- Captured at issue, never read live (RULES 5.3.4)
-- ---------------------------------------------------------------------------

insert into public.payments (id, salon_id, customer_id, method, amount_paise, status, captured_at)
values ('bbbbeeee-7777-4000-8000-000000000001', 'bbbbeeee-0000-4000-8000-000000000001',
        'bbbbeeee-1111-4000-8000-00000000000c', 'upi', 50000, 'captured', now());
select app.wallet_credit_from_payment('bbbbeeee-7777-4000-8000-000000000001');

select ok(
  (select expires_at between now() + interval '89 days' and now() + interval '91 days'
     from public.wallet_lots
    where source_payment_id = 'bbbbeeee-7777-4000-8000-000000000001' and kind = 'bonus'),
  'a bonus issued now expires in the owner''s 90 days');

select is(
  (select expires_at from public.wallet_lots
    where source_payment_id = 'bbbbeeee-7777-4000-8000-000000000001' and kind = 'paid'),
  null, 'paid credit has no expiry - whatever the owner sets');

set local role authenticated;
select pg_temp.as_role('owner');
select public.set_bonus_expiry(30);
reset role;

select ok(
  (select expires_at > now() + interval '89 days' from public.wallet_lots
    where source_payment_id = 'bbbbeeee-7777-4000-8000-000000000001' and kind = 'bonus'),
  'shortening it later does not touch the bonus already given');

-- ---------------------------------------------------------------------------
-- The console's rules save keeps it
-- ---------------------------------------------------------------------------

select app_admin.set_salon_rules('bbbbeeee-aaaa-4000-8000-00000000000f',
  'bbbbeeee-0000-4000-8000-000000000001',
  '{"wallet_rule": {"topup_paise": 100000, "bonus_paise": 15000, "min_topup_paise": 20000}}'::jsonb);

select is(
  (select array[(wallet_rule ->> 'bonus_paise')::int, (wallet_rule ->> 'bonus_expiry_days')::int]
     from public.salons where id = 'bbbbeeee-0000-4000-8000-000000000001'),
  array[15000, 30],
  'a console rules save changes the bonus and KEEPS the owner''s expiry (it used to reset it)');

select throws_ok(
  $$select app_admin.set_salon_rules('bbbbeeee-aaaa-4000-8000-00000000000f',
      'bbbbeeee-0000-4000-8000-000000000001',
      '{"wallet_rule": {"topup_paise": 100000, "bonus_paise": 15000, "bonus_expiry_days": 999}}'::jsonb)$$,
  null, null, 'and the console still cannot set expiry itself');

select * from finish();
