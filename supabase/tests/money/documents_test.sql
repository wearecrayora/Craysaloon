-- RELEASE GATE: receipts and invoices (0094; PRD 16A.3, RULES 11.12)
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- A top-up gets a RECEIPT and never a tax invoice; a paid visit gets a TAX
-- INVOICE (GST-registered salon) or a BILL OF SUPPLY (anyone else); numbers run
-- per salon, per series, per financial year, with no gaps; and nothing issued
-- can be changed or taken back.
--
-- The issuing triggers are DEFERRED to commit, and this file runs inside one
-- transaction that is rolled back, so no commit ever comes. Instead, after
-- each action it FLUSHES them - `set constraints all immediate` fires every
-- pending deferred trigger right there, exactly as a commit would, and
-- `deferred` puts them back. Not "immediate" throughout: that fires each
-- trigger at the end of the statement INSIDE the function, before the rest
-- of the function has run - which is not what a commit sees, and is how a
-- first draft of this test put a Rs 0 bonus on a receipt.

select plan(26);

-- ---------------------------------------------------------------------------
-- The financial year, in IST
-- ---------------------------------------------------------------------------

select is(app.financial_year('2027-03-31 23:59:00+05:30'), '2627',
  'the last minute of March, IST, is still FY 2026-27');
select is(app.financial_year('2027-03-31 19:00:00+00'), '2728',
  'but 19:00 UTC on 31 March is already 1 April in India - FY 2027-28');
select is(app.financial_year('2026-04-01 00:00:00+05:30'), '2627',
  'the first minute of April starts the year');

-- ---------------------------------------------------------------------------
-- Fixtures: two salons, neither GST-registered yet
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('dddddddd-aaaa-4000-8000-00000000000a'),
  ('dddddddd-aaaa-4000-8000-00000000000b'),
  ('dddddddd-aaaa-4000-8000-00000000000f');

