-- 0110 Age, and a parent's or guardian's consent for a child (DPDP Act s.9).
--
-- Decided 14 Oct 2026. Before this, the privacy policy said a salon "must not
-- create an account for anyone under 18 without verifiable consent from a parent
-- or guardian" - and nothing in the product asked anyone's age. A rule nobody is
-- asked about is a sentence, not a control.
--
-- Now the join screen asks, with nothing pre-selected: 18 or older, or under 18.
-- Under 18 needs a parent or guardian to give their name and confirm, on the
-- spot, that they agree. And a child is never sent marketing:
--
--   * otp-verify refuses an under-18 join with no guardian, and sends no
--     marketing consent for one;
--   * public.record_age_declaration records the answer against the customer
--     the login bound (service role only - the Edge Function calls it);
--   * a trigger on consents refuses promotional or WhatsApp consent for a minor
--     from ANY path, so no screen, script or future function can get it wrong
--     (s.9(3): no tracking, behavioural monitoring or targeted advertising
--     directed at children - the visit reminder is a marketing message here);
--   * erasure clears the guardian's name with the rest of the identity.
--
-- What this is not: "verifiable" consent in the sense of DPDP Rules 2025 r.10,
-- which contemplates checking the parent's identity (e.g. a DigiLocker token).
-- It is a recorded declaration, made in the salon, by the adult present.
-- COMPLIANCE.md records the gap.

alter table public.customers
  add column if not exists is_minor        boolean not null default false,
  add column if not exists guardian_name   text,
  add column if not exists age_declared_at timestamptz;

comment on column public.customers.is_minor is
  'Declared under 18 at join (0110). No promotional or WhatsApp consent can be granted while true.';
comment on column public.customers.guardian_name is
  'The parent or guardian who consented for a customer declared under 18 (0110). Cleared on erasure.';

-- ---------------------------------------------------------------------------
-- Recording the answer
-- ---------------------------------------------------------------------------

create or replace function public.record_age_declaration(p_auth_user_id uuid, p_age jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_adult    boolean;
  v_guardian text;
  v_customer record;
begin
  if p_age is null or jsonb_typeof(p_age) <> 'object' or not p_age ? 'adult' then
    return jsonb_build_object('ok', false, 'reason', 'not_declared');
  end if;
  v_adult := (p_age ->> 'adult')::boolean;
  v_guardian := nullif(btrim(coalesce(p_age ->> 'guardian_name', '')), '');

  if not v_adult and (v_guardian is null or length(v_guardian) < 2
                      or coalesce((p_age ->> 'guardian_confirms')::boolean, false) is not true) then
    return jsonb_build_object('ok', false, 'reason', 'guardian_required');
  end if;

  update public.customers c
     set is_minor = not v_adult,
         guardian_name = case when v_adult then null else left(v_guardian, 120) end,
         age_declared_at = now(),
         updated_at = now()
   where c.auth_user_id = p_auth_user_id
     and c.anonymised_at is null
  returning c.id, c.salon_id into v_customer;

  if v_customer.id is null then
    -- A staff login, or no customer row: nothing to record.
    return jsonb_build_object('ok', true, 'recorded', false);
  end if;

  if not v_adult then
    -- Whatever was ticked, a child gets no marketing: withdrawn, on the record.
    insert into public.consents (salon_id, customer_id, purpose, granted, source)
    values (v_customer.salon_id, v_customer.id, 'promotional', false, 'age_declaration'),
           (v_customer.salon_id, v_customer.id, 'whatsapp', false, 'age_declaration');
  end if;

  return jsonb_build_object('ok', true, 'recorded', true, 'minor', not v_adult);
end;
$$;

comment on function public.record_age_declaration(uuid, jsonb) is
  'Called ONLY by otp-verify, after a login binds (0110). Records 18+ or under-18 with the guardian who consented; a minor''s marketing consent is withdrawn on the record.';

revoke all on function public.record_age_declaration(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_age_declaration(uuid, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- No marketing to a child, from any path
-- ---------------------------------------------------------------------------

create or replace function app.no_marketing_to_children()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.granted
     and new.purpose in ('promotional', 'whatsapp')
     and exists (select 1 from public.customers c where c.id = new.customer_id and c.is_minor) then
    raise exception 'consent: a customer under 18 cannot be sent offers or reminders (DPDP s.9)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists consents_no_marketing_to_children on public.consents;
create trigger consents_no_marketing_to_children
  before insert on public.consents
  for each row execute function app.no_marketing_to_children();

-- ---------------------------------------------------------------------------
-- Erasure takes the guardian's name too
-- ---------------------------------------------------------------------------

create or replace function app.erase_guardian_with_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.anonymised_at is not null and old.anonymised_at is null then
    new.guardian_name := null;
  end if;
  return new;
end;
$$;

drop trigger if exists customers_erase_guardian on public.customers;
create trigger customers_erase_guardian
  before update on public.customers
  for each row execute function app.erase_guardian_with_identity();

revoke all on function app.no_marketing_to_children() from public, anon, authenticated;
revoke all on function app.erase_guardian_with_identity() from public, anon, authenticated;
