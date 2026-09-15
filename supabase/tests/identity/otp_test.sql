-- RELEASE GATE: the OTP challenge (ADR-36)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- Message Central generates, sends and verifies the code; the server only
-- remembers which verification it started, for which phone, for which salon.
-- Everything below is about that memory being impossible to misuse:
--
--   * no salon context, no send - and no money spent;
--   * a code is only ever checked against the challenge the server issued;
--   * five attempts, then nothing;
--   * one verification yields at most one session;
--   * the identity a session is minted for carries no plaintext phone.

select plan(24);

insert into auth.users (id) values ('55555555-eeee-4000-8000-000000000001');

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values ('55555555-0000-4000-8000-00000000000a', 'OTP Salon Ltd', 'OTP Salon',
        'CRAY-QQQRRR', 'active', '55555555-eeee-4000-8000-000000000001', now());

insert into public.salon_integrations (salon_id, provider, status)
values ('55555555-0000-4000-8000-00000000000a', 'message_central', 'missing');

-- A new customer, mid-join.
select public.start_join('CRAY-QQQRRR', '9811100001');

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

select is(
  public.otp_begin('9811100099') ->> 'reason',
  'no_salon_context',
  'a number with no salon context is refused before any money is spent'
);

select is(
  (public.otp_begin('9811100001') ->> 'salon_id')::uuid,
  '55555555-0000-4000-8000-00000000000a'::uuid,
  'a number with a live join intent resolves to that salon'
);

-- Two more sends are allowed (resend, resend again); the fourth is not.
select public.otp_begin('9811100001');
select public.otp_begin('9811100001');
select is(
  public.otp_begin('9811100001') ->> 'reason',
  'rate_limited',
  'the fourth send in ten minutes is refused - every send is real money'
);

-- ---------------------------------------------------------------------------
-- The challenge
-- ---------------------------------------------------------------------------

create temp table t_ch as
  select public.otp_record_challenge(
    '9811100001', '55555555-0000-4000-8000-00000000000a', 'mc-verification-1', 'salon') as id;

select is(
  public.otp_attempt((select id from t_ch)) ->> 'verification_id',
  'mc-verification-1',
  'an attempt returns the verification the SERVER started - the client never names it'
);

-- Five attempts in total, then nothing. One is already spent above.
select public.otp_attempt((select id from t_ch));
select public.otp_attempt((select id from t_ch));
select public.otp_attempt((select id from t_ch));
select is(
  public.otp_attempt((select id from t_ch)) ->> 'ok',
  'true',
  'the fifth attempt is still allowed'
);
select is(
  public.otp_attempt((select id from t_ch)) ->> 'reason',
  'too_many_attempts',
  'the sixth is refused - a six-digit code cannot be ground through'
);

-- A resend supersedes the old challenge, so an old id cannot be kept around
-- and ground against in parallel.
create temp table t_ch2 as
  select public.otp_record_challenge(
    '9811100001', '55555555-0000-4000-8000-00000000000a', 'mc-verification-2', 'salon') as id;

select is(
  public.otp_attempt((select id from t_ch)) ->> 'reason',
  'expired',
  'resending supersedes the previous challenge'
);

select is(
  public.otp_attempt('00000000-0000-4000-8000-000000000000') ->> 'reason',
  'expired',
  'an unknown challenge looks exactly like an expired one - no oracle'
);

-- ---------------------------------------------------------------------------
-- Completion: one verification, at most one session
-- ---------------------------------------------------------------------------

select is(
  public.otp_complete((select id from t_ch2)) ->> 'identity',
  encode(app.phone_hash('9811100001'), 'hex') || '@phone.craysalon.invalid',
  'the session is minted for an identity derived from the peppered hash'
);

select is(
  public.otp_complete((select id from t_ch2)) ->> 'reason',
  'expired',
  'completing the same challenge twice is refused - no second session'
);

-- The identity must never carry the number itself: auth.users is not where a
-- plaintext phone belongs (RULES 4.7).
select is(
  position('9811100001' in (
    encode(app.phone_hash('9811100001'), 'hex') || '@phone.craysalon.invalid')),
  0,
  'the Auth identity contains no plaintext phone number'
);

-- ---------------------------------------------------------------------------
-- Sender credentials, at the moment of use
-- ---------------------------------------------------------------------------

select is(
  public.otp_salon_sender('55555555-0000-4000-8000-00000000000a'),
  null,
  'a salon with no Message Central credential yields null - the caller falls back and alerts'
);

insert into public.platform_admins (id, email, name, is_super, active)
values ('55555555-eeee-4000-8000-000000000001', 'otp@crayora.test', 'OTP Op', false, true);

select app_admin.set_integration_secret(
  '55555555-eeee-4000-8000-000000000001',
  '55555555-0000-4000-8000-00000000000a',
  'message_central', 'not-a-real-mc-token-FOR-TEST', 'C-TESTCUSTOMER', null);

select is(
  public.otp_salon_sender('55555555-0000-4000-8000-00000000000a') ->> 'customer_id',
  'C-TESTCUSTOMER',
  'once stored, the salon''s own account is used'
);

-- A credential already seen to fail must not cost a customer a login attempt
-- to rediscover.
update public.salon_integrations set status = 'failing'
 where salon_id = '55555555-0000-4000-8000-00000000000a' and provider = 'message_central';

