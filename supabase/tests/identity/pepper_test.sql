-- GATE: the phone-hash pepper is configured, not supplied by the test
--
-- This file sets NO GUC on purpose. Every other test in this suite calls
--
--     select set_config('app.phone_hash_pepper', '...', true);
--
-- which is fine for isolating their fixtures, but it means they would all pass
-- against a database where no pepper exists at all - and that was true of the
-- hosted project until migration 0023. The first real provisioning would have
-- failed at the owner insert with "no pepper configured", inside a transaction
-- that then rolled back the whole salon.
--
-- A test that supplies the condition it is checking is not checking anything.
-- This one asserts the production path: Vault, no fallback.

select plan(4);

select is(
  (select count(*)::int from vault.secrets where name = 'phone_hash_pepper'),
  1,
  'exactly one phone_hash_pepper secret exists in Vault'
);

-- THE assertion. No set_config anywhere above this line.
select lives_ok(
  $$select app.phone_hash('9876543210')$$,
  'app.phone_hash works with NO session GUC - it reads the pepper from Vault'
);

-- Stable across calls, or customer_identities would not be a usable key.
select is(
  app.phone_hash('9876543210'),
  app.phone_hash('+91 98765 43210'),
  'the same number in any format still collapses to one hash under the real pepper'
);

-- The peppering is doing something: a bare sha256 of the digits would be
-- brute-forceable across a 10^9 keyspace, which is the entire reason for a
-- pepper (ADR-15).
select isnt(
  app.phone_hash('9876543210'),
  extensions.digest('9876543210', 'sha256'),
  'the hash is peppered, not a bare digest of the number'
);

select * from finish();
