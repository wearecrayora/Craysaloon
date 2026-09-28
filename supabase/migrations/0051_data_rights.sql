-- 0051 The rights the DPDP Act gives a customer, made real
--
-- RULES 11.6-11.9 described these; nothing implemented them. The Act does not
-- treat them as features: withdrawal, access, correction, erasure and grievance
-- are entitlements, and a Data Fiduciary that cannot honour them is in breach
-- whatever its intentions (DPDP Act 2023 ss.6(4)-(6), 11, 12, 13; DPDP Rules
-- 2025, notified 14 Nov 2025, full compliance 13 May 2027).
--
-- Who is who, and it matters for every line below: **the SALON is the Data
-- Fiduciary; Crayora is a Data Processor** acting on its instructions (RULES
-- 11.7). So a request is raised against the salon, visible to the salon, and
-- answerable by the salon - with Crayora able to execute it on their behalf.
--
--   set_consent            withdrawal as easy as consent (s.6(4))
--   my_consents            what a customer has agreed to, so a screen can show it
--   data_rights_requests   access, erasure and grievance, with a statutory clock
--   anonymise_customer     erasure that keeps the books (s.12(3) vs statutory
--                          retention: identity goes, financial rows stay)

-- ---------------------------------------------------------------------------
-- 1. Consent, withdrawn as easily as it was given
-- ---------------------------------------------------------------------------
--
-- The consents table is an append-only LEDGER (RULES 11.6): withdrawal is a new
-- row saying `granted = false`, never an edit. That is what lets a salon show,
-- months later, what the customer had agreed to at the time - which is the only
-- honest answer to "why did you message me".