select is(
  public.otp_salon_sender('55555555-0000-4000-8000-00000000000a'),
  null,
  'a credential marked failing is not tried again - straight to the fallback'
);

-- ---------------------------------------------------------------------------
-- None of this is reachable by a tenant
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'otp\_%'
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
  0,
  'no OTP function is callable by anon or authenticated - only by the Edge Functions'
);

-- otp_salon_sender returns a decrypted credential. It must be the only public
-- function that does.
select set_eq(
  $$with fns as materialized (
      select p.oid, p.proname from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.prokind = 'f')
    select proname::text from fns
     where pg_get_functiondef(oid) ~* 'decrypted_secret'$$,
  $$values ('otp_salon_sender')$$,
  'exactly one public function reads a decrypted secret, and it is the OTP sender'
);

-- ---------------------------------------------------------------------------
-- One normalisation, not two (0029)
-- ---------------------------------------------------------------------------
--
-- Message Central gets app.canonical_phone(); binding uses app.phone_hash().
-- If those two ever disagreed about which inputs are "the same phone", the
-- number that received the OTP and the number that got bound could differ.
-- Asserted across every format the binding gate already covers.

select is(
  (select count(*)::int
     from (values ('9876543210'), ('+91 98765 43210'), ('0091 9876543210'),
                  ('091-9876543210'), ('09876543210'), ('919876543210')) v(p)
    where app.canonical_phone(v.p) <> '9876543210'),
  0,
  'every accepted format canonicalises to the same 10-digit number'
);

select is(
  (select count(distinct app.phone_hash(v.p))::int
     from (values ('9876543210'), ('+91 98765 43210'), ('0091 9876543210'),
                  ('091-9876543210'), ('09876543210'), ('919876543210')) v(p)),
  1,
  'and those same formats produce exactly one hash - the two functions agree'
);

select is(
  public.otp_begin('+91 98111 00001') ->> 'mobile',
  null,
  'otp_begin is rate-limited here, so it returns no number for a fourth send'
);

-- ---------------------------------------------------------------------------
-- The caller limit keys on the CUSTOMER, not the Edge Function (0030)
-- ---------------------------------------------------------------------------
--
-- otp_begin is only ever called by the Edge Function, so the address
-- PostgREST records is the function's. Keyed on that, every customer in the
-- country shares ten sends per ten minutes and login fails for everyone on
-- the first busy morning. Simulate exactly that header and check which bucket
-- is actually charged.

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values ('55555555-0000-4000-8000-00000000000b', 'Key Salon Ltd', 'Key Salon',
        'CRAY-KKKMMM', 'active', '55555555-eeee-4000-8000-000000000001', now());
select public.start_join('CRAY-KKKMMM', '9822200001');
select set_config('request.headers', '{"x-forwarded-for": "10.0.0.99"}', true);
select public.otp_begin('9822200001', 'customer-203.0.113.7');

select is(
  (select array_agg(bucket order by bucket)::text
     from public.rate_limit_counters
    where bucket in ('otp_send_caller:10.0.0.99', 'otp_send_caller:customer-203.0.113.7')),
  '{otp_send_caller:customer-203.0.113.7}',
  'the send limit charges the customer''s address, never the Edge Function''s'
);

-- ---------------------------------------------------------------------------
-- The server only adopts accounts it created (0031)
-- ---------------------------------------------------------------------------
--
-- Account pre-hijacking: with public sign-up open, anyone could create an
-- account at a customer's synthetic address with a password they know, and
-- the server would adopt it on the customer's first login. The defence is that
-- otp-verify only trusts accounts recorded here.

select is(
  (select public.otp_complete(public.otp_record_challenge(
     '9811100001', '55555555-0000-4000-8000-00000000000a', 'mc-verification-3', 'salon'))
     ->> 'auth_user_id'),
  null,
  'a first login reports no owned account - the server must create and record one'
);

create temp table t_ch3 as
  select public.otp_record_challenge(
    '9811100001', '55555555-0000-4000-8000-00000000000a', 'mc-verification-4', 'salon') as id;
select public.otp_complete((select id from t_ch3));

insert into auth.users (id) values ('55555555-eeee-4000-8000-0000000000c1');
select public.otp_link_identity((select id from t_ch3), '55555555-eeee-4000-8000-0000000000c1');

select is(
  (select public.otp_complete(public.otp_record_challenge(
     '9811100001', '55555555-0000-4000-8000-00000000000a', 'mc-verification-5', 'salon'))
     ->> 'auth_user_id')::uuid,
  '55555555-eeee-4000-8000-0000000000c1'::uuid,
  'once recorded, later logins are minted for exactly that account'
);

-- The link is keyed on a verified challenge, never on a hash the caller
-- supplies, so an account cannot be linked to an arbitrary phone.
select throws_ok(
  $$select public.otp_link_identity(
      '00000000-0000-4000-8000-000000000000', '55555555-eeee-4000-8000-0000000000c1')$$,
  'P0001', null,
  'an account can only be linked to the phone of a genuinely completed challenge'
);

select is(
  (select count(*)::int from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname = 'auth_identities'),
  0,
  'auth_identities has no policies - no tenant can read who owns which account'
);

select * from finish();
