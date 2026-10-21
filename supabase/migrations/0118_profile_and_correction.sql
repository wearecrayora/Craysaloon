-- 0118 The customer's profile: their name and language, theirs to change, and
-- the right to have anything else corrected (decided 21 Oct 2026).
--
-- 1. update_my_profile. A customer corrects their own NAME and sets their
--    LANGUAGE. Before this, the app's language choice lived only on the phone,
--    so every push went out in the salon's first language however the customer
--    had set the app: app.notify reads customers.language first (0059). Saving
--    it is what makes a Hindi-speaking customer's reminders arrive in Hindi.
--
--    Only those two columns. The phone number is not here and never will be:
--    it is the binding (RULES 4 - one number, one salon, no switch path).
--
-- 2. The right to correction, DPDP s.12(1). Anything a customer cannot change
--    themselves - above all a new phone number - is ASKED for, as a request
--    against the salon with the same 30-day clock as access and erasure. A new
--    number is then a transfer, done by a Crayora super-admin from the
--    console's binding desk once the salon has confirmed who is asking
--    (RULES 4.3). The customer never moves their own binding.

-- ---------------------------------------------------------------------------
-- 1. Language values the message templates know
-- ---------------------------------------------------------------------------

alter table public.customers
  add constraint customers_language_known check (language in ('en', 'hi', 'hi_Latn'));

create or replace function public.update_my_profile(
  p_name     text default null,
  p_language text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid := app.current_customer_id();
  v_name     text;
  v_gone     timestamptz;
begin
  if v_customer is null or app.current_app_role() <> 'customer' then
    raise exception 'update_my_profile: only the customer changes their own profile'
      using errcode = '42501';
  end if;

  select c.anonymised_at into v_gone from public.customers c where c.id = v_customer;
  if v_gone is not null then
    -- Erased: there is no identity left to edit.
    return jsonb_build_object('ok', false, 'reason', 'erased');
  end if;

  if p_name is not null then
    -- One space between words, none at the ends; letters, not a phone number.
    v_name := regexp_replace(btrim(p_name), '\s+', ' ', 'g');
    if char_length(v_name) < 2 or char_length(v_name) > 60 then
      return jsonb_build_object('ok', false, 'reason', 'name_length');
    end if;
    if v_name ~ '[[:cntrl:]]' or v_name !~ '[[:alpha:]]' then
      return jsonb_build_object('ok', false, 'reason', 'name_invalid');
    end if;
  end if;

  if p_language is not null and p_language not in ('en', 'hi', 'hi_Latn') then
    return jsonb_build_object('ok', false, 'reason', 'language');
  end if;

  update public.customers
     set name       = coalesce(v_name, name),
         language   = coalesce(p_language, language),
         updated_at = now()
   where id = v_customer;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.update_my_profile is
  'The customer''s own name and language, and nothing else - never the phone, which is the binding (RULES 4). Language decides which language their messages arrive in (0059).';

revoke all on function public.update_my_profile(text, text) from public, anon;
grant execute on function public.update_my_profile(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Correction joins access, erasure and grievance
-- ---------------------------------------------------------------------------

alter table public.data_rights_requests drop constraint data_rights_requests_kind_check;
alter table public.data_rights_requests
  add constraint data_rights_requests_kind_check
  check (kind in ('access', 'erasure', 'grievance', 'correction'));

create or replace function public.request_data_right(
  p_kind   text,
  p_detail text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_role     text := app.current_app_role();
  v_customer uuid;
  v_existing uuid;
  v_id       uuid;
begin
  if v_salon is null or v_role <> 'customer' then
    raise exception 'request_data_right: only the customer may ask' using errcode = '42501';
  end if;
  if p_kind not in ('access', 'erasure', 'grievance', 'correction') then
    raise exception 'request_data_right: unknown kind %', p_kind;
  end if;

  v_customer := app.current_customer_id();
  if v_customer is null then
    raise exception 'request_data_right: no customer for this session' using errcode = '42501';
  end if;

  -- One open request of a kind at a time. Tapping twice is impatience, not a
  -- second right, and a queue of duplicates helps nobody.
  select r.id into v_existing
    from public.data_rights_requests r
   where r.customer_id = v_customer and r.kind = p_kind
     and r.status in ('open', 'in_progress');
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'already', true, 'request_id', v_existing);
  end if;

  insert into public.data_rights_requests (salon_id, customer_id, kind, detail)
  values (v_salon, v_customer, p_kind, left(nullif(btrim(coalesce(p_detail, '')), ''), 500))
  returning id into v_id;

  -- The salon is the Data Fiduciary: it is told, in its own app, that it owes
  -- somebody an answer.
  insert into public.domain_events (salon_id, type, aggregate_id, payload)
  values (v_salon, 'data_right.requested', v_id,
          jsonb_build_object('kind', p_kind, 'customer_id', v_customer));

  return jsonb_build_object('ok', true, 'already', false, 'request_id', v_id);
end;
$$;

comment on function public.request_data_right is
  'Access, erasure, grievance or correction (DPDP ss.11, 12, 13). Raised against the SALON, which is the Data Fiduciary, with a due date so the obligation is visible rather than remembered. A new phone number is a correction, carried out as a transfer by Crayora (0118).';

revoke all on function public.request_data_right(text, text) from public, anon;
grant execute on function public.request_data_right(text, text) to authenticated;
