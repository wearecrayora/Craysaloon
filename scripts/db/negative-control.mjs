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
// The same treatment is applied to the admin plane's audit gate: an
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
const ADMIN_TEST = 'supabase/tests/admin/admin_plane_test.sql';

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
  ];

  if (results.every(Boolean)) {
    console.log('\nNEGATIVE CONTROLS PASSED - both gates go red when they should.');
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
