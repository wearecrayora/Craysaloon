// NEGATIVE CONTROLS for the gates that can silently stop working.
//
// PHASES.md M1 does not say "the leak test passes". It says "a deliberately
// unprotected test table makes it FAIL" - and that is the harder half. A gate
// that has only ever been observed passing is not known to be a gate at all;
// three times in M1 a check turned out to be green because it was doing
// nothing (a leak test that never switched role, a grant assertion that named
// four of twenty tables, a piped step whose exit code came from `tee`).
//
// So: create a table that is deliberately unprotected - it has salon_id, it
// has no RLS, it has no policies, and it is not on the documented exemption
// list - run the real leak test against it, and require that the structural
// assertions go red. If they stay green, the leak test has stopped working and
// this exits non-zero.
//
// Everything runs inside transactions that are always rolled back, so the
// canary never outlives the run even against the shared hosted database.
//
// The same treatment is applied to the admin plane's audit gate, and to
// RULES 8.12 - a function the owner app could call to change a payment key
// must turn the admin-plane gate red. And to the audit gate: an
// app_admin function that mutates without auditing must make it go red,
// because RULES 6.5 is otherwise just a convention that a hurried session can
// forget.
//
//   node scripts/db/negative-control.mjs

import postgres from 'postgres';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { ROOT, requireDatabaseUrl, connect } from './env.mjs';

const CANARY = `
  create table public.leak_canary (
    id       uuid primary key default gen_random_uuid(),
    salon_id uuid not null,
    secret   text
  );
`;

// The two structural assertions that must notice. Matched on their message so
// that renaming an assertion breaks this loudly rather than quietly reducing
// what is being checked.
const MUST_FAIL = [
  /RLS both ENABLED and FORCED/,
  /has policies, or is a documented no-policy table/,
];

const LEAK_TEST = 'supabase/tests/rls/leak_test.sql';
const SCOPE_TEST = 'supabase/tests/rls/customer_scope_test.sql';
const BOOKING_TEST = 'supabase/tests/booking/booking_test.sql';
const MONEY_TEST = 'supabase/tests/money/ledger_test.sql';
const ADMIN_TEST = 'supabase/tests/admin/admin_plane_test.sql';
const REMINDER_TEST = 'supabase/tests/messaging/reminder_test.sql';
const REFERRAL_TEST = 'supabase/tests/growth/referral_test.sql';
const DASHBOARD_TEST = 'supabase/tests/metrics/dashboard_test.sql';

// A new table naming a customer, protected the way EVERY tenant table was
// protected until 0038: one permissive policy scoped to the salon. It looks
// careful and it leaks - a customer reads every row of their salon, because
// permissive policies are OR'd. This is the bug that shipped, reproduced, and
// the customer-scope gate must notice it on the day such a table is added.
const SCOPE_CANARY = `
  create table public.scope_canary (
    id          uuid primary key default gen_random_uuid(),
    salon_id    uuid not null,
    customer_id uuid not null,
    note        text
  );
  alter table public.scope_canary enable row level security;
  alter table public.scope_canary force row level security;
  create policy scope_canary_tenant on public.scope_canary
    for all to authenticated
    using (salon_id = app.current_salon_id())
    with check (salon_id = app.current_salon_id());
  grant select, insert, update, delete on public.scope_canary to authenticated;
`;

const SCOPE_MUST_FAIL = [/every table naming a customer has a RESTRICTIVE policy/];

// Double-booking is prevented by ONE thing: the exclusion constraint
// (ARCHITECTURE 6.5). Drop it and the database will happily seat two people in
// the same chair - a create_booking that "looks fine" in every test that does
// not race. So the booking gate must notice its absence, or it is testing the
// happy path of a mechanism that is no longer there.
const BOOKING_CANARY = `
  alter table public.bookings drop constraint bookings_no_staff_overlap;
`;

const BOOKING_MUST_FAIL = [/cannot be booked twice/];

// RULES 5.2: only five callers may post to a ledger, and exactly one function
// writes the row. The realistic way that breaks is a well-meant helper - "just a
// small function to credit a goodwill amount" - that inserts a ledger row
// directly, skipping the lock, the overdraw check and the balance recompute.
// This is that function. The money gate must go red the day it appears.
const LEDGER_CANARY = `
  create function app.canary_credit_goodwill(p_salon uuid, p_customer uuid, p_paise bigint)
  returns void
  language sql
  security definer
  set search_path = ''
  as $canary$
    insert into public.wallet_transactions
      (salon_id, customer_id, kind, amount_paise, balance_after)
    values (p_salon, p_customer, 'admin_correction', p_paise, p_paise);
  $canary$;
`;

