-- RELEASE GATE: the rights the DPDP Act gives a customer
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- These are entitlements, not features (DPDP Act 2023 ss.6(4), 11, 12(3), 13;
-- DPDP Rules 2025). A Data Fiduciary that cannot honour them is in breach
-- whatever it intended, so each one is asserted against the function that runs:
--
--   * consent is a LEDGER - withdrawal is a new row, and the history survives
--   * only the person themselves may change their own consent
--   * access, erasure and grievance can be asked for, and land on the SALON
--     with a due date
--   * erasure means ANONYMISATION: the person goes, the money stays
--   * the salted hash survives erasure, so one-phone-one-salon stays enforceable

select plan(25);

insert into auth.users (id) values
  ('dddddddd-cccc-4000-8000-00000000000f'),
  ('dddddddd-cccc-4000-8000-00000000000a'),
  ('dddddddd-cccc-4000-8000-00000000000b');

insert into public.platform_admins (id, email, name, is_super, active)
values ('dddddddd-cccc-4000-8000-00000000000f', 'dpdp@crayora.test', 'DPDP Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at)
values ('dddddddd-cccc-4000-8000-000000000001', 'Rights Salon Ltd', 'Rights Salon',
        'CRAY-RGTQQQ', 'active', 'dddddddd-cccc-4000-8000-00000000000f', now());

insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash, birthday)
values
  ('dddddddd-cccc-4000-8000-00000000000c', 'dddddddd-cccc-4000-8000-000000000001',
   'dddddddd-cccc-4000-8000-00000000000a', 'Priya', '9855511001',
   app.phone_hash('9855511001'), date '1994-03-04'),
  ('dddddddd-cccc-4000-8000-00000000000d', 'dddddddd-cccc-4000-8000-000000000001',
   'dddddddd-cccc-4000-8000-00000000000b', 'Ravi', '9855511002',
   app.phone_hash('9855511002'), null);

insert into public.customer_identities (phone_hash, auth_user_id, salon_id, customer_id)
values (app.phone_hash('9855511001'), 'dddddddd-cccc-4000-8000-00000000000a',
        'dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c');

-- Consent as it stands at binding: service on, marketing off (0034).
insert into public.consents (salon_id, customer_id, purpose, granted, source)
values
  ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
   'service_communication', true, 'binding'),
  ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
   'promotional', true, 'binding'),
  ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
   'whatsapp', false, 'binding'),
  ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
   'photos', false, 'binding');

-- Money and history, so erasure has something to have to keep.
insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
values ('dddddddd-cccc-4000-8000-00000000000c', 'dddddddd-cccc-4000-8000-000000000001', 25000);

insert into public.wallet_transactions
  (salon_id, customer_id, kind, amount_paise, balance_after)
values ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
        'credit_topup', 25000, 25000);

insert into public.notification_tokens (salon_id, customer_id, token, platform)
values ('dddddddd-cccc-4000-8000-000000000001', 'dddddddd-cccc-4000-8000-00000000000c',
        'fcm-token-for-priya', 'android');

-- ---------------------------------------------------------------------------
-- As the customer
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-cccc-4000-8000-00000000000a",'
  '"app_role":"customer",'
  '"salon_id":"dddddddd-cccc-4000-8000-000000000001"}',
  true
);

select is((select current_user)::text, 'authenticated',
  'the test runs as authenticated, so these assertions mean something');

select results_eq(
  $q$select purpose, granted from public.my_consents() order by purpose$q$,
  $q$values ('photos', false), ('promotional', true),
           ('service_communication', true), ('whatsapp', false)$q$,
  'a customer can see exactly what they have agreed to (s.11)'
);

-- WITHDRAWAL, as easy as consent was (s.6(4)).
select is(
  (public.set_consent('promotional', false) ->> 'ok'),
  'true',
  'and can withdraw marketing consent themselves, in one call'
);

select is(
  (select granted from public.my_consents() where purpose = 'promotional'),
  false,
  'which takes effect immediately'
);

-- The LEDGER: withdrawal is a new row, not an edit (RULES 11.6).
select is(
  (select count(*)::int from public.consents
    where customer_id = 'dddddddd-cccc-4000-8000-00000000000c' and purpose = 'promotional'),
  2,
  'the withdrawal is a NEW row - the salon can still show what was agreed, and when'
);

select is(
  (select granted from public.consents
    where customer_id = 'dddddddd-cccc-4000-8000-00000000000c'
      and purpose = 'promotional' order by occurred_at limit 1),
  true,
  'and the original consent is still there, unedited'
);

select is(
  (public.set_consent('promotional', true) ->> 'granted'),
  'true',
  'consent can be given again later - this is a ledger, not a one-way door'
);

-- Service messages are the service. Withdrawing them would leave an account
-- that cannot tell its owner anything, so the honest answer is "leave instead".
select is(
  (public.set_consent('service_communication', false) ->> 'reason'),
  'service_communication_required',
  'service messages cannot be switched off while the account exists - erasure is the way out'
);

