-- RELEASE GATE: taking the money (M7)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- The rules a payment path has to keep, all of which cost real rupees when they
-- break:
--   * the AMOUNT is decided by the server, not by whatever the client sent
--   * credit follows a CAPTURED payment, never a client claiming one
--   * the amount is RE-VERIFIED at capture against the payment we created
--   * a redelivered webhook credits nothing twice
--   * the salon comes from the URL token, never from the body
--   * there is still exactly ONE function that reads a decrypted credential

select plan(24);

-- ---------------------------------------------------------------------------
-- The credential door
-- ---------------------------------------------------------------------------

-- Two functions in the whole schema may read Vault, and they read different
-- things for different reasons:
--   phone_hash            the phone-number PEPPER, which every hash needs (0023)
--   salon_provider_secret a SALON's provider credential, at the moment of use
-- A third name appearing here means somebody opened a second door to either.
select set_eq(
  $q$with fns as materialized (
      select p.oid, p.proname
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'app', 'app_admin') and p.prokind = 'f'
    )
    select proname::text from fns
     where pg_get_functiondef(oid) ~* 'vault[.]decrypted_secrets'$q$,
  $q$values ('phone_hash'), ('salon_provider_secret')$q$,
  'only the pepper reader and the ONE credential door read Vault (ARCH 8.1)'
);

select is(
  (select count(*)::int from pg_proc p
    where p.oid in ('public.salon_provider_secret(uuid,public.integration_provider)'::regprocedure,
                    'public.salon_by_webhook_token(text)'::regprocedure,
                    'app.record_payment_captured(uuid,text,bigint)'::regprocedure,
                    'app.webhook_seen(text,text,uuid,jsonb)'::regprocedure)
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0,
  'no device can read a credential, resolve a webhook token, or capture a payment'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('aaaaaaab-aaaa-4000-8000-00000000000f'),
  ('aaaaaaab-aaaa-4000-8000-00000000000c');

insert into public.platform_admins (id, email, name, is_super, active)
values ('aaaaaaab-aaaa-4000-8000-00000000000f', 'pay@crayora.test', 'Pay Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, webhook_token,
                           wallet_rule, activated_by, activated_at)
values ('aaaaaaab-0000-4000-8000-000000000001', 'Pay Salon Ltd', 'Pay Salon',
        'CRAY-PAYQQQ', 'active', 'whk_pay_salon_token',
        -- THE SHAPE THE CONSOLE WRITES (PRD "Rs 500 -> +Rs 50"), not a shape
        -- invented to suit the function under test. A fixture that agrees with
        -- the code proves only that the code agrees with itself - which is
        -- exactly how the percent/slab mismatch survived until 0058.
        '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 50000}'::jsonb,
        'aaaaaaab-aaaa-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash)
values ('aaaaaaab-1111-4000-8000-00000000000c', 'aaaaaaab-0000-4000-8000-000000000001',
        'aaaaaaab-aaaa-4000-8000-00000000000c', 'Nita', '9866600011',
        app.phone_hash('9866600011'));

-- The webhook token resolves the salon; anything else resolves nothing.
select is(
  public.salon_by_webhook_token('whk_pay_salon_token'),
  'aaaaaaab-0000-4000-8000-000000000001'::uuid,
  'the path token names the salon - the body never gets to (ARCH 8.3)'
);

select is(
  public.salon_by_webhook_token('whk_not_a_real_token'),
  null,
  'an unknown token names nothing, so a forged webhook has no salon to act on'
);

-- ---------------------------------------------------------------------------
-- As the customer
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaab-aaaa-4000-8000-00000000000c",'
  '"app_role":"customer",'
  '"salon_id":"aaaaaaab-0000-4000-8000-000000000001"}',
  true
);

-- The disclosure block's numbers (RULES 5.3.6).
create temp table quote as select public.topup_quote(100000) as q;
grant select on quote to public;

select results_eq(
  $q$select (q ->> 'amount_paise')::bigint, (q ->> 'bonus_paise')::bigint from quote$q$,
  $q$values (100000::bigint, 10000::bigint)$q$,
  'the quote states the bonus the ledger will actually grant - two slabs of Rs 50'
);

select is(
  (select (q ->> 'bonus_expires_at') is not null from quote),
  true,
  'and when that bonus expires, before anyone pays'
);

select results_eq(
  $q$select (q ->> 'paid_credit_expires')::boolean, (q ->> 'refundable')::boolean from quote$q$,
  $q$values (false, false)$q$,
  'and the two facts a customer must know: paid credit never expires, top-ups are not refundable'
);

select is(
  (select (public.topup_quote(10000) ->> 'bonus_paise')::bigint),
  0::bigint,
  'below the salon''s minimum there is no bonus, and the screen says so rather than implying one'
);

-- Starting a top-up.
create temp table started as
select public.start_topup('bbbbbbbb-9999-4000-8000-000000000001', 100000) as r;
grant select on started to public;

select is((select r ->> 'ok' from started), 'true', 'a customer starts a Rs 1000 top-up');

select is(
  (select status::text from public.payments where id = (select (r ->> 'payment_id')::uuid from started)),
  'created',
  'which creates a payment in `created` - not captured, because nothing has been paid yet'
);

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = 'aaaaaaab-1111-4000-8000-00000000000c'),
  null,
  'and credits NOTHING - a phone saying "I paid" is not payment'
);