const LEDGER_MUST_FAIL = [/exactly ONE function inserts a wallet ledger row/];

// ARCHITECTURE 6.6: "exactly one reminder per cycle" is the INDEX's promise, not
// the application's. Drop the index and the code reads identically - the
// duplicate only appears when an offline mark-complete replays, which is the
// normal case on salon wifi and the hardest one to reproduce by hand.
const REMINDER_CANARY = `
  drop index public.reminders_one_per_cycle;
`;

const REMINDER_MUST_FAIL = [/replaying the SAME visit schedules nothing new/];

// The ack is the only thing standing between "push, free" and "WhatsApp, billed
// to the salon, on every message". This is the plausible mistake: a sweep that
// escalates on age alone, because acked_at "is usually null anyway".
const ACK_CANARY = `
  create or replace function app.escalate_due_deliveries(p_salon_id uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
  as $canary$
  declare
    v_row record;
    v_escalated integer := 0;
  begin
    for v_row in
      select d.id, d.notification_id, n.category
        from public.notification_deliveries d
        join public.notifications n on n.id = d.notification_id
       where d.salon_id = p_salon_id
         and d.sent_at is not null
         and d.sent_at + app.escalation_window(n.purpose) <= now()
    loop
      insert into public.notification_deliveries
        (salon_id, notification_id, channel, provider_status)
      values (p_salon_id, v_row.notification_id, 'sms', 'queued');
      v_escalated := v_escalated + 1;
    end loop;
    return jsonb_build_object('ok', true, 'escalated', v_escalated, 'exhausted', 0);
  end;
  $canary$;
`;

const ACK_MUST_FAIL = [/an ACKED push escalates nothing/];

// The hole 0066 filled: reminders were scheduled and NOTHING read
// scheduled_for, so every one sat in the table forever. The gate did not notice
// because it asserted the scheduling, beside the code that scheduled. This
// canary removes the sending half and requires the gate to go red - so the day
// somebody "simplifies" the sweep, the reminder loop cannot silently stop.
const SEND_CANARY = `
  create or replace function app.send_due_reminders(p_salon_id uuid, p_limit integer default 200)
  returns jsonb
  language sql
  security definer
  set search_path = ''
  as $canary$
    select jsonb_build_object('ok', true, 'sent', 0, 'opted_out', 0);
  $canary$;
`;

const SEND_MUST_FAIL = [/a reminder that is due becomes a message/];

// RULES 10: a reward releases only after a completed PAID first visit. The
// plausible way that breaks is not malice - it is somebody "fixing" a support
// complaint that rewards were not arriving, by releasing on a completed visit
// instead of a paid one. That pays out for every no-show who was marked done.
const REFERRAL_CANARY = `
  create or replace function app.release_due_referrals(p_salon_id uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
  as $canary$
  declare
    v_ref record;
    v_paid integer := 0;
  begin
    for v_ref in
      select r.id from public.referrals r
       where r.salon_id = p_salon_id and r.status = 'pending_visit'
         and exists (select 1 from public.visits v
                      where v.customer_id = r.referred_customer_id)
    loop
      perform app.referral_release_reward(v_ref.id);
      v_paid := v_paid + 1;
    end loop;
    return jsonb_build_object('ok', true, 'released', v_paid);
  end;
  $canary$;
`;

const REFERRAL_MUST_FAIL = [/a COMPLETED visit releases nothing/];

// The seam. mark_visit_complete calling Automation A is one `perform` line, and
// for three days it was absent - marking a visit complete scheduled no reminder
// and wrote no metric, while both the automation's own gate and the booking gate
// stayed green (0075). This canary removes that line.
const SEAM_CANARY = `
  create or replace function app.on_visit_completed(p_visit_id uuid)
  returns jsonb
  language sql
  security definer
  set search_path = ''
  as $canary$
    select jsonb_build_object('ok', true, 'reminder_id', null);
  $canary$;
`;

const SEAM_MUST_FAIL = [/marking a visit complete SCHEDULES THE REMINDER/];

