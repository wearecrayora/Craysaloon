-- 0094 Receipts and invoices (PRD 16A.3, 10.8; RULES 11.12; the last gap in the
-- M13 release audit: "a top-up produces a receipt, not a tax invoice; GST
-- appears on the service invoice").
--
-- Two documents, kept apart on purpose:
--
--   * A wallet TOP-UP gets a RECEIPT, series RCT. It is never labelled or
--     numbered as a tax invoice: salon credit is a voucher, and the top-up is
--     generally not the taxable event (16A.3).
--   * A PAID VISIT gets the service document. For a GST-registered salon that
--     is a TAX INVOICE (series INV) with GST split CGST/SGST; for anyone else a
--     BILL OF SUPPLY (series BOS) with no tax on it.
--
-- Numbers are sequential per salon, per series, per Indian financial year
-- (April-March, in IST), with no gaps: the counter row is incremented in the
-- same transaction as the document, so a rolled-back document rolls back its
-- number too. `RCT/2627/00001` - 14 characters, inside GST's 16.
--
-- Issued by the DATABASE, at commit, whatever path got there. A visit becomes
-- paid three ways today (counter checkout, the customer's wallet, UPI) and will
-- gain more; a trigger on the visit catches all of them, and on a path added
-- next year too. The triggers are DEFERRED constraint triggers because the
-- facts a document needs are written after the row that triggers it: a top-up
-- posts its bonus after its paid credit, and a checkout settles the wallet
-- after it marks the visit paid.
--
-- Both tables are append-only (grant, policy and trigger - as the ledgers) and
-- are never purged: an erased customer's documents stay, against the
-- anonymised id (RULES 11.9). No customer NAME is stored on either: a B2C
-- document below Rs 50,000 needs none, and a name kept here would survive the
-- erasure that anonymises everything else.
--
-- ⚖️ A CA must confirm three things before the first live tax invoice
-- (docs/release/PRD20-audit.md):
--   1. the RATE. It is not defaulted: Crayora sets it per salon, and until it
--      is set a salon issues bills of supply. (Salon and barber services were
--      reportedly moved from 18% to 5% without input tax credit from 22 Sep
--      2025.)
--   2. that menu prices are GST-INCLUSIVE, which is how this computes: the
--      visit's amount is what the customer paid, and the tax is carved out of
--      it, never added on top.
--   3. the BONUS. The invoice taxes the full service value and records how much
--      of it was paid with bonus credit (bonus_paise), so the treatment can be
--      changed on the CA's answer without losing anything.

-- ---------------------------------------------------------------------------
-- GST registration
-- ---------------------------------------------------------------------------

alter table public.salons
  add column gst_rate_bp integer
    check (gst_rate_bp is null or gst_rate_bp in (500, 1200, 1800, 2800, 4000));

comment on column public.salons.gst_rate_bp is
  'GST rate on the salon''s services, in basis points (500 = 5%). Null = not charging GST: the salon issues bills of supply. Set only by Crayora (app_admin.set_salon_gst), on a CA''s advice (0094).';

-- ---------------------------------------------------------------------------
-- Numbering
-- ---------------------------------------------------------------------------

create table public.document_series (
  salon_id    uuid    not null references public.salons(id) on delete restrict,
  series      text    not null check (series in ('RCT', 'INV', 'BOS')),
  fy          text    not null check (fy ~ '^[0-9]{4}$'),
  last_number integer not null check (last_number > 0),
  primary key (salon_id, series, fy)
);

alter table public.document_series enable row level security;
alter table public.document_series force row level security;
revoke all on public.document_series from public, anon, authenticated;

comment on table public.document_series is
  'The last number issued per salon, series and financial year (0094). No policies: only the two issuing functions touch it.';

-- '2627' for any moment in FY 2026-27 (1 Apr 2026 - 31 Mar 2027, IST).
create or replace function app.financial_year(p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(y, 'FM00') || to_char(y + 1, 'FM00')
    from (select (extract(year from local)::int
                  - case when extract(month from local) < 4 then 1 else 0 end) % 100 as y
            from (select p_at at time zone 'Asia/Kolkata' as local) l) f
$$;

create or replace function app.next_document_number(
  p_salon_id uuid,
  p_series   text,
  p_at       timestamptz
)
returns table (number text, fy text, seq integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fy  text := app.financial_year(p_at);
  v_seq integer;
begin
  -- Row-locked increment in the caller's transaction: two documents issued at
  -- once queue on the row, and a rollback returns the number.
  insert into public.document_series as s (salon_id, series, fy, last_number)
  values (p_salon_id, p_series, v_fy, 1)
  on conflict (salon_id, series, fy)
  do update set last_number = s.last_number + 1
  returning s.last_number into v_seq;

  return query select p_series || '/' || v_fy || '/' || to_char(v_seq, 'FM00000'), v_fy, v_seq;
end;
$$;

-- ---------------------------------------------------------------------------
-- The documents
-- ---------------------------------------------------------------------------

create table public.receipts (
  id           uuid        primary key default extensions.gen_random_uuid(),
  salon_id     uuid        not null references public.salons(id) on delete restrict,
  customer_id  uuid        not null references public.customers(id) on delete restrict,
  payment_id   uuid        not null unique references public.payments(id) on delete restrict,
  number       text        not null,
  fy           text        not null,
  seq          integer     not null,
  -- What was paid, and the bonus that came with it - on the receipt, apart,
  -- because they are different things (16A.3).
  paid_paise   bigint      not null check (paid_paise > 0),
  bonus_paise  bigint      not null default 0 check (bonus_paise >= 0),
  issued_at    timestamptz not null default now(),
  unique (salon_id, fy, seq)
);

create table public.invoices (
  id               uuid        primary key default extensions.gen_random_uuid(),
  salon_id         uuid        not null references public.salons(id) on delete restrict,
  customer_id      uuid        not null references public.customers(id) on delete restrict,
  visit_id         uuid        not null unique references public.visits(id) on delete restrict,
  kind             text        not null check (kind in ('tax_invoice', 'bill_of_supply')),
  number           text        not null,
  fy               text        not null,
  seq              integer     not null,
  -- Snapshot of what was done, as it was named and priced when booked.
  lines            jsonb       not null default '[]'::jsonb,
  total_paise      bigint      not null check (total_paise >= 0),
  taxable_paise    bigint      not null check (taxable_paise >= 0),
  cgst_paise       bigint      not null default 0 check (cgst_paise >= 0),
  sgst_paise       bigint      not null default 0 check (sgst_paise >= 0),
  gst_rate_bp      integer,
  gstin            text,
  sac              text        not null default '9997',
  -- How it was paid: wallet paid credit, wallet bonus credit, and the rest.
  wallet_paid_paise  bigint    not null default 0,
  bonus_paise        bigint    not null default 0,
  other_paise        bigint    not null default 0,
  issued_at        timestamptz not null default now(),
  unique (salon_id, kind, fy, seq),
  -- The tax is carved out of the total, never added on top.
  check (taxable_paise + cgst_paise + sgst_paise = total_paise),
  check (kind = 'tax_invoice' or (cgst_paise = 0 and sgst_paise = 0 and gstin is null)),
  check (kind = 'bill_of_supply' or (gstin is not null and gst_rate_bp is not null))
);

create index receipts_customer_idx on public.receipts (salon_id, customer_id, issued_at desc);
create index invoices_customer_idx on public.invoices (salon_id, customer_id, issued_at desc);

alter table public.receipts enable row level security;
alter table public.receipts force row level security;
alter table public.invoices enable row level security;
alter table public.invoices force row level security;

-- Read: the salon's own staff, and a customer their own documents only.
-- Write: nobody - no insert, update or delete policy exists, and the grant is
-- SELECT alone. The issuing functions are definers.
revoke all on public.receipts, public.invoices from public, anon, authenticated;
grant select on public.receipts, public.invoices to authenticated;

create policy receipts on public.receipts
  for select to authenticated
  using (salon_id = app.current_salon_id());
create policy customer_scope on public.receipts
  as restrictive for all to authenticated
  using (app.current_app_role() <> 'customer' or customer_id = app.current_customer_id());

create policy invoices on public.invoices
  for select to authenticated
  using (salon_id = app.current_salon_id());
create policy customer_scope on public.invoices
  as restrictive for all to authenticated
  using (app.current_app_role() <> 'customer' or customer_id = app.current_customer_id());

-- Append-only, the third way: stops even the owner and service_role.
create trigger receipts_append_only
  before update or delete on public.receipts
  for each row execute function app.block_ledger_mutation();
create trigger invoices_append_only
  before update or delete on public.invoices
  for each row execute function app.block_ledger_mutation();

comment on table public.receipts is
  'One per wallet top-up: a RECEIPT, never a tax invoice (RULES 11.12). Append-only, never purged (0094).';
comment on table public.invoices is
  'One per paid visit: a tax invoice for a GST-registered salon, a bill of supply otherwise. Append-only, never purged (0094).';

-- ---------------------------------------------------------------------------
-- Issuing
-- ---------------------------------------------------------------------------

create or replace function app.issue_receipt(p_payment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment record;
  v_bonus   bigint;
  v_doc     record;
  v_id      uuid;
begin
  select id into v_id from public.receipts where payment_id = p_payment_id;
  if v_id is not null then
    return v_id;
  end if;

  select p.id, p.salon_id, p.customer_id, p.amount_paise, p.captured_at
    into v_payment
    from public.payments p
   where p.id = p_payment_id and p.visit_id is null and p.status = 'captured';
  if v_payment.id is null then
    return null; -- not a captured top-up: nothing to receipt
  end if;

  select coalesce(sum(t.amount_paise), 0) into v_bonus
    from public.wallet_transactions t
   where t.payment_id = p_payment_id and t.kind = 'credit_bonus';

  select * into v_doc
    from app.next_document_number(v_payment.salon_id, 'RCT', coalesce(v_payment.captured_at, now()));

  insert into public.receipts (salon_id, customer_id, payment_id, number, fy, seq,
                               paid_paise, bonus_paise, issued_at)
  values (v_payment.salon_id, v_payment.customer_id, p_payment_id, v_doc.number, v_doc.fy,
          v_doc.seq, v_payment.amount_paise, v_bonus, coalesce(v_payment.captured_at, now()))
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function app.issue_invoice(p_visit_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit   record;
  v_salon   record;
  v_lines   jsonb;
  v_items   bigint;
  v_kind    text;
  v_doc     record;
  v_taxable bigint;
  v_tax     bigint;
  v_cgst    bigint := 0;
  v_sgst    bigint := 0;
  v_paid    bigint;
  v_bonus   bigint;
  v_id      uuid;
begin
  select id into v_id from public.invoices where visit_id = p_visit_id;
  if v_id is not null then
    return v_id;
  end if;

  select v.id, v.salon_id, v.customer_id, v.booking_id, v.final_amount_paise
    into v_visit
    from public.visits v
   where v.id = p_visit_id and v.payment_status = 'paid';
  if v_visit.id is null then
    return null; -- not paid: no document yet
  end if;

  select s.gst_number, s.gst_rate_bp into v_salon
    from public.salons s where s.id = v_visit.salon_id;

  -- What was done, as booked. If the owner settled on a different amount at
  -- mark-complete, the difference is its own line rather than a silent edit of
  -- somebody's price.
  select coalesce(jsonb_agg(jsonb_build_object('kind', i.kind, 'name', i.name_snapshot,
                                               'price_paise', i.price_paise)
                            order by (i.kind <> 'service'), i.created_at), '[]'::jsonb),
         coalesce(sum(i.price_paise), 0)
    into v_lines, v_items
    from public.booking_items i
   where i.booking_id = v_visit.booking_id;

  if v_items <> v_visit.final_amount_paise then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'kind', 'adjustment', 'name', null,
      'price_paise', v_visit.final_amount_paise - v_items));
  end if;

  -- GST only for a registered salon with a rate set (see the header's ⚖️).
  if v_salon.gst_number is not null and v_salon.gst_rate_bp is not null then
    v_kind    := 'tax_invoice';
    v_taxable := round(v_visit.final_amount_paise * 10000.0 / (10000 + v_salon.gst_rate_bp));
    v_tax     := v_visit.final_amount_paise - v_taxable;
    v_cgst    := v_tax / 2;
    v_sgst    := v_tax - v_cgst;
  else
    v_kind    := 'bill_of_supply';
    v_taxable := v_visit.final_amount_paise;
  end if;

  -- How the wallet paid, lot by lot (payment_allocations, 0048).
  select coalesce(sum(a.amount_paise) filter (where l.kind = 'paid'), 0),
         coalesce(sum(a.amount_paise) filter (where l.kind = 'bonus'), 0)
    into v_paid, v_bonus
    from public.payments p
    join public.payment_allocations a on a.payment_id = p.id
    join public.wallet_lots l on l.id = a.wallet_lot_id
   where p.visit_id = p_visit_id and p.method = 'wallet'
     and p.status not in ('failed', 'cancelled');

  select * into v_doc
    from app.next_document_number(v_visit.salon_id,
                                  case v_kind when 'tax_invoice' then 'INV' else 'BOS' end,
                                  now());

  insert into public.invoices (salon_id, customer_id, visit_id, kind, number, fy, seq, lines,
                               total_paise, taxable_paise, cgst_paise, sgst_paise,
                               gst_rate_bp, gstin, wallet_paid_paise, bonus_paise, other_paise)
  values (v_visit.salon_id, v_visit.customer_id, p_visit_id, v_kind, v_doc.number, v_doc.fy,
          v_doc.seq, v_lines, v_visit.final_amount_paise, v_taxable, v_cgst, v_sgst,
          case when v_kind = 'tax_invoice' then v_salon.gst_rate_bp end,
          case when v_kind = 'tax_invoice' then v_salon.gst_number end,
          v_paid, v_bonus,
          greatest(v_visit.final_amount_paise - v_paid - v_bonus, 0))
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function app.receipt_on_topup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.issue_receipt(new.payment_id);
  return null;
end;
$$;

create or replace function app.invoice_on_paid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.issue_invoice(new.id);
  return null;
end;
$$;

-- At COMMIT: by then the bonus row is posted and the wallet is settled.
create constraint trigger wallet_topup_receipt
  after insert on public.wallet_transactions
  deferrable initially deferred
  for each row
  when (new.kind = 'credit_topup' and new.payment_id is not null)
  execute function app.receipt_on_topup();

create constraint trigger visit_paid_invoice
  after insert or update of payment_status on public.visits
  deferrable initially deferred
  for each row
  when (new.payment_status = 'paid')
  execute function app.invoice_on_paid();

revoke all on function app.financial_year(timestamptz) from public, anon, authenticated;
revoke all on function app.next_document_number(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function app.issue_receipt(uuid) from public, anon, authenticated;
revoke all on function app.issue_invoice(uuid) from public, anon, authenticated;
revoke all on function app.receipt_on_topup() from public, anon, authenticated;
revoke all on function app.invoice_on_paid() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Setting a salon's GST - Crayora only, audited
-- ---------------------------------------------------------------------------

create or replace function app_admin.set_salon_gst(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_gst_number     text,
  p_rate_bp        integer,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before record;
  v_gstin  text := nullif(upper(btrim(coalesce(p_gst_number, ''))), '');
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: a GST change needs a reason';
  end if;
  -- 2 state digits, PAN (5 letters, 4 digits, 1 letter), entity, Z, check.
  if v_gstin is not null and v_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then
    raise exception 'app_admin: % is not a GSTIN', v_gstin;
  end if;
  if (v_gstin is null) <> (p_rate_bp is null) then
    raise exception 'app_admin: a GST-registered salon needs both a GSTIN and a rate; an unregistered one, neither';
  end if;

  select gst_number, gst_rate_bp into v_before from public.salons where id = p_salon_id;
  if not found then
    raise exception 'app_admin: no such salon';
  end if;

  update public.salons
     set gst_number = v_gstin, gst_rate_bp = p_rate_bp, updated_at = now()
   where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.gst_set', 'salons', p_salon_id::text, p_reason,
    jsonb_build_object('gst_number', v_before.gst_number, 'gst_rate_bp', v_before.gst_rate_bp),
    jsonb_build_object('gst_number', v_gstin, 'gst_rate_bp', p_rate_bp));
end;
$$;

select app_admin.close_privileges();
