// STATIC ANALYSIS of every plpgsql function in the schema.
//
// PostgreSQL does not check a plpgsql body at CREATE time. It checks syntax and
// stops - so a function that selects a column which does not exist, or assigns
// a text to an integer, is accepted happily and fails the first time that line
// is reached. In M8 that happened three times in one session:
//
//   * `booking_items.service_id`   - the table has kind/ref_id
//   * `customers.last_visit`       - the column is last_visit_at
//   * `sample_n` written as gaps   - the check constraint counts visits
//
// All three applied cleanly. All three would have failed at the first
// mark-complete in production, which is the one action that must work offline.
// The gate caught them, but only because a test happened to exercise that path;
// a function with no test would have shipped.
//
// `plpgsql_check` removes the "happened to" - it walks every statement in every
// body and resolves every identifier against the live catalog. That is the
// mechanism the mistake deserves, rather than a resolution to be careful.
//
//   node scripts/db/plpgsql-check.mjs
//
// The extension is created inside a transaction that is always rolled back, so
// this never changes the schema it is checking - including on the shared hosted
// database.

import postgres from 'postgres';
import { requireDatabaseUrl, connect } from './env.mjs';

// Levels worth failing on. `warning_extra` is deliberately excluded: it flags
// shadowed variables and unused parameters, which are style, not defects.
const FATAL = new Set(['error']);

// Functions that cannot be checked meaningfully, with the reason. Empty on
// purpose - an entry here is a hole in the analysis and must be argued for.
const EXEMPT = new Map();

const sql = connect(postgres, await requireDatabaseUrl());

try {
  await sql.begin(async (tx) => {
    await tx`create extension if not exists plpgsql_check`;

    // A TRIGGER function cannot be analysed on its own - NEW and OLD have no
    // shape without a table - so each one is checked against the relation it is
    // actually attached to. A trigger function attached to nothing is reported
    // rather than skipped: it is dead code at best.
    const targets = await tx`
      select n.nspname as schema,
             p.proname as name,
             p.oid::regprocedure::text as signature,
             (p.prorettype = 'trigger'::regtype) as is_trigger,
             (select min(t.tgrelid::regclass::text)
                from pg_trigger t where t.tgfoid = p.oid and not t.tgisinternal) as relation
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        join pg_language l on l.oid = p.prolang
       where n.nspname in ('app', 'app_admin', 'public')
         and l.lanname = 'plpgsql'
         and p.prokind = 'f'
       order by n.nspname, p.proname`;

    console.log(`Checking ${targets.length} plpgsql functions in app, app_admin and public.\n`);

    let failures = 0;
    let checked = 0;

    for (const target of targets) {
      if (target.is_trigger && !target.relation) {
        console.error(
          `  ERROR ${target.signature}: a trigger function attached to no table - ` +
            'dead code at best, and unanalysable either way',
        );
        failures++;
        continue;
      }

      if (EXEMPT.has(target.signature)) {
        console.log(`  skip  ${target.signature} - ${EXEMPT.get(target.signature)}`);
        continue;
      }

      let issues;
      try {
        // Each check gets its own savepoint. Without one, the FIRST function
        // that the checker cannot analyse aborts the transaction and every
        // function after it reports the same meaningless cascade - which is
        // exactly what this script did on its first run.
        issues = await tx.savepoint((sp) =>
          target.is_trigger
            ? sp`
                select level, message, lineno, statement, query
                  from plpgsql_check_function_tb(${target.signature}::regprocedure,
                                                 ${target.relation}::regclass)`
            : sp`
                select level, message, lineno, statement, query
                  from plpgsql_check_function_tb(${target.signature}::regprocedure)`,
        );
      } catch (error) {
        // A function the checker itself cannot analyse is reported, never
        // silently passed: an unchecked function is the case this exists for.
        console.error(`  ERROR ${target.signature}: ${error.message}`);
        failures++;
        continue;
      }

      checked++;
      const fatal = issues.filter((i) => FATAL.has(i.level));
      const other = issues.filter((i) => !FATAL.has(i.level));

      if (fatal.length > 0) {
        failures++;
        console.error(`\n  ${target.signature}`);
        for (const issue of fatal) {
          console.error(`    ${issue.level} at line ${issue.lineno ?? '?'}: ${issue.message}`);
          if (issue.statement) console.error(`      in: ${issue.statement}`);
          if (issue.query) console.error(`      query: ${issue.query}`);
        }
      } else if (other.length > 0) {
        console.log(`  warn  ${target.signature}`);
        for (const issue of other) {
          console.log(`          ${issue.level}: ${issue.message}`);
        }
      }
    }

    console.log(`\n${checked} functions analysed.`);

    if (failures > 0) {
      console.error(
        `\nPLPGSQL CHECK FAILED - ${failures} function(s) reference something that does not\n` +
          'exist, or use it wrongly. PostgreSQL accepted them at CREATE time and would have\n' +
          'failed at the first call, in production, on the path nobody tested by hand.',
      );
      process.exitCode = 1;
    } else {
      console.log('PLPGSQL CHECK PASSED - every body resolves against the live catalog.');
    }

    // The extension was only ever needed for the duration of the check.
    throw new Rollback();
  }).catch((error) => {
    if (!(error instanceof Rollback)) throw error;
  });
} finally {
  await sql.end({ timeout: 5 });
}

/** Rolls the transaction back without turning a clean run into a failure. */
function Rollback() {}
Rollback.prototype = Object.create(Error.prototype);