create or replace function public.set_consent(
  p_purpose public.consent_purpose,
  p_granted boolean
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
begin
  if v_salon is null or v_role <> 'customer' then
    -- Only the person themselves. A salon cannot tick a box on a customer's
    -- behalf: consent that someone else gave is not consent (s.6(1)).
    raise exception 'set_consent: only the customer may change their own consent'
      using errcode = '42501';
  end if;

  v_customer := app.current_customer_id();
  if v_customer is null then
    raise exception 'set_consent: no customer for this session' using errcode = '42501';
  end if;

  -- service_communication is the service itself: booking confirmations, payment
  -- receipts, the reminder they asked for. Withdrawing it would leave a customer
  -- with an account that cannot tell them anything, so it is not offered as a
  -- toggle - the way to end it is to leave, which erasure below does.
  if p_purpose = 'service_communication' and p_granted = false then
    return jsonb_build_object('ok', false, 'reason', 'service_communication_required');
  end if;

  insert into public.consents (salon_id, customer_id, purpose, granted, source)
  values (v_salon, v_customer, p_purpose, p_granted, 'customer');

  return jsonb_build_object('ok', true, 'purpose', p_purpose::text, 'granted', p_granted);
end;
$$;

comment on function public.set_consent is
  'Withdrawal as easy as consent (DPDP s.6(4)). Appends to the consent ledger - never edits, so the salon can always show what was agreed at the time. Only the customer themselves: consent given by someone else is not consent.';

revoke all on function public.set_consent(public.consent_purpose, boolean) from public, anon;
grant execute on function public.set_consent(public.consent_purpose, boolean) to authenticated;

-- What the "Your data" screen renders: the latest row per purpose.
create or replace function public.my_consents()
returns table (purpose text, granted boolean, occurred_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (c.purpose)
         c.purpose::text, c.granted, c.occurred_at
    from public.consents c
   where c.customer_id = app.current_customer_id()
     and c.salon_id = app.current_salon_id()
   order by c.purpose, c.occurred_at desc
$$;

revoke all on function public.my_consents() from public, anon;
grant execute on function public.my_consents() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Access, erasure and grievance - with a clock
-- ---------------------------------------------------------------------------
--
-- A right nobody can see the state of is a right in name only. Each request is a
-- row with a DUE DATE, so the salon can see what it owes and by when, and so
-- Crayora can report on it. The Rules expect a Data Fiduciary to publish how to
-- exercise these and to respond within a stated period; 30 days is the working
-- target here and is deliberately shorter than any outer limit.

create table public.data_rights_requests (
  id           uuid primary key default extensions.gen_random_uuid(),
  salon_id     uuid not null references public.salons(id) on delete cascade,
  customer_id  uuid not null references public.customers(id) on delete cascade,

  -- access: a copy of their data (s.11). erasure: delete it (s.12(3)).
  -- grievance: they are unhappy and the salon must answer (s.13).
  kind         text not null check (kind in ('access', 'erasure', 'grievance')),
  detail       text,

  status       text not null default 'open'
                 check (status in ('open', 'in_progress', 'completed', 'refused')),
  -- A refusal must say why: "we kept your invoices because the law requires it"
  -- is an answer; silence is not.
  outcome      text,

  requested_at timestamptz not null default now(),
  due_at       timestamptz not null default now() + interval '30 days',
  completed_at timestamptz,
  handled_by   uuid references public.platform_admins(id) on delete set null
);

create index data_rights_requests_salon_open_idx
  on public.data_rights_requests (salon_id, status, due_at);

create index data_rights_requests_customer_idx
  on public.data_rights_requests (salon_id, customer_id, requested_at desc);

alter table public.data_rights_requests enable row level security;
alter table public.data_rights_requests force row level security;

-- The salon sees its own requests - it is the Data Fiduciary and must answer
-- them. The restrictive policy from 0038 applies too, confining a customer to
-- their own rows.
create policy data_rights_requests_tenant on public.data_rights_requests
  for select to authenticated
  using (salon_id = app.current_salon_id());

create policy customer_scope on public.data_rights_requests
  as restrictive for all to authenticated
  using (app.current_app_role() <> 'customer'
         or customer_id = app.current_customer_id())
  with check (app.current_app_role() <> 'customer'
         or customer_id = app.current_customer_id());

-- Writes come through the function below, never straight from a device.
create policy server_only_write on public.data_rights_requests
  as restrictive for insert to authenticated with check (false);
create policy server_only_change on public.data_rights_requests
  as restrictive for update to authenticated using (false) with check (false);
create policy server_only_delete on public.data_rights_requests
  as restrictive for delete to authenticated using (false);

grant select on public.data_rights_requests to authenticated;

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
  if p_kind not in ('access', 'erasure', 'grievance') then
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
  values (v_salon, v_customer, p_kind, nullif(btrim(coalesce(p_detail, '')), ''))
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
  'Access, erasure or grievance (DPDP ss.11, 12(3), 13). Raised against the SALON, which is the Data Fiduciary, with a due date so the obligation is visible rather than remembered.';

revoke all on function public.request_data_right(text, text) from public, anon;
grant execute on function public.request_data_right(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Erasure that keeps the books
-- ---------------------------------------------------------------------------
--
-- DPDP s.12(3) gives a right to erasure; other law requires financial records to
-- be kept (GST, Companies Act - the exact period is a question for a CA, hence
-- the note in ARCHITECTURE 13). Both are satisfied by ANONYMISATION: the person
-- stops being identifiable, the money still adds up.
--
-- What goes: name, birthday, anniversary, the plaintext number, the link to the
-- login. What stays: the salted hash (so a returning number is still recognised
-- as already-bound, which is what keeps one phone to one salon enforceable), and
-- every financial row, now pointing at someone nobody can name.

create or replace function app_admin.anonymise_customer(
  p_actor_admin_id uuid,
  p_customer_id    uuid,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer record;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: an erasure needs a reason - it is the audit entry';
  end if;

  select c.id, c.salon_id, c.anonymised_at into v_customer
    from public.customers c where c.id = p_customer_id
   for update;

  if v_customer.id is null then
    raise exception 'app_admin: no such customer';
  end if;
  if v_customer.anonymised_at is not null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.customers
     set name = null,
         phone = null,
         birthday = null,
         anniversary = null,
         auth_user_id = null,
         anonymised_at = now(),
         updated_at = now()
   where id = p_customer_id;

  -- The binding goes with the identity: the person is no longer this salon's
  -- customer, and a future login starts fresh.
  delete from public.customer_identities where customer_id = p_customer_id;

  -- Their device tokens are personal data and have no purpose left.
  delete from public.notification_tokens where customer_id = p_customer_id;

  update public.data_rights_requests
     set status = 'completed', completed_at = now(), handled_by = p_actor_admin_id,
         outcome = 'Identity erased. Financial records retained in anonymised form '
                   'as other law requires.'
   where customer_id = p_customer_id and kind = 'erasure' and status in ('open', 'in_progress');

  perform app_admin.audit(
    v_customer.salon_id, p_actor_admin_id, 'customer.anonymised', 'customers',
    p_customer_id::text, p_reason, null,
    jsonb_build_object('financial_rows_retained', true));

  return jsonb_build_object('ok', true, 'already', false);
end;
$$;

comment on function app_admin.anonymise_customer is
  'Erasure as ANONYMISATION (RULES 11.8): name, birthday, plaintext number and the login link go; the salted hash and every financial row stay, because DPDP s.12(3) and statutory books-of-account retention both have to be satisfied. Photos in R2 are deleted by the job that owns them.';

select app_admin.close_privileges();
