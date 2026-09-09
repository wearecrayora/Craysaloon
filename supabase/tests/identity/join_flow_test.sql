-- RELEASE GATE: the salon-code-first join flow
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- These are the only functions in the system that `anon` can call, so they are
-- the only ones an unauthenticated stranger can reach. Two properties matter
-- more than the rest:
--
--   * a code for a salon that is not ACTIVE resolves to exactly the same thing
--     as a code that does not exist - null. Anything else turns this into an
--     oracle for which codes are real.
--   * an OTP request with no salon context is REFUSED (PHASES M3). A default
--     sender would let any number in India be made to cost Crayora money, and
--     would deliver an OTP from a brand the recipient has never heard of.

select plan(15);

insert into auth.users (id) values
  ('33333333-cccc-4000-8000-000000000001');

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values
  ('33333333-0000-4000-8000-00000000000a', 'Live Salon Ltd', 'Live Salon',
   'CRAY-AAABBB', 'active', '33333333-cccc-4000-8000-000000000001', now()),
  ('33333333-0000-4000-8000-00000000000b', 'Setup Salon Ltd', 'Setup Salon',
   'CRAY-CCCDDD', 'setup', null, null);

insert into public.salon_branding (salon_id, version, tokens)
values ('33333333-0000-4000-8000-00000000000a', 3,
        '{"displayName":"Live Salon","brand":{"light":{"primary":"#1f6f5c"}}}'::jsonb);

-- ---------------------------------------------------------------------------
-- resolve_join_code
-- ---------------------------------------------------------------------------

select is(
  public.resolve_join_code('CRAY-AAABBB') ->> 'display_name',
  'Live Salon',
  'an active salon resolves to its display name'
);

select is(
  (public.resolve_join_code('CRAY-AAABBB') -> 'branding') ->> 'displayName',
  'Live Salon',
  'and to its branding, so the app can theme its login screen before anyone signs in'
);

select is(
  public.resolve_join_code('CRAY-AAABBB') ->> 'branding_version',
  '3',
  'including the version, which is what tells an installed app to re-theme'
);

-- Case-insensitive: the code is read off a printed sticker and typed by hand.
select is(
  public.resolve_join_code('  cray-aaabbb  ') ->> 'display_name',
  'Live Salon',
  'lowercase and surrounding whitespace still resolve'
);

-- THE isolation property. A QR printed before activation is worthless.
select is(
  public.resolve_join_code('CRAY-CCCDDD'),
  null,
  'a salon in SETUP resolves to nothing - a leaked QR cannot bind customers early'
);

select is(
  public.resolve_join_code('CRAY-ZZZZZZ'),
  null,
  'an unknown code resolves to nothing - identical to the setup case, so this is no oracle'
);

-- Whatever the payload grows into, it must never grow to include customer
-- data or contact details. Asserted as an exact key set so an addition is a
-- deliberate decision made here, not a side effect elsewhere.
select set_eq(
  $$select jsonb_object_keys(public.resolve_join_code('CRAY-AAABBB'))$$,
  $$values ('salon_id'), ('display_name'), ('branding_version'), ('branding')$$,
  'the pre-auth payload carries exactly four keys and no customer data'
);

-- ---------------------------------------------------------------------------
-- start_join
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.start_join('CRAY-CCCDDD', '9800000001')$$,
  '22023', null,
  'start_join refuses a salon that is not active, with the same error as a bad code'
);

select lives_ok(
  $$select public.start_join('CRAY-AAABBB', '9800000001')$$,
  'start_join records an intent for an active salon'
);

select is(
  (select salon_id from public.join_intents
    where phone_hash = app.phone_hash('9800000001')),
  '33333333-0000-4000-8000-00000000000a'::uuid,
  'the intent names the salon whose account will pay for the OTP'
);

-- ---------------------------------------------------------------------------
-- resolve_otp_sender - the refusal is the point
-- ---------------------------------------------------------------------------

select is(
  app.resolve_otp_sender('9800000001') ->> 'source',
  'join_intent',
  'a live intent decides which salon sends the OTP'
);

-- A number nobody has ever heard of. No default sender, no fallback to
-- Crayora's account, no SMS.
select is(
  app.resolve_otp_sender('9700000009') ->> 'reason',
  'no_salon_context',
  'an OTP request with NO salon context is refused, not sent from a default account'
);

-- ---------------------------------------------------------------------------
-- The anon surface is exactly two functions
-- ---------------------------------------------------------------------------

-- Reachability, not just the ACL. 0024 granted anon USAGE on the whole `app`
-- schema to expose two entry points, which exposed every helper in it -
-- including app.phone_hash, an anon-callable hashing oracle that would undo
-- the pepper protecting a 10^9 keyspace. The schema stays shut; the door is
-- two wrappers in `public`, which is also the only schema PostgREST exposes.
select is(
  (select has_schema_privilege('anon', 'app', 'USAGE')),
  false,
  'anon has no USAGE on the app schema, so nothing in it is reachable'
);

select set_eq(
  $$select p.proname::text
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and has_function_privilege('anon', p.oid, 'EXECUTE')$$,
  $$values ('resolve_join_code'), ('start_join')$$,
  'the entire pre-auth surface is two functions in public, and nothing else'
);

select is(
  (select has_function_privilege('anon', 'app.phone_hash(text)', 'EXECUTE')),
  false,
  'anon cannot call phone_hash - an online hashing oracle would defeat the pepper'
);

select * from finish();