select is(
  (public.start_topup('bbbbbbbb-9999-4000-8000-000000000001', 100000) ->> 'payment_id'),
  (select r ->> 'payment_id' from started),
  'a retried tap returns the same payment rather than a second order (RULES 9.3)'
);

select is(
  (public.start_topup('bbbbbbbb-9999-4000-8000-000000000002', 10000) ->> 'reason'),
  'below_minimum',
  'an amount below the salon''s minimum is refused BY THE SERVER'
);

select is(
  (public.start_topup('bbbbbbbb-9999-4000-8000-000000000003', 99999999) ->> 'reason'),
  'above_maximum',
  'and an absurd amount never reaches a payment gateway'
);

select is(
  (public.start_topup('bbbbbbbb-9999-4000-8000-000000000004', -100000) ->> 'reason'),
  'invalid_amount',
  'nor a negative one'
);

reset role;

-- ---------------------------------------------------------------------------
-- The webhook's work
-- ---------------------------------------------------------------------------

-- A wrong amount is refused outright: the body is not evidence of what was owed.
select is(
  (app.record_payment_captured(
     (select (r ->> 'payment_id')::uuid from started), 'pay_FAKE', 50000) ->> 'reason'),
  'amount_mismatch',
  'a webhook claiming a different amount is refused, not partially accepted'
);

select is(
  (select status::text from public.payments
    where id = (select (r ->> 'payment_id')::uuid from started)),
  'created',
  'and the payment is left exactly as it was'
);

-- The real capture.
create temp table captured as
select app.record_payment_captured(
  (select (r ->> 'payment_id')::uuid from started), 'pay_REAL_1', 100000) as r;

select is((select r ->> 'ok' from captured), 'true', 'the correct amount captures');

select results_eq(
  $q$select kind::text, amount_paise from public.wallet_transactions
     where customer_id = 'aaaaaaab-1111-4000-8000-00000000000c' order by id$q$,
  $q$values ('credit_topup', 100000::bigint), ('credit_bonus', 10000::bigint)$q$,
  'and only THEN is the wallet credited - paid and bonus, as separate entries'
);

select is(
  (select balance_paise from public.wallet_accounts
    where customer_id = 'aaaaaaab-1111-4000-8000-00000000000c'),
  110000::bigint,
  'the balance is the top-up plus the bonus the quote promised'
);

-- Redelivery. This is the normal case, not an error.
select is(
  (app.record_payment_captured(
     (select (r ->> 'payment_id')::uuid from started), 'pay_REAL_1', 100000) ->> 'already'),
  'true',
  'a redelivered webhook is a no-op'
);

select is(
  (select count(*)::int from public.wallet_transactions
    where customer_id = 'aaaaaaab-1111-4000-8000-00000000000c'),
  2,
  'and credits nothing twice'
);

-- Dedupe at the door, before any of that work is repeated.
select is(
  app.webhook_seen('razorpay', 'evt_pay_001', 'aaaaaaab-0000-4000-8000-000000000001',
                   '{"event":"payment.captured"}'::jsonb),
  false,
  'the first arrival of an event is new'
);

select is(
  app.webhook_seen('razorpay', 'evt_pay_001', 'aaaaaaab-0000-4000-8000-000000000001',
                   '{"event":"payment.captured"}'::jsonb),
  true,
  'the second is recognised, so the work behind it is not redone'
);

select * from finish();