-- The rights that need the salon to act.
create temp table asked as select public.request_data_right('access') as r;
grant select on asked to public;

select is((select r ->> 'ok' from asked), 'true', 'a customer can ask for a copy of their data (s.11)');

select is(
  (select kind from public.data_rights_requests
    where id = (select (r ->> 'request_id')::uuid from asked)),
  'access',
  'and it is recorded as a request the salon owes an answer to'
);

select is(
  (select due_at > now() + interval '29 days' from public.data_rights_requests
    where id = (select (r ->> 'request_id')::uuid from asked)),
  true,
  'with a due date, so the obligation is visible rather than remembered'
);

select is(
  (public.request_data_right('access') ->> 'already'),
  'true',
  'asking twice does not create a queue of duplicates'
);

select is(
  (public.request_data_right('erasure', 'I have moved city') ->> 'ok'),
  'true',
  'and erasure is a different right, asked for separately (s.12(3))'
);

-- One customer cannot see or act for another.
select is(
  (select count(*)::int from public.data_rights_requests),
  2,
  'a customer sees only their OWN requests'
);

reset role;

-- ---------------------------------------------------------------------------
-- A stylist cannot consent on someone's behalf
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-cccc-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"dddddddd-cccc-4000-8000-000000000001"}',
  true
);

select throws_ok(
  $q$select public.set_consent('promotional', true)$q$,
  '42501', null,
  'the SALON cannot tick a consent box for a customer - consent someone else gave is not consent'
);

select is(
  (select count(*)::int from public.data_rights_requests),
  2,
  'but the salon does see the requests it owes answers to - it is the Data Fiduciary'
);

reset role;

-- ---------------------------------------------------------------------------
-- Access: the copy can actually be produced, and the request closed (0091)
-- ---------------------------------------------------------------------------

create temp table copy as
  select app_admin.access_request_export('dddddddd-cccc-4000-8000-00000000000f',
           (select (r ->> 'request_id')::uuid from asked)) as j;

select ok(
  (select j -> 'you' ->> 'name' = 'Priya'
      and jsonb_array_length(j -> 'consents') > 4  -- the whole ledger, withdrawals included
      and (j -> 'wallet' ->> 'balance_paise')::bigint = 25000
     from copy),
  'the copy holds who they are, what they agreed to, and their money (s.11)');

select throws_like(
  $q$select app_admin.complete_access_request('dddddddd-cccc-4000-8000-00000000000f',
       (select (r ->> 'request_id')::uuid from asked), ' ')$q$,
  '%how the copy reached%',
  'closing it needs to say how the copy reached the person');

select app_admin.complete_access_request('dddddddd-cccc-4000-8000-00000000000f',
  (select (r ->> 'request_id')::uuid from asked), 'emailed to the address they gave on 3 Jan');

select is(
  (select outcome from public.data_rights_requests
    where id = (select (r ->> 'request_id')::uuid from asked)),
  'A copy of your data was sent to you: emailed to the address they gave on 3 Jan',
  'and the customer sees that outcome under Your data');

-- ---------------------------------------------------------------------------
-- Erasure: the person goes, the money stays
-- ---------------------------------------------------------------------------

select is(
  (app_admin.anonymise_customer(
     'dddddddd-cccc-4000-8000-00000000000f',
     'dddddddd-cccc-4000-8000-00000000000c',
     'Customer asked to be erased') ->> 'ok'),
  'true',
  'Crayora can execute the erasure on the salon''s behalf, with a reason'
);

select results_eq(
  $q$select name, phone, birthday, auth_user_id, (anonymised_at is not null)
       from public.customers where id = 'dddddddd-cccc-4000-8000-00000000000c'$q$,
  $q$values (null::text, null::text, null::date, null::uuid, true)$q$,
  'the identity is gone: name, number, birthday and the link to their login'
);

select is(
  (select phone_hash is not null from public.customers
    where id = 'dddddddd-cccc-4000-8000-00000000000c'),
  true,
  'the salted hash REMAINS - it is what keeps one phone to one salon enforceable'
);

select results_eq(
  $q$select count(*)::int, sum(amount_paise)::bigint from public.wallet_transactions
      where customer_id = 'dddddddd-cccc-4000-8000-00000000000c'$q$,
  $q$values (1, 25000::bigint)$q$,
  'and every financial row stays, now pointing at someone nobody can name (RULES 11.8)'
);

select is(
  (select count(*)::int from public.notification_tokens
    where customer_id = 'dddddddd-cccc-4000-8000-00000000000c'),
  0,
  'their device tokens are deleted - personal data with no purpose left'
);

select results_eq(
  $q$select status, (outcome is not null) from public.data_rights_requests
      where customer_id = 'dddddddd-cccc-4000-8000-00000000000c' and kind = 'erasure'$q$,
  $q$values ('completed', true)$q$,
  'the request is closed WITH an outcome - a refusal or a limit must be explained, never silent'
);

select * from finish();
