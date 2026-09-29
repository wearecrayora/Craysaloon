-- RELEASE GATE: offboarding a salon, and support mode (M12, 0089)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PHASES M12 done-when, asserted against the functions that run:
--   * purge splits personal from financial - identity, tokens, messages and
--     credentials go; every payment and ledger row stays, still balancing
--   * anonymising preserves ledger integrity (the balance still equals the sum
--     of the ledger; the ledger is still append-only) AND binding exclusivity
--     (the phone is released, and binds to exactly one salon afterwards)
--   * support mode is time-boxed and reason-required, masks the phone, and
--     un-masking is a separate, logged act
-- plus the preconditions a purge must never skip: purge due, an export
-- offered, customer credit settled, a super-admin, the name typed back.

select plan(32);

insert into auth.users (id) values
  ('55555555-aaaa-4000-8000-00000000000a'),   -- operator (not super)
  ('55555555-aaaa-4000-8000-00000000000b'),   -- super-admin
  ('55555555-aaaa-4000-8000-00000000000c'),   -- customer of the closing salon
  ('55555555-aaaa-4000-8000-00000000000d'),   -- customer of the neighbour
  ('55555555-aaaa-4000-8000-00000000000f');   -- owner of the closing salon

insert into public.platform_admins (id, email, name, is_super, active)
values ('55555555-aaaa-4000-8000-00000000000a', 'op@crayora.test', 'Offboard Op', false, true),
       ('55555555-aaaa-4000-8000-00000000000b', 'super@crayora.test', 'Offboard Super', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, timezone,
                           wallet_rule, activated_by, activated_at, grievance_name, grievance_email)
values
  ('55555555-0000-4000-8000-000000000001', 'Closing Salon Ltd', 'Closing Salon', 'CRAY-CXSNGA',
   'active', 'Asia/Kolkata',
   '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 50000}'::jsonb,
   '55555555-aaaa-4000-8000-00000000000b', now(), 'Owner', 'o@closing.test'),
  ('55555555-0000-4000-8000-000000000002', 'Neighbour Salon Ltd', 'Neighbour Salon', 'CRAY-NBRSGA',
   'active', 'Asia/Kolkata',
   '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 50000}'::jsonb,
   '55555555-aaaa-4000-8000-00000000000b', now(), 'Owner', 'o@neighbour.test');

insert into public.subscriptions (salon_id, plan, renews_at)
values ('55555555-0000-4000-8000-000000000001', 'starter', now() + interval '20 days'),
       ('55555555-0000-4000-8000-000000000002', 'starter', now() + interval '20 days');

insert into public.users (id, salon_id, name, role, phone, phone_hash, auth_user_id, active)
values ('55555555-2222-4000-8000-00000000000f', '55555555-0000-4000-8000-000000000001',
        'Closing Owner', 'owner', '9755500029', app.phone_hash('9755500029'),
        '55555555-aaaa-4000-8000-00000000000f', true);

insert into public.staff (salon_id, name, active)
values ('55555555-0000-4000-8000-000000000001', 'Ravi', true);

-- A completed Message Central verification, as otp-verify would have it.
create or replace function pg_temp.verified(p_phone text, p_salon uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := public.otp_record_challenge(p_phone, p_salon, 'mc-' || p_phone, 'salon');
  perform public.otp_complete(v);
  return v;
end $$;

-- Asha joins the closing salon; Bina joins the neighbour.
select public.start_join('CRAY-CXSNGA', '9755500021');
create temp table l1 as select pg_temp.verified('9755500021', '55555555-0000-4000-8000-000000000001') as id;
select public.otp_finish_login((select id from l1), '55555555-aaaa-4000-8000-00000000000c', '{}'::jsonb);
select public.start_join('CRAY-NBRSGA', '9755500022');
create temp table l2 as select pg_temp.verified('9755500022', '55555555-0000-4000-8000-000000000002') as id;
select public.otp_finish_login((select id from l2), '55555555-aaaa-4000-8000-00000000000d', '{}'::jsonb);

create temp table people as
  select c.id, c.salon_id, c.auth_user_id from public.customers c
   where c.salon_id in ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000002');
grant select on people to public;

update public.customers set name = 'Asha' where auth_user_id = '55555555-aaaa-4000-8000-00000000000c';
update public.customers set name = 'Bina' where auth_user_id = '55555555-aaaa-4000-8000-00000000000d';

-- Real money, through the real path: a captured top-up at each salon.
insert into public.payments (id, salon_id, customer_id, method, amount_paise, status,
                             razorpay_order_id, idempotency_key)
select case when salon_id = '55555555-0000-4000-8000-000000000001'
            then '55555555-9999-4000-8000-000000000001'::uuid
            else '55555555-9999-4000-8000-000000000002'::uuid end,
       salon_id, id, 'upi', 100000, 'created', 'order_' || left(id::text, 8), 'offboard-' || id
  from people;
select app.record_payment_captured('55555555-9999-4000-8000-000000000001', 'pay_off_1', 100000);
select app.record_payment_captured('55555555-9999-4000-8000-000000000002', 'pay_off_2', 100000);

-- Operational personal data that must go.
insert into public.notification_tokens (salon_id, customer_id, token, platform)
select salon_id, id, 'fcm-offboard-' || left(id::text, 8), 'android' from people;

insert into public.data_rights_requests (salon_id, customer_id, kind)
select salon_id, id, 'access' from people
 where salon_id = '55555555-0000-4000-8000-000000000001';

-- A credential the salon's account holds.
insert into public.salon_integrations (salon_id, provider, vault_secret_id, last4)
values ('55555555-0000-4000-8000-000000000001', 'razorpay',
        vault.create_secret('rzp-secret-offboard-test'), '4821');

create temp table before as
  select (select count(*) from public.wallet_transactions
           where salon_id = '55555555-0000-4000-8000-000000000001') as ledger_rows,
         (select count(*) from public.payments
           where salon_id = '55555555-0000-4000-8000-000000000001') as payment_rows,
         (select vault_secret_id from public.salon_integrations
           where salon_id = '55555555-0000-4000-8000-000000000001') as secret_id,
         (select balance_paise from public.wallet_accounts w
            join people p on p.id = w.customer_id
           where p.salon_id = '55555555-0000-4000-8000-000000000002') as neighbour_balance;
grant select on before to public;

-- ---------------------------------------------------------------------------
-- The preconditions, each refused with a sentence
-- ---------------------------------------------------------------------------

select throws_ok(
  $q$select app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000a',
       '55555555-0000-4000-8000-000000000001', 'closed', 'Closing Salon')$q$,
  '42501', null,
  'only a Crayora super-admin can purge');

