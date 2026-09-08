-- 0015 Phone normalisation: handle every international prefix form
--
-- SECOND normalisation gap, found by the binding gate.
--
-- 0006 enumerated prefix shapes by length:
--     12 digits starting '91'    ->  strip
--     13 digits starting '091'   ->  strip
--     11 digits starting '0'     ->  strip
--
-- which misses '0091XXXXXXXXXX' - India's actual international dialling
-- prefix, 14 digits, and a form people genuinely type. It would have hashed to
-- something different from the same person's plain 10-digit number, and
-- customer_identities.phone_hash is the primary key enforcing one binding per
-- phone. A missed prefix is a second identity for the same human.
--
-- Enumerating shapes was the wrong approach: there is always another shape.
-- Strip ALL leading zeros first, then the country code. That covers 00, 0091,
-- 091, 0 and any combination, and it cannot be defeated by a form nobody
-- thought of.
--
-- Safe because Indian mobile numbers start 6-9, so no significant digit is
-- ever a leading zero.

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

  -- 1. Drop every leading zero: handles 0, 00 and 0091 in one step.
  v_digits := regexp_replace(v_digits, '^0+', '');

  -- 2. Drop the country code if what remains is 91 + a 10-digit number.
  if length(v_digits) = 12 and left(v_digits, 2) = '91' then
    v_digits := right(v_digits, 10);
  end if;

  -- 3. Canonical form or nothing. A typo must never become a silent second
  --    identity for the same person.
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
  'Peppered HMAC of the canonical 10-digit Indian mobile number. Leading zeros then the 91 country code are stripped, so 0091/091/00/0 and any spacing all collapse to one hash. Invalid numbers raise.';
