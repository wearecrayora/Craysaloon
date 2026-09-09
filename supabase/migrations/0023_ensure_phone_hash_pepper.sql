-- 0023 The phone-hash pepper must exist
--
-- FOUND BY ASKING WHETHER PROVISIONING ACTUALLY WORKS.
--
-- `app.phone_hash` reads its pepper from the Vault secret `phone_hash_pepper`,
-- falling back to a session GUC. Every test sets that GUC, so every test
-- passed - and the hosted project had no Vault secret at all. The first real
-- provisioning through the console would have raised
--
--     phone_hash: no pepper configured (vault secret phone_hash_pepper)
--
-- inside app_admin.provision_salon, at the owner insert, and rolled the whole
-- transaction back. A green test suite over a schema that could not create a
-- single salon.
--
-- This is the same failure shape as the leak test that never switched role and
-- the bootstrap that set rolbypassrls itself: a check that supplies the
-- condition it is meant to be verifying. The fix is not another test - it is
-- to stop the condition being optional.
--
-- So: the pepper is ensured here, idempotently, and
-- supabase/tests/identity/pepper_test.sql asserts phone_hash works with NO GUC
-- set, which is the only version of that assertion worth having.
--
-- The value is generated INSIDE the database and never leaves it. Nobody -
-- including whoever runs this migration - ever sees it, which is the correct
-- handling for a secret whose only consumer is a database function.
--
-- ROTATION IS NOT A ROUTINE OPERATION. Changing this pepper changes every
-- phone_hash, which is the primary key of customer_identities - the table that
-- makes one phone mean one salon. Rotating it without a planned re-hash
-- migration would orphan every existing binding and let a bound customer bind
-- a second time. ARCHITECTURE 8.2 says the same; this comment exists because
-- the person who eventually rotates secrets on a schedule will read the
-- migration, not the architecture document.

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'phone_hash_pepper') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'phone_hash_pepper',
      'Pepper for app.phone_hash. Generated in-database by migration 0023 and '
      'never exported. Rotating it invalidates every customer_identities row '
      'and requires a planned re-hash migration.'
    );
    raise notice 'created the phone_hash pepper';
  end if;
end;
$$;

-- Prove it, here, rather than trusting the block above. If the pepper is
-- unreadable for any reason - wrong extension, wrong privileges - this fails
-- the migration instead of leaving a database that cannot provision a salon.
do $$
declare
  v_hash bytea;
begin
  -- Deliberately no set_config: this must work from Vault alone.
  select app.phone_hash('9876543210') into v_hash;

  if v_hash is null then
    raise exception '0023: phone_hash returned null even with a pepper present';
  end if;
end;
$$;