// PRD 9.5: reconciliation ALERTS on a mismatch rather than silently correcting.
// The day an owner rings to say the bookings card is wrong, the obvious fix is
// to make the nightly job overwrite the stored number with the right one. That
// fix makes every future drift invisible - including the next 0075. This is it.
const HEAL_CANARY = `
  create or replace function app.reconcile_day(p_salon_id uuid, p_day date)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
  as $canary$
  begin
    insert into public.daily_salon_metrics (salon_id, day, bookings)
    select p_salon_id, p_day, count(*)::integer from public.bookings b
     where b.salon_id = p_salon_id and app.salon_day(p_salon_id, b.starts_at) = p_day
    on conflict (salon_id, day) do update set bookings = excluded.bookings;
    return jsonb_build_object('ok', true, 'drifted', false, 'drift', '{}'::jsonb);
  end;
  $canary$;
`;

const HEAL_MUST_FAIL = [/stored number is NOT healed/];

// A function in app_admin that mutates a table and never writes audit_log -
// exactly the mistake RULES 6.5 exists to prevent.
const AUDIT_CANARY = `
  create function app_admin.canary_unaudited_change(p_salon_id uuid)
  returns void
  language sql
  security definer
  set search_path = ''
  as $canary$
    update public.salons set updated_at = now() where id = p_salon_id;
  $canary$;
`;

const ADMIN_MUST_FAIL = [/writes audit_log in the same transaction/];

// RULES 8.12: provider credentials are Crayora's to set, never the salon's. The
// realistic way that breaks is not an attacker - it is a well-meant owner
// feature: a function the owner app can call to "update my Razorpay key".
// This is that function. The admin-plane gate must refuse it.
const CREDENTIAL_CANARY = `
  create function public.canary_update_my_payment_key(p_key text)
  returns void
  language sql
  security definer
  set search_path = ''
  as $canary$
    update public.salon_integrations set last4 = right(p_key, 4)
     where salon_id = app.current_salon_id() and provider = 'razorpay';
  $canary$;
  grant execute on function public.canary_update_my_payment_key(text) to authenticated;
`;

const CREDENTIAL_MUST_FAIL = [/no function a salon can call touches provider credentials/];

// The start code (0084) proves one thing: the customer is in the chair. A
// start_service that stops comparing the code still starts every service, so
// nothing on the salon floor would notice. This is that function.
const START_TEST = 'supabase/tests/booking/start_and_pay_test.sql';
const START_CANARY = `
  do $canary$
  declare
    v_def text;
    v_new text;
  begin
    select pg_get_functiondef('public.start_service(uuid, uuid, text)'::regprocedure) into strict v_def;
    v_new := replace(v_def, 'elsif btrim(p_code) <> v_code.code then', 'elsif false then');
    if v_new = v_def then raise exception 'start canary: the code comparison moved'; end if;
    execute v_new;
  end;
  $canary$;
`;

const START_MUST_FAIL = [/a wrong code is refused/];

// A haircut paid by UPI is a payment for a haircut, not wallet credit (0085).
// Before 0085 every captured payment was a top-up, so the old branch-free
// capture is the natural thing to "restore" - and it would hand the customer
// the bill back as spendable credit, with a bonus on top.
const BILL_CREDIT_CANARY = `
  do $canary$
  declare
    v_oid oid;
    v_def text;
    v_new text;
  begin
    select p.oid into strict v_oid from pg_proc p
     where p.proname = 'record_payment_captured' and p.pronamespace = 'app'::regnamespace;
    v_def := pg_get_functiondef(v_oid);
    v_new := replace(v_def, 'if v_payment.visit_id is not null then', 'if false then');
    if v_new = v_def then raise exception 'bill canary: the visit branch moved'; end if;
    execute v_new;
  end;
  $canary$;
`;

const BILL_CREDIT_MUST_FAIL = [/credits NOTHING to the wallet/];


class Rollback extends Error {
  constructor(lines) {
    super('rollback');
    this.lines = lines;
  }
}

const sql = connect(postgres, await requireDatabaseUrl());

async function runTest(testPath, canarySql) {
  const body = await readFile(path.join(ROOT, testPath), 'utf8');
  let lines = [];
  await sql
    .begin(async (tx) => {
      if (canarySql) await tx.unsafe(canarySql);
      const rows = await tx.unsafe(body);
      const flat = Array.isArray(rows[0]) ? rows.flat() : rows;
      lines = flat.map((r) => Object.values(r)[0]).filter((v) => typeof v === 'string');
      throw new Rollback(lines);
    })
    .catch((e) => {
      if (!(e instanceof Rollback)) throw e;
    });
  return lines;
}

