-- 0089 M12: offboarding a salon (export, credit settlement, purge) and support
-- mode.
--
-- ═══ PURGE: PERSONAL GOES, FINANCIAL STAYS ═══
--
-- PRD 14 / 16A.6 and ARCHITECTURE 13.2: ninety days after suspension the
-- salon's operational and personal data is purged, but invoices, payments and
-- the wallet and loyalty ledgers are kept for the statutory books-of-account
-- period, with the people in them anonymised. Deleting the books would breach
-- tax law; keeping them identifiable would breach DPDP.
--
-- The "restricted archive" is built IN PLACE, not by moving rows. The financial
-- tables are append-only with triggers that refuse DELETE, and they are joined
-- by foreign keys to visits, bookings and customers; copying them elsewhere and
-- deleting the originals would mean switching off the very protections this
-- purge must preserve. Instead every PATH to them is closed:
--   * every customer is anonymised and unbound - no customer can log in;
--   * every staff account is anonymised, deactivated and unlinked - no owner
--     or stylist can log in;
--   * the salon stays suspended and is marked purged - it cannot be activated
--     again, and no code resolves.
-- What remains is reachable only by Crayora super-admins through the console,
-- which is what "restricted, audit-logged" asks for (PRD 16A.6).
--
-- Preconditions, each refused with a sentence rather than skipped:
--   1. billing says purge is due (app.billing_state = 'purge_due');
--   2. the owner was offered an export of their data, and when, is recorded;
--   3. if customers still hold credit, how the salon settled it is recorded
--      (PRD 16A.2). The ledger is NOT touched to do that - only five callers
--      may post to a ledger (RULES 5.2), and "settled on exit" is not one of
--      them. The balance stays in the books, beside the recorded settlement;
--   4. a super-admin, a reason, and the salon's display name typed back.
--
-- Binding exclusivity after purge: each customer's binding is RELEASED, with an
-- `unbind` event, exactly as a single erasure does. A phone bound to a salon
-- that no longer exists must be free to join another - one active binding, and
-- here zero is the right number.
--
-- ═══ SUPPORT MODE ═══
--
-- ARCHITECTURE 14.2, RULES 6.8: time-boxed (60 minutes by default), reason
-- required, PII-minimising views with the phone masked to its last four digits,
-- and un-masking a separate, separately-logged action.

-- ---------------------------------------------------------------------------
-- Offboarding facts on the salon
-- ---------------------------------------------------------------------------

alter table public.salons
  add column export_offered_at   timestamptz,
  add column export_offered_note text,
  add column credit_settled_at   timestamptz,
  add column credit_settled_note text,
  add column purged_at           timestamptz,
  add column purged_by           uuid references public.platform_admins(id);

comment on column public.salons.purged_at is
  'When the salon''s personal and operational data was purged (0089). Its financial records remain, anonymised and reachable only by Crayora super-admins. A purged salon can never be activated again.';

-- A purged salon never comes back: nothing personal is left to come back to.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(
           'app_admin.activate_salon(uuid, uuid, text)'::regprocedure) into strict v_def;
  v_new := replace(v_def,
    $x$  -- PRD 14: there is no free trial;$x$,
    $x$  if exists (select 1 from public.salons where id = p_salon_id and purged_at is not null) then
    raise exception 'app_admin: this salon was purged - it cannot be activated again';
  end if;

  -- PRD 14: there is no free trial;$x$);
  if v_new = v_def then raise exception '0089: activate_salon shape'; end if;
  execute v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The owner's export: everything the salon holds, in one document
-- ---------------------------------------------------------------------------