select throws_like(
  $q$select app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'closed', 'Closing Salon')$q$,
  '%purge is not due%',
  'a paid-up salon cannot be purged - purge comes 90 days after suspension');

update public.subscriptions set renews_at = now() - interval '98 days'
 where salon_id = '55555555-0000-4000-8000-000000000001';

select throws_like(
  $q$select app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'closed', 'Closing Salon')$q$,
  '%offer the owner an export%',
  'not before the owner has been offered their data');

select app_admin.record_export_offered('55555555-aaaa-4000-8000-00000000000b',
  '55555555-0000-4000-8000-000000000001', 'Emailed the export to the owner on 2 Jan');

select throws_like(
  $q$select app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'closed', 'Closing Salon')$q$,
  '%still hold%credit%',
  'not while customers hold credit the salon has not settled (PRD 16A.2)');

select is(
  (app_admin.record_credit_settlement('55555555-aaaa-4000-8000-00000000000b',
     '55555555-0000-4000-8000-000000000001',
     'Refunded in cash at the counter, list signed by the owner') ->> 'outstanding_paise'),
  '110000',
  'the settlement is recorded against the credit the ledger shows - Rs 1,000 paid + Rs 100 bonus');

select throws_like(
  $q$select app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'closed', 'closing salon')$q$,
  '%type the salon''s display name exactly%',
  'the display name must be typed back exactly');

-- ---------------------------------------------------------------------------
-- The purge
-- ---------------------------------------------------------------------------

select is(
  (app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
     '55555555-0000-4000-8000-000000000001', 'Owner closed the business',
     'Closing Salon') ->> 'customers_anonymised'),
  '1',
  'the purge runs, and anonymises every customer');

-- Personal: gone.
select is(
  (select count(*)::int from public.customers
    where salon_id = '55555555-0000-4000-8000-000000000001'
      and (name is not null or phone is not null or auth_user_id is not null)),
  0,
  'no name, number or login link survives');

select is(
  (select count(*)::int from public.notification_tokens
    where salon_id = '55555555-0000-4000-8000-000000000001'),
  0,
  'device tokens are gone');

select is(
  (select count(*)::int from public.users
    where salon_id = '55555555-0000-4000-8000-000000000001'
      and (active or auth_user_id is not null or name <> 'Former staff' or phone <> '')),
  0,
  'every staff account is anonymised and closed - nobody can log in to the archive');

select is(
  (select count(*)::int from public.salon_integrations
    where salon_id = '55555555-0000-4000-8000-000000000001'),
  0,
  'the salon''s credentials are gone');

select is(
  (select count(*)::int from vault.secrets where id = (select secret_id from before)),
  0,
  'and so is the secret itself - not just the row that pointed at it');

-- Financial: every row stays, and still balances.
select is(
  (select count(*) from public.wallet_transactions
    where salon_id = '55555555-0000-4000-8000-000000000001'),
  (select ledger_rows from before),
  'every ledger row stays (RULES 11.8) - the books survive the people');

select is(
  (select count(*) from public.payments
    where salon_id = '55555555-0000-4000-8000-000000000001'),
  (select payment_rows from before),
  'every payment stays');

select is(
  (select w.balance_paise from public.wallet_accounts w
     join people p on p.id = w.customer_id
    where p.salon_id = '55555555-0000-4000-8000-000000000001'),
  (select coalesce(sum(t.amount_paise), 0)::bigint from public.wallet_transactions t
     join people p on p.id = t.customer_id
    where p.salon_id = '55555555-0000-4000-8000-000000000001'),
  'LEDGER INTEGRITY: the balance still equals the sum of the ledger');