const failures = (lines) => lines.filter((l) => /^not ok/.test(l));
const passes = (lines) => lines.filter((l) => /^ok /.test(l));

async function check(label, testPath, canarySql, mustFail) {
  const clean = await runTest(testPath, null);
  console.log(`\n${label}`);
  console.log(`  baseline:      ${passes(clean).length} ok, ${failures(clean).length} not ok`);

  // If the gate is already failing, any "detection" below is really just the
  // pre-existing failure, so refuse to draw a conclusion from it.
  if (failures(clean).length > 0) {
    for (const l of failures(clean)) console.log(`    ${l}`);
    console.error(`  ${label} is already failing without a canary. Fix that first.`);
    return false;
  }

  const dirty = await runTest(testPath, canarySql);
  console.log(`  with canary:   ${passes(dirty).length} ok, ${failures(dirty).length} not ok`);
  for (const l of failures(dirty)) console.log(`    ${l}`);

  const undetected = mustFail.filter((rx) => !failures(dirty).some((l) => rx.test(l)));
  if (undetected.length > 0) {
    console.error(`  ${label} did NOT catch the canary:`);
    for (const rx of undetected) console.error(`    no failure matched ${rx}`);
    return false;
  }
  return true;
}

try {
  const results = [
    await check(
      'leak test / an unprotected tenant table',
      LEAK_TEST,
      CANARY,
      MUST_FAIL,
    ),
    await check(
      'admin plane / an app_admin function that mutates without auditing',
      ADMIN_TEST,
      AUDIT_CANARY,
      ADMIN_MUST_FAIL,
    ),
    await check(
      'credentials / an owner-callable function that changes a payment key',
      ADMIN_TEST,
      CREDENTIAL_CANARY,
      CREDENTIAL_MUST_FAIL,
    ),
    await check(
      'customer scope / a new customer table protected only by salon_id',
      SCOPE_TEST,
      SCOPE_CANARY,
      SCOPE_MUST_FAIL,
    ),
    await check(
      'booking / the exclusion constraint that prevents double-booking, removed',
      BOOKING_TEST,
      BOOKING_CANARY,
      BOOKING_MUST_FAIL,
    ),
    await check(
      'money / a second function that writes a ledger row directly',
      MONEY_TEST,
      LEDGER_CANARY,
      LEDGER_MUST_FAIL,
    ),
    await check(
      'reminders / the one-per-cycle index, dropped',
      REMINDER_TEST,
      REMINDER_CANARY,
      REMINDER_MUST_FAIL,
    ),
    await check(
      'messaging / an escalation sweep that ignores the ack',
      REMINDER_TEST,
      ACK_CANARY,
      ACK_MUST_FAIL,
    ),
    await check(
      'reminders / a sweep that schedules them and never sends them',
      REMINDER_TEST,
      SEND_CANARY,
      SEND_MUST_FAIL,
    ),
    await check(
      'referrals / a reward released on a COMPLETED visit rather than a paid one',
      REFERRAL_TEST,
      REFERRAL_CANARY,
      REFERRAL_MUST_FAIL,
    ),
    await check(
      'automations / mark-complete that runs no automation at all',
      BOOKING_TEST,
      SEAM_CANARY,
      SEAM_MUST_FAIL,
    ),
    await check(
      'metrics / a reconciliation that heals drift instead of reporting it',
      DASHBOARD_TEST,
      HEAL_CANARY,
      HEAL_MUST_FAIL,
    ),
    await check(
      'start code / a start_service that accepts any code',
      START_TEST,
      START_CANARY,
      START_MUST_FAIL,
    ),
    await check(
      'bills / a captured bill payment that credits the wallet',
      START_TEST,
      BILL_CREDIT_CANARY,
      BILL_CREDIT_MUST_FAIL,
    ),
  ];

  if (results.every(Boolean)) {
    console.log('\nNEGATIVE CONTROLS PASSED - every gate goes red when it should.');
  } else {
    console.error(
      '\nNEGATIVE CONTROL FAILED. A gate stayed green while the thing it exists' +
        '\nto catch was present. Treat this as a production defect, not a test' +
        '\ndefect: every guarantee resting on that gate is currently unverified.',
    );
    process.exitCode = 1;
  }
} finally {
  await sql.end({ timeout: 5 });
}