insert into public.platform_admins (id, email, name, is_super, active)
values ('dddddddd-aaaa-4000-8000-00000000000f', 'docs@crayora.test', 'Docs Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at, wallet_rule)
values
  ('dddddddd-0000-4000-8000-000000000001', 'Docs Salon Ltd', 'Docs Salon', 'CRAY-DDKQ22',
   'active', 'dddddddd-aaaa-4000-8000-00000000000f', now(),
   '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 10000}'::jsonb),
  ('dddddddd-0000-4000-8000-000000000002', 'Other Salon Ltd', 'Other Salon', 'CRAY-DDKQ33',
   'active', 'dddddddd-aaaa-4000-8000-00000000000f', now(),
   '{"topup_paise": 50000, "bonus_paise": 5000, "min_topup_paise": 10000}'::jsonb);

insert into public.customers (id, salon_id, auth_user_id, name, phone_hash)
values
  ('dddddddd-1111-4000-8000-00000000000a', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-aaaa-4000-8000-00000000000a', 'Docs A', app.phone_hash('9733300011')),
  ('dddddddd-1111-4000-8000-00000000000b', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-aaaa-4000-8000-00000000000b', 'Docs B', app.phone_hash('9733300012')),
  ('dddddddd-1111-4000-8000-00000000000c', 'dddddddd-0000-4000-8000-000000000002',
   null, 'Other C', app.phone_hash('9733300013'));

insert into public.staff (id, salon_id, name, active)
values ('dddddddd-3333-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001',
        'Docs stylist', true);

-- ---------------------------------------------------------------------------
-- Top-ups: a RECEIPT, never an invoice
-- ---------------------------------------------------------------------------

insert into public.payments (id, salon_id, customer_id, method, amount_paise, status, captured_at)
values
  ('dddddddd-7777-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-1111-4000-8000-00000000000a', 'upi', 50000, 'captured', now()),
  ('dddddddd-7777-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001',
   'dddddddd-1111-4000-8000-00000000000b', 'upi', 20000, 'captured', now()),
  ('dddddddd-7777-4000-8000-000000000003', 'dddddddd-0000-4000-8000-000000000002',
   'dddddddd-1111-4000-8000-00000000000c', 'upi', 50000, 'captured', now());

select app.wallet_credit_from_payment('dddddddd-7777-4000-8000-000000000001');
select app.wallet_credit_from_payment('dddddddd-7777-4000-8000-000000000002');
select app.wallet_credit_from_payment('dddddddd-7777-4000-8000-000000000003');
set constraints all immediate;
set constraints all deferred;

select is(
  (select number from public.receipts where payment_id = 'dddddddd-7777-4000-8000-000000000001'),
  'RCT/' || app.financial_year(now()) || '/00001',
  'a top-up gets receipt RCT/<fy>/00001 - a receipt series, never INV');

select is(
  (select array[paid_paise, bonus_paise] from public.receipts
    where payment_id = 'dddddddd-7777-4000-8000-000000000001'),
  array[50000::bigint, 5000::bigint],
  'the receipt shows the paid amount and the bonus apart - the bonus posted AFTER the credit is on it');

select is(
  (select seq from public.receipts where payment_id = 'dddddddd-7777-4000-8000-000000000002'),
  2, 'the next top-up at the same salon is number 2 - no gap');

select is(
  (select seq from public.receipts where payment_id = 'dddddddd-7777-4000-8000-000000000003'),
  1, 'another salon counts from 1 - numbering is per salon');

select is((select count(*)::int from public.invoices), 0,
  'no top-up produced a tax invoice, or any invoice (RULES 11.12)');

select is(
  (select app.issue_receipt('dddddddd-7777-4000-8000-000000000001')),
  (select id from public.receipts where payment_id = 'dddddddd-7777-4000-8000-000000000001'),
  'issuing again returns the same receipt - one per payment, however often asked');

-- ---------------------------------------------------------------------------
-- A paid visit at an UNREGISTERED salon: a bill of supply, no tax
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status, total_paise)
values ('dddddddd-4444-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001',
        'dddddddd-1111-4000-8000-00000000000a', 'dddddddd-3333-4000-8000-000000000001',
        now() - interval '1 hour', now() - interval '15 minutes', 'completed', 45000);

insert into public.booking_items (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
values
  ('dddddddd-4444-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001', 'service',
   extensions.gen_random_uuid(), 'Haircut', 30000, 30),
  ('dddddddd-4444-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001', 'add_on',
   extensions.gen_random_uuid(), 'Head massage', 15000, 15);

insert into public.visits (id, salon_id, booking_id, customer_id, staff_id, final_amount_paise, completed_at)
values ('dddddddd-5555-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001',
        'dddddddd-4444-4000-8000-000000000001', 'dddddddd-1111-4000-8000-00000000000a',
        'dddddddd-3333-4000-8000-000000000001', 45000, now());
set constraints all immediate;
set constraints all deferred;

select is((select count(*)::int from public.invoices), 0,
  'completing a visit issues nothing - only PAYING does');

-- Settled the way the counter does it: the wallet first (Rs 550: Rs 50 bonus,
-- Rs 500 paid), which covers the whole Rs 450.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-aaaa-4000-8000-00000000000f","app_role":"owner",'
  '"salon_id":"dddddddd-0000-4000-8000-000000000001"}', true);
select public.checkout_visit('dddddddd-5555-4000-8000-000000000001',
                             'dddddddd-9999-4000-8000-000000000001', true, 'cash');
reset role;
set constraints all immediate;
set constraints all deferred;

select is(
  (select array[kind, number] from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000001'),
  array['bill_of_supply', 'BOS/' || app.financial_year(now()) || '/00001'],
  'an unregistered salon issues a BILL OF SUPPLY, in its own series');

select is(
  (select array[total_paise, taxable_paise, cgst_paise, sgst_paise] from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000001'),
  array[45000, 45000, 0, 0]::bigint[],
  'and charges no GST');

select is(
  (select array[bonus_paise, wallet_paid_paise, other_paise] from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000001'),
  array[5000, 40000, 0]::bigint[],
  'the document records how much was paid with BONUS credit, apart (16A.3, the CA''s question)');

select is(
  (select jsonb_array_length(lines) from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000001'),
  2, 'the lines are what was booked - no adjustment line when the amount matches');

update public.visits set payment_status = 'paid'
 where id = 'dddddddd-5555-4000-8000-000000000001';
set constraints all immediate;
set constraints all deferred;
select is(
  (select count(*)::int from public.invoices where visit_id = 'dddddddd-5555-4000-8000-000000000001'),
  1, 'a visit marked paid twice still has ONE document');

-- ---------------------------------------------------------------------------
-- GST registration: Crayora only, validated, audited
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_admin.set_salon_gst('dddddddd-aaaa-4000-8000-00000000000f',
      'dddddddd-0000-4000-8000-000000000001', 'NOTAGSTIN', 500, 'CA advice')$$,
  null, null, 'a malformed GSTIN is refused');

select throws_ok(
  $$select app_admin.set_salon_gst('dddddddd-aaaa-4000-8000-00000000000f',
      'dddddddd-0000-4000-8000-000000000001', '29ABCDE1234F1Z5', null, 'CA advice')$$,
  null, null, 'a GSTIN without a rate is refused - registered means both');

select lives_ok(
  $$select app_admin.set_salon_gst('dddddddd-aaaa-4000-8000-00000000000f',
      'dddddddd-0000-4000-8000-000000000001', '29abcde1234f1z5', 500, 'CA confirmed 5% without ITC')$$,
  'a valid GSTIN and rate are accepted');

select is(
  (select count(*)::int from public.audit_log
    where action = 'salon.gst_set' and salon_id = 'dddddddd-0000-4000-8000-000000000001'),
  1, 'and the change is audited');

-- ---------------------------------------------------------------------------
-- A paid visit at a REGISTERED salon: a tax invoice, GST carved out
-- ---------------------------------------------------------------------------

insert into public.bookings (id, salon_id, customer_id, staff_id, starts_at, ends_at, status, total_paise)
values ('dddddddd-4444-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001',
        'dddddddd-1111-4000-8000-00000000000b', 'dddddddd-3333-4000-8000-000000000001',
        now() - interval '3 hours', now() - interval '2 hours', 'completed', 30000);

insert into public.booking_items (booking_id, salon_id, kind, ref_id, name_snapshot, price_paise, duration_minutes)
values ('dddddddd-4444-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001', 'service',
        extensions.gen_random_uuid(), 'Haircut', 30000, 30);

-- The owner settled on Rs 450 for a Rs 300 booking: the difference is a line.
insert into public.visits (id, salon_id, booking_id, customer_id, staff_id, final_amount_paise,
                           completed_at, payment_status)
values ('dddddddd-5555-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000001',
        'dddddddd-4444-4000-8000-000000000002', 'dddddddd-1111-4000-8000-00000000000b',
        'dddddddd-3333-4000-8000-000000000001', 45000, now(), 'paid');
set constraints all immediate;
set constraints all deferred;

select is(
  (select array[kind, number, gstin] from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000002'),
  array['tax_invoice', 'INV/' || app.financial_year(now()) || '/00001', '29ABCDE1234F1Z5'],
  'a registered salon issues a TAX INVOICE, INV series, carrying its GSTIN');

-- Rs 450 inclusive at 5%: taxable 42857 (450/1.05 = 428.571...), tax 2143,
-- split 1071 CGST + 1072 SGST - to the paisa, summing back exactly.
select is(
  (select array[total_paise, taxable_paise, cgst_paise, sgst_paise] from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000002'),
  array[45000, 42857, 1071, 1072]::bigint[],
  'GST is CARVED OUT of the price the customer paid, never added on top');

select is(
  (select lines -> 1 ->> 'kind' from public.invoices
    where visit_id = 'dddddddd-5555-4000-8000-000000000002'),
  'adjustment',
  'a settled amount that differs from the booking shows as its own line, not an edited price');

-- ---------------------------------------------------------------------------
-- Nothing issued can change
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update public.invoices set total_paise = 1 where visit_id = 'dddddddd-5555-4000-8000-000000000002'$$,
  '23001', null, 'an invoice cannot be edited - not even by the owner of the table');

select throws_ok(
  $$delete from public.receipts where payment_id = 'dddddddd-7777-4000-8000-000000000001'$$,
  '23001', null, 'nor a receipt deleted');

-- ---------------------------------------------------------------------------
-- A customer reads their own documents, and only those
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"dddddddd-aaaa-4000-8000-00000000000a","app_role":"customer",'
  '"salon_id":"dddddddd-0000-4000-8000-000000000001"}', true);

select is(
  (select count(*)::int from public.receipts) + (select count(*)::int from public.invoices),
  2, 'customer A sees their own receipt and their own bill - and not B''s');

select throws_ok(
  $$insert into public.receipts (salon_id, customer_id, payment_id, number, fy, seq, paid_paise)
    values ('dddddddd-0000-4000-8000-000000000001', 'dddddddd-1111-4000-8000-00000000000a',
            'dddddddd-7777-4000-8000-000000000002', 'RCT/0000/99999', '0000', 99999, 1)$$,
  '42501', null, 'and cannot write one');

reset role;
select * from finish();
