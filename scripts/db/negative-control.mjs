// NEGATIVE CONTROL for the cross-tenant leak test.
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

class Rollback extends Error {
  constructor(lines) {
    super('rollback');
    this.lines = lines;
  }
}

const body = await readFile(path.join(ROOT, LEAK_TEST), 'utf8');
const sql = connect(postgres, await requireDatabaseUrl());

async function runLeakTest(withCanary) {
  let lines = [];
  await sql
    .begin(async (tx) => {
      if (withCanary) await tx.unsafe(CANARY);
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

try {
  // 1. Baseline. If the schema is already failing the leak test, this tool
  //    would report a "detection" that is really just the pre-existing
  //    failure, so refuse to draw any conclusion from it.
  const clean = await runLeakTest(false);
  console.log(`baseline (no canary):  ${passes(clean).length} ok, ${failures(clean).length} not ok`);
  if (failures(clean).length > 0) {
    for (const l of failures(clean)) console.log(`  ${l}`);
    console.error(
      '\nThe leak test is already failing without the canary. Fix that first -' +
        '\nuntil it passes clean, this control proves nothing.',
    );
    process.exit(1);
  }

  // 2. Now break the schema on purpose.
  const dirty = await runLeakTest(true);
  console.log(
    `with an unprotected table: ${passes(dirty).length} ok, ${failures(dirty).length} not ok`,
  );
  for (const l of failures(dirty)) console.log(`  ${l}`);

  const undetected = MUST_FAIL.filter((rx) => !failures(dirty).some((l) => rx.test(l)));

  if (undetected.length > 0) {
    console.error('\nNEGATIVE CONTROL FAILED - the leak test did NOT catch an unprotected table.');
    for (const rx of undetected) console.error(`  no failure matched ${rx}`);
    console.error(
      '\nA table with salon_id, no RLS and no policies was visible to the gate' +
        '\nand the gate stayed green. Every isolation guarantee in this repo rests' +
        '\non that test, so treat this as a production defect, not a test defect.',
    );
    process.exit(1);
  }

  console.log('\nNEGATIVE CONTROL PASSED - an unprotected table makes the leak test fail.');
} finally {
  await sql.end({ timeout: 5 });
}