create or replace function app_admin.salon_export(p_actor_admin_id uuid, p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  return jsonb_build_object(
    'format', 'cray-salon-export/1',
    'generated_at', now(),
    'salon', (select jsonb_build_object('display_name', s.display_name, 'legal_name', s.legal_name,
                                         'gst_number', s.gst_number, 'address', s.address)
                from public.salons s where s.id = p_salon_id),
    'customers', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', c.id, 'name', c.name, 'phone', c.phone, 'birthday', c.birthday,
                     'anniversary', c.anniversary, 'last_visit_at', c.last_visit_at,
                     'loyalty_points', c.loyalty_points, 'created_at', c.created_at)
                     order by c.created_at)
                   from public.customers c where c.salon_id = p_salon_id), '[]'),
    'services', coalesce((select jsonb_agg(to_jsonb(x) order by x.name)
                   from public.services x where x.salon_id = p_salon_id), '[]'),
    'bookings', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', b.id, 'customer_id', b.customer_id, 'starts_at', b.starts_at,
                     'status', b.status, 'total_paise', b.total_paise) order by b.starts_at)
                   from public.bookings b where b.salon_id = p_salon_id), '[]'),
    'visits', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', v.id, 'customer_id', v.customer_id, 'completed_at', v.completed_at,
                     'final_amount_paise', v.final_amount_paise, 'tip_paise', v.tip_paise,
                     'payment_status', v.payment_status) order by v.completed_at)
                   from public.visits v where v.salon_id = p_salon_id), '[]'),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', p.id, 'customer_id', p.customer_id, 'visit_id', p.visit_id,
                     'method', p.method, 'amount_paise', p.amount_paise, 'status', p.status,
                     'captured_at', p.captured_at) order by p.created_at)
                   from public.payments p where p.salon_id = p_salon_id), '[]'),
    'wallet_balances', coalesce((select jsonb_agg(jsonb_build_object(
                     'customer_id', w.customer_id, 'balance_paise', w.balance_paise))
                   from public.wallet_accounts w where w.salon_id = p_salon_id), '[]'),
    'wallet_transactions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id)
                   from public.wallet_transactions t where t.salon_id = p_salon_id), '[]')
  );
end;
$$;

