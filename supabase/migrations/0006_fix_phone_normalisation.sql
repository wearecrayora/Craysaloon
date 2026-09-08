-- 0006 Fix phone normalisation
--
-- BUG (caught before any data existed):
--   app.phone_hash only stripped non-digits, so
--     '+91 98765 43210' -> '919876543210'
--     '9876543210'      -> '9876543210'
--   produced DIFFERENT hashes for the same human being.
--
-- customer_identities.phone_hash is the primary key that enforces one active
-- binding per phone (ARCHITECTURE 5.4). With format-dependent hashing, the
-- same person could bind to one salon as "9876543210" and to a second as
-- "+919876543210" - the single most important invariant in the product,
-- defeated by a formatting difference.
--
-- Migrations are forward-only (RULES.md 6.1), so this replaces the function
-- rather than editing 0002.
--
-- Canonical form is the 10-digit Indian national number. Everything reduces
-- to that or is rejected: silently hashing a malformed number is how you get
-- two identities for one person.

create or replace function app.phone_hash(p_phone text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pepper text;
  v_digits text;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'phone_hash: empty phone';
  end if;

  v_digits := regexp_replace(p_phone, '[^0-9]', '', 'g');

  -- Reduce every accepted shape to the 10-digit national number.
  --   +91 98765 43210 / 0091... -> 919876543210 -> 9876543210
  --   098765 43210              -> 09876543210  -> 9876543210
  if length(v_digits) = 12 and left(v_digits, 2) = '91' then
    v_digits := right(v_digits, 10);
  elsif length(v_digits) = 13 and left(v_digits, 3) = '091' then
    v_digits := right(v_digits, 10);
  elsif length(v_digits) = 11 and left(v_digits, 1) = '0' then
    v_digits := right(v_digits, 10);
  end if;

  -- Indian mobile numbers are 10 digits starting 6-9. Anything else is a
  -- typo or a landline, and must not become a silent second identity.
  if v_digits !~ '^[6-9][0-9]{9}$' then
    raise exception 'phone_hash: not a valid Indian mobile number';
  end if;

  begin
    select decrypted_secret into v_pepper
      from vault.decrypted_secrets
     where name = 'phone_hash_pepper'
     limit 1;
  exception when others then
    v_pepper := null;
  end;

  v_pepper := coalesce(
    v_pepper,
    nullif(current_setting('app.phone_hash_pepper', true), '')
  );

  if v_pepper is null then
    raise exception
      'phone_hash: no pepper configured (vault secret phone_hash_pepper)';
  end if;

  return extensions.hmac(v_digits, v_pepper, 'sha256');
end;
$$;

comment on function app.phone_hash(text) is
  'Peppered HMAC of the CANONICAL 10-digit Indian mobile number. Every accepted format reduces to the same hash; invalid numbers raise rather than becoming a second identity.';