select throws_ok(
  $q$delete from public.wallet_transactions
      where salon_id = '55555555-0000-4000-8000-000000000001'$q$,
  null, null,
  'and the ledger is still append-only - the purge did not switch the protection off');

-- Binding: released, and exclusive afterwards.
select is(
  (select count(*)::int from public.customer_identities
    where salon_id = '55555555-0000-4000-8000-000000000001'),
  0,
  'every binding to the closed salon is released');

select is(
  (select count(*)::int from public.binding_events
    where from_salon_id = '55555555-0000-4000-8000-000000000001' and kind = 'unbind'),
  1,
  'and each release is recorded like any other unbind');

select public.start_join('CRAY-NBRSGA', '9755500021');
create temp table l3 as select pg_temp.verified('9755500021', '55555555-0000-4000-8000-000000000002') as id;

select is(
  public.otp_finish_login((select id from l3), '55555555-aaaa-4000-8000-00000000000c',
                          '{}'::jsonb) ->> 'outcome',
  'bound',
  'BINDING EXCLUSIVITY: the released phone can join another salon');

select is(
  (select count(*)::int from public.customer_identities
    where phone_hash = app.phone_hash('9755500021')),
  1,
  'and holds exactly ONE binding afterwards');

-- The neighbour: untouched.
select is(
  (select name from public.customers where auth_user_id = '55555555-aaaa-4000-8000-00000000000d'),
  'Bina',
  'the neighbouring salon''s customer is untouched');

select is(
  (select w.balance_paise from public.wallet_accounts w
     join people p on p.id = w.customer_id
    where p.salon_id = '55555555-0000-4000-8000-000000000002'),
  (select neighbour_balance from before),
  'and so is their money');

-- The rest of the bookkeeping.
select is(
  (select count(*)::int from public.data_rights_requests
    where salon_id = '55555555-0000-4000-8000-000000000001' and status in ('open', 'in_progress')),
  0,
  'open data-rights requests are answered with an outcome, not dropped');

select throws_like(
  $q$select app_admin.set_salon_status('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'grace', 'bring it back')$q$,
  '%purged%',
  'a purged salon''s status is final - it can never be brought back');

select throws_like(
  $q$select app_admin.reactivate_salon('55555555-aaaa-4000-8000-00000000000b',
       '55555555-0000-4000-8000-000000000001', 'changed their mind')$q$,
  '%purged%',
  'nor reactivated');

select is(
  (app_admin.purge_salon('55555555-aaaa-4000-8000-00000000000b',
     '55555555-0000-4000-8000-000000000001', 'again', 'Closing Salon') ->> 'already'),
  'true',
  'purging twice is a no-op, not an error');

-- ---------------------------------------------------------------------------
-- Support mode
-- ---------------------------------------------------------------------------

select throws_like(
  $q$select app_admin.support_customers('55555555-aaaa-4000-8000-00000000000a',
       '55555555-0000-4000-8000-000000000002')$q$,
  '%start a support session%',
  'customer data is not visible without a support session');

select throws_like(
  $q$select app_admin.start_support_session('55555555-aaaa-4000-8000-00000000000a',
       '55555555-0000-4000-8000-000000000002', '  ')$q$,
  '%needs a reason%',
  'a session needs a reason');

select throws_like(
  $q$select app_admin.start_support_session('55555555-aaaa-4000-8000-00000000000a',
       '55555555-0000-4000-8000-000000000002', 'Ticket 41', 180)$q$,
  '%5 to 120 minutes%',
  'and a time box - never an open-ended session');

create temp table sess as
  select app_admin.start_support_session('55555555-aaaa-4000-8000-00000000000a',
           '55555555-0000-4000-8000-000000000002', 'Ticket 41: wallet question') as r;
grant select on sess to public;

create temp table seen as
  select app_admin.support_customers('55555555-aaaa-4000-8000-00000000000a',
           '55555555-0000-4000-8000-000000000002') -> 0 as c;
grant select on seen to public;

select ok(
  (select c ->> 'phone_last4' = '0022' and not (c ? 'phone') from seen),
  'inside a session the phone is MASKED to its last four digits');

select is(
  app_admin.support_unmask_phone('55555555-aaaa-4000-8000-00000000000a',
    (select (c ->> 'customer_id')::uuid from seen), 'Customer asked us to call back'),
  '9755500022',
  'un-masking is its own act, with its own reason');

-- Time runs out.
update public.support_sessions
   set started_at = now() - interval '2 hours', ends_at = now() - interval '1 hour'
 where id = (select (r ->> 'session_id')::uuid from sess);

select throws_like(
  $q$select app_admin.support_customers('55555555-aaaa-4000-8000-00000000000a',
       '55555555-0000-4000-8000-000000000002')$q$,
  '%start a support session%',
  'when the time box ends, so does the access');

select * from finish();