-- Recording that the owner was offered it (the console produces the file).
create or replace function app_admin.record_export_offered(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_note           text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'app_admin: say how the export was offered - "emailed to the owner on 3 Jan"';
  end if;

  update public.salons
     set export_offered_at = now(), export_offered_note = btrim(p_note), updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(p_salon_id, p_actor_admin_id, 'salon.export_offered', 'salons',
                          p_salon_id::text, p_note, null, null);
end;
$$;

-- How the salon settled its customers' credit. The ledger is not touched.
create or replace function app_admin.record_credit_settlement(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_note           text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outstanding bigint;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);
  if coalesce(btrim(p_note), '') = '' then
    raise exception
      'app_admin: say how the salon settled its customers'' credit - '
      '"refunded in cash at the counter, list signed by the owner"';
  end if;

  select coalesce(sum(balance_paise), 0) into v_outstanding
    from public.wallet_accounts where salon_id = p_salon_id;

  update public.salons
     set credit_settled_at = now(), credit_settled_note = btrim(p_note), updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(p_salon_id, p_actor_admin_id, 'salon.credit_settled', 'salons',
                          p_salon_id::text, p_note, null,
                          jsonb_build_object('outstanding_paise_in_ledger', v_outstanding));

  return jsonb_build_object('outstanding_paise', v_outstanding);
end;
$$;

-- ---------------------------------------------------------------------------
-- The purge
-- ---------------------------------------------------------------------------

create or replace function app_admin.purge_salon(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_reason         text,
  p_typed_name     text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon       record;
  v_outstanding bigint;
  v_customers   integer;
  v_released    integer;
  v_staff       integer;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a purge needs a reason - it is the audit entry';
  end if;

  select s.id, s.display_name, s.status, s.purged_at, s.export_offered_at, s.credit_settled_at
    into v_salon
    from public.salons s where s.id = p_salon_id for update;

  if v_salon.id is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;
  if v_salon.purged_at is not null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if btrim(coalesce(p_typed_name, '')) <> v_salon.display_name then
    raise exception 'app_admin: type the salon''s display name exactly to confirm the purge';
  end if;
  if app.billing_state(p_salon_id) <> 'purge_due' then
    raise exception
      'app_admin: purge is not due - it comes 90 days after suspension (the state is %)',
      app.billing_state(p_salon_id);
  end if;
  if v_salon.export_offered_at is null then
    raise exception 'app_admin: offer the owner an export of their data first, and record it';
  end if;

  select coalesce(sum(balance_paise), 0) into v_outstanding
    from public.wallet_accounts where salon_id = p_salon_id;
  if v_outstanding > 0 and v_salon.credit_settled_at is null then
    raise exception
      'app_admin: customers still hold % paise of credit at this salon. Record how the salon '
      'settled it first - a salon cannot keep money for services it will never provide',
      v_outstanding;
  end if;

  -- ── Customers: identity goes, the books stay ──────────────────────────────
  update public.customers
     set name = null, phone = null, birthday = null, anniversary = null,
         auth_user_id = null, anonymised_at = coalesce(anonymised_at, now()), updated_at = now()
   where salon_id = p_salon_id;
  get diagnostics v_customers = row_count;

  -- Bindings are RELEASED, recorded like any other unbind.
  insert into public.binding_events (phone_hash, kind, from_salon_id, actor_admin_id, reason)
  select ci.phone_hash, 'unbind', p_salon_id, p_actor_admin_id, 'Salon purged: ' || btrim(p_reason)
    from public.customer_identities ci where ci.salon_id = p_salon_id;
  delete from public.customer_identities where salon_id = p_salon_id;
  get diagnostics v_released = row_count;

  -- ── Operational personal data with no purpose left ────────────────────────
  delete from public.notification_tokens where salon_id = p_salon_id;
  delete from public.notification_deliveries where salon_id = p_salon_id;
  delete from public.notifications where salon_id = p_salon_id;
  delete from public.reminders where salon_id = p_salon_id;
  delete from public.join_intents where salon_id = p_salon_id;
  delete from public.otp_challenges where salon_id = p_salon_id;
  delete from public.booking_start_codes where salon_id = p_salon_id;
  delete from public.customer_service_intervals where salon_id = p_salon_id;
  update public.bookings set notes = null, cancel_reason = null
   where salon_id = p_salon_id and (notes is not null or cancel_reason is not null);

  -- ── Staff: nobody can log in to the archive ───────────────────────────────
  update public.users
     set name = 'Former staff', phone = '', auth_user_id = null, active = false, updated_at = now()
   where salon_id = p_salon_id;
  get diagnostics v_staff = row_count;
  update public.staff set name = 'Former stylist', active = false where salon_id = p_salon_id;

  -- ── Credentials: the salon's accounts are no longer ours to hold ──────────
  delete from vault.secrets
   where id in (select vault_secret_id from public.salon_integrations
                 where salon_id = p_salon_id and vault_secret_id is not null);
  delete from public.salon_integrations where salon_id = p_salon_id;

  -- ── Requests still open are answered, not dropped ─────────────────────────
  update public.data_rights_requests
     set status = 'completed', completed_at = now(), handled_by = p_actor_admin_id,
         outcome = 'The salon closed and its data was purged. Identity erased; financial '
                   'records retained in anonymised form as other law requires.'
   where salon_id = p_salon_id and status in ('open', 'in_progress');

  update public.salons
     set status = 'suspended', purged_at = now(), purged_by = p_actor_admin_id, updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.purged', 'salons', p_salon_id::text, p_reason,
    jsonb_build_object('status', v_salon.status),
    jsonb_build_object('customers_anonymised', v_customers, 'bindings_released', v_released,
                       'staff_closed', v_staff, 'outstanding_credit_paise', v_outstanding,
                       'financial_rows_retained', true));

  return jsonb_build_object('ok', true, 'already', false, 'customers_anonymised', v_customers,
                            'bindings_released', v_released, 'staff_closed', v_staff);
end;
$$;

comment on function app_admin.purge_salon is
  'Offboarding (0089): anonymises every customer and staff member, releases bindings, deletes operational personal data and the salon''s credentials, and KEEPS every financial row. Requires purge_due, a recorded export offer, a recorded credit settlement when credit is outstanding, a super-admin, a reason and the display name typed back.';

-- ---------------------------------------------------------------------------
-- Support mode
-- ---------------------------------------------------------------------------

create table public.support_sessions (
  id         uuid primary key default extensions.gen_random_uuid(),
  salon_id   uuid not null references public.salons(id) on delete cascade,
  admin_id   uuid not null references public.platform_admins(id),
  reason     text not null check (length(btrim(reason)) > 0),
  started_at timestamptz not null default now(),
  ends_at    timestamptz not null,
  ended_at   timestamptz,
  check (ends_at > started_at and ends_at <= started_at + interval '2 hours')
);

create index support_sessions_salon on public.support_sessions (salon_id, admin_id, ends_at desc);

alter table public.support_sessions enable row level security;
alter table public.support_sessions force row level security;
revoke all on public.support_sessions from public, anon, authenticated;

comment on table public.support_sessions is
  'Support mode (0089, RULES 6.8): time-boxed, reason-required. No policies: only app_admin reads or writes it.';

create or replace function app.support_session_live(p_admin uuid, p_salon uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.support_sessions s
   where s.admin_id = p_admin and s.salon_id = p_salon
     and s.ended_at is null and s.ends_at > now()
   order by s.ends_at desc
   limit 1
$$;

revoke all on function app.support_session_live(uuid, uuid) from public, anon, authenticated;

create or replace function app_admin.start_support_session(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_reason         text,
  p_minutes        integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid;
  v_ends timestamptz;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: support mode needs a reason - what is the ticket?';
  end if;
  if p_minutes is null or p_minutes not between 5 and 120 then
    raise exception 'app_admin: a support session lasts 5 to 120 minutes';
  end if;

  -- One live session per operator per salon: starting again returns it.
  v_id := app.support_session_live(p_actor_admin_id, p_salon_id);
  if v_id is not null then
    select ends_at into v_ends from public.support_sessions where id = v_id;
    return jsonb_build_object('session_id', v_id, 'ends_at', v_ends, 'already', true);
  end if;

  insert into public.support_sessions (salon_id, admin_id, reason, ends_at)
  values (p_salon_id, p_actor_admin_id, btrim(p_reason), now() + make_interval(mins => p_minutes))
  returning id, ends_at into v_id, v_ends;

  perform app_admin.audit(p_salon_id, p_actor_admin_id, 'support.started', 'support_sessions',
                          v_id::text, p_reason, null,
                          jsonb_build_object('minutes', p_minutes));

  return jsonb_build_object('session_id', v_id, 'ends_at', v_ends, 'already', false);
end;
$$;

create or replace function app_admin.end_support_session(p_actor_admin_id uuid, p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  update public.support_sessions set ended_at = now()
   where id = p_session_id and admin_id = p_actor_admin_id and ended_at is null
  returning salon_id into v_salon;

  if v_salon is not null then
    perform app_admin.audit(v_salon, p_actor_admin_id, 'support.ended', 'support_sessions',
                            p_session_id::text, null, null, null);
  end if;
end;
$$;

-- The masked view. Read-only, and nothing at all without a live session.
create or replace function app_admin.support_customers(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_search         text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session uuid;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  v_session := app.support_session_live(p_actor_admin_id, p_salon_id);
  if v_session is null then
    raise exception 'app_admin: start a support session with a reason first - it lasts an hour';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'customer_id',    c.id,
             'name',           c.name,
             -- Masked to the last four (RULES 6.8). Un-masking is its own action.
             'phone_last4',    right(coalesce(c.phone, ''), 4),
             'balance_paise',  coalesce(w.balance_paise, 0),
             'last_visit_at',  c.last_visit_at,
             'anonymised',     c.anonymised_at is not null)
           order by c.last_visit_at desc nulls last)
      from (select * from public.customers c
             where c.salon_id = p_salon_id
               and (p_search is null or btrim(p_search) = ''
                    or c.name ilike btrim(p_search) || '%'
                    or right(coalesce(c.phone, ''), 4) = btrim(p_search))
             order by c.last_visit_at desc nulls last
             limit 50) c
      left join public.wallet_accounts w on w.customer_id = c.id), '[]'::jsonb);
end;
$$;

-- Un-masking one number: a separate act, logged separately, with its own reason.
create or replace function app_admin.support_unmask_phone(
  p_actor_admin_id uuid,
  p_customer_id    uuid,
  p_reason         text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon uuid;
  v_phone text;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: un-masking a number needs its own reason';
  end if;

  select salon_id, phone into v_salon, v_phone from public.customers where id = p_customer_id;
  if v_salon is null then
    raise exception 'app_admin: no such customer';
  end if;
  if app.support_session_live(p_actor_admin_id, v_salon) is null then
    raise exception 'app_admin: un-masking is only possible inside a live support session';
  end if;

  perform app_admin.audit(v_salon, p_actor_admin_id, 'support.unmasked_phone', 'customers',
                          p_customer_id::text, p_reason, null, null);
  return v_phone;
end;
$$;

-- Read-only: the sessions on the salon's support page.
create or replace function app_admin.list_support_sessions(p_actor_admin_id uuid, p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_admin.assert_admin(p_actor_admin_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'admin', a.name, 'reason', s.reason, 'started_at', s.started_at,
             'ends_at', s.ends_at, 'ended_at', s.ended_at,
             'live', s.ended_at is null and s.ends_at > now(),
             'mine', s.admin_id = p_actor_admin_id)
           order by s.started_at desc)
      from (select * from public.support_sessions
             where salon_id = p_salon_id order by started_at desc limit 20) s
      join public.platform_admins a on a.id = s.admin_id), '[]'::jsonb);
end;
$$;

select app_admin.close_privileges();
