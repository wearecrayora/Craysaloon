-- RELEASE GATE: messaging trial, grace, and block (0032, 0033)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- The sequence, as the owner specified it: an operator-granted TRIAL during
-- which Crayora pays for a salon's OTPs; then an optional GRACE period; then,
-- if the salon still has no Message Central account of its own, it is
-- BLOCKED - no new customers, no OTPs, no writes.
--
-- Every assertion here walks one salon through that sequence in order, so the
-- test reads as the lifecycle it protects.

select plan(22);

insert into auth.users (id) values ('77777777-aaaa-4000-8000-000000000001');
insert into public.platform_admins (id, email, name, is_super, active)
values ('77777777-aaaa-4000-8000-000000000001', 'grace@crayora.test', 'Grace Op', false, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values ('77777777-0000-4000-8000-00000000000a', 'Lifecycle Ltd', 'Lifecycle Salon',
        'CRAY-WWWXXX', 'active', '77777777-aaaa-4000-8000-000000000001', now());

insert into public.subscriptions (salon_id, plan, status, setup_fee_paise, setup_fee_status)
values ('77777777-0000-4000-8000-00000000000a', 'starter', 'active', 0, 'unpaid');

insert into public.salon_integrations (salon_id, provider, status)
values ('77777777-0000-4000-8000-00000000000a', 'message_central', 'missing');

-- ---------------------------------------------------------------------------
-- 0. Never sponsored: unchanged behaviour - Crayora's account as a fault
-- ---------------------------------------------------------------------------

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'fallback',
  'a salon never given a trial is NOT blocked - it falls back, alerted, as before'
);

-- ---------------------------------------------------------------------------
-- 1. Trial
-- ---------------------------------------------------------------------------

select app_admin.set_messaging_trial(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  14, 'Launch month');

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'trial',
  'during the trial, Crayora pays on purpose'
);

-- Grace granted WHILE the trial runs starts when the trial ends, so "7 days'
-- grace" means 7 days after the free period, not 7 days that overlap it.
select app_admin.set_messaging_grace(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  7, 'Setting up Message Central');

select is(
  (select (messaging_grace_ends_at - messaging_trial_ends_at) = interval '7 days'
     from public.subscriptions where salon_id = '77777777-0000-4000-8000-00000000000a'),
  true,
  'grace granted during a trial starts when the trial ends'
);

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'trial',
  'and does not shorten the trial it follows'
);

-- ---------------------------------------------------------------------------
-- 2. Trial over, grace running
-- ---------------------------------------------------------------------------

select app_admin.set_messaging_trial(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  0, 'Trial ended early for the test');
-- Re-grant grace from now, since its anchor (the trial end) just moved.
select app_admin.set_messaging_grace(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  7, 'Setting up Message Central');

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'grace',
  'after the trial, the grace period keeps OTPs flowing'
);

select is(
  public.resolve_join_code('CRAY-WWWXXX') ->> 'display_name',
  'Lifecycle Salon',
  'a salon in grace can still take new customers'
);

select public.start_join('CRAY-WWWXXX', '9833300001');

select is(
  public.otp_begin('9833300001', 'grace-caller') ->> 'messaging_state',
  'grace',
  'and its customers still get OTPs - recorded as grace, not as a fault'
);

select lives_ok(
  $$select public.otp_record_challenge(
      '9833300001', '77777777-0000-4000-8000-00000000000a', 'mc-grace-1', 'grace')$$,
  'a grace send is recorded under its own sender, distinct from a fault fallback'
);

select is(
  app.salon_writable('77777777-0000-4000-8000-00000000000a'),
  true,
  'and the salon can still operate'
);

-- ---------------------------------------------------------------------------
-- 3. Grace over, no own account: BLOCKED
-- ---------------------------------------------------------------------------

select app_admin.set_messaging_grace(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  0, 'Grace ended');

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'blocked',
  'trial over, grace over, no own account: the salon is blocked'
);

select is(
  public.resolve_join_code('CRAY-WWWXXX'),
  null,
  'no new customers - its code resolves to nothing, exactly like an unknown code'
);

select throws_ok(
  $$select public.start_join('CRAY-WWWXXX', '9833300002')$$,
  '22023', null,
  'start_join refuses, with the same error as a bad code'
);

-- The intent from step 2 is still live, so this customer HAS salon context.
-- Nobody is paying for this salon's OTPs any more, so none is sent.
select is(
  public.otp_begin('9833300001', 'blocked-caller') ->> 'reason',
  'salon_blocked',
  'no OTP is sent for a blocked salon - so no new logins'
);

select is(
  app.salon_writable('77777777-0000-4000-8000-00000000000a'),
  false,
  'no writes - every INSERT and UPDATE policy goes through salon_writable'
);

select is(
  (select status::text from public.salons where id = '77777777-0000-4000-8000-00000000000a'),
  'active',
  'the status is NOT changed to suspended - that would start the road to purging its data'
);

-- ---------------------------------------------------------------------------
-- What a block must never take away
-- ---------------------------------------------------------------------------

-- Reads: a customer already logged in can still see their wallet - money the
-- salon owes them (PRD 16A). No SELECT policy may gate on salon status.
select is(
  (select count(*)::int
     from pg_policy p join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and p.polcmd = 'r'
      and (pg_get_expr(p.polqual, p.polrelid) ~ 'salon_writable|salon_blocked')),
  0,
  'no read policy is gated on the block - customers can still see their own money'
);

-- Consent withdrawal: DPDP requires it to work at all times.
select is(
  (select pg_get_expr(p.polwithcheck, p.polrelid) ~ 'salon_writable|salon_blocked'
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname = 'consents' and p.polname = 'consents_customer_insert'),
  false,
  'a customer can still withdraw consent from a blocked salon (DPDP)'
);

-- ---------------------------------------------------------------------------
-- 4. The way out: the salon adds its own account, and the block lifts at once
-- ---------------------------------------------------------------------------

select app_admin.set_integration_secret(
  '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
  'message_central', 'not-a-real-mc-token-FOR-TEST', 'C-LIFECYCLE0001', null);

select is(
  app.salon_messaging_state('77777777-0000-4000-8000-00000000000a'),
  'own',
  'once the salon''s own account is entered, it is no longer blocked'
);

select is(
  public.resolve_join_code('CRAY-WWWXXX') ->> 'display_name',
  'Lifecycle Salon',
  'and new customers can join again - no operator action needed'
);

select is(
  app.salon_writable('77777777-0000-4000-8000-00000000000a'),
  true,
  'and it can operate again'
);

-- ---------------------------------------------------------------------------
-- Guard rails on the grant itself
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_admin.set_messaging_grace(
      '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
      30, '  ')$$,
  'P0001', null,
  'grace without a reason is refused - when it ends, a salon is blocked'
);

select throws_ok(
  $$select app_admin.set_messaging_grace(
      '77777777-aaaa-4000-8000-000000000001', '77777777-0000-4000-8000-00000000000a',
      3650, 'typo')$$,
  'P0001', null,
  'grace longer than 365 days is refused'
);

select * from finish();
