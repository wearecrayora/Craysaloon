// Apply migrations and run pgTAP against the HOSTED Supabase project.
//
// Development runs against the hosted project - no Docker, no local stack
// (PHASES.md option A). `supabase test db` shells out to Docker for pg_prove,
// so this exists instead: pgTAP tests are just SQL that returns TAP rows, and
// nothing about that needs a container.
//
//   node run.mjs migrate      apply every migration, in order, each in a txn
//   node run.mjs test         run every supabase/tests/**/*.sql, report TAP
//   node run.mjs sql "..."    one-off statement
//
// Reads DATABASE_URL from the repo .env. Never prints it.
//
// THE ledger is public.schema_migrations, written here. `supabase db push`
// keeps its own in supabase_migrations.schema_migrations; running both would
// mean two disagreeing records of what has been applied, so db-push.sh
// delegates to this file rather than to the CLI.

import postgres from 'postgres';
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { ROOT, requireDatabaseUrl, connect } from './env.mjs';

// --- migrate ---------------------------------------------------------------

async function migrate(sql) {
  const dir = path.join(ROOT, 'supabase/migrations');
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();

  await sql`
    create table if not exists public.schema_migrations (
      version     text primary key,
      applied_at  timestamptz not null default now()
    )`;

  const applied = new Set(
    (await sql`select version from public.schema_migrations`).map((r) => r.version),
  );

  let ran = 0;
  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    if (applied.has(version)) {
      console.log(`  skip   ${file}`);
      continue;
    }
    const body = await readFile(path.join(dir, file), 'utf8');
    process.stdout.write(`  apply  ${file} ... `);
    try {
      // Each migration is one transaction: a failure leaves nothing behind.
      await sql.begin(async (tx) => {
        await tx.unsafe(body);
        await tx`insert into public.schema_migrations (version) values (${version})`;
      });
      console.log('ok');
      ran++;
    } catch (error) {
      console.log('FAILED');
      console.error(`\n  ${error.message}`);
      if (error.position) {
        const upto = body.slice(0, Number(error.position));
        console.error(`  at line ${upto.split('\n').length}`);
      }
      throw new Error(`Migration ${file} failed - nothing from it was applied.`);
    }
  }
  console.log(`\n${ran} applied, ${files.length - ran} already present.`);
}

// --- test ------------------------------------------------------------------

async function collectTests(dir, out = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) await collectTests(full, out);
    else if (entry.name.endsWith('.sql')) out.push(full);
  }
  return out.sort();
}

async function runTests(sql) {
  const dir = path.join(ROOT, 'supabase/tests');
  if (!existsSync(dir)) {
    console.log('No supabase/tests yet.');
    return;
  }
  const files = await collectTests(dir);
  if (files.length === 0) {
    console.log('No pgTAP tests yet.');
    return;
  }

  let failed = 0;
  for (const file of files) {
    const name = path.relative(ROOT, file);
    console.log(`\n--- ${name}`);
    const body = await readFile(file, 'utf8');
    try {
      // Roll every test back: tests seed two salons and must not leave them
      // behind in a shared hosted database.
      let lines = [];
      await sql
        .begin(async (tx) => {
          const rows = await tx.unsafe(body);
          const flat = Array.isArray(rows[0]) ? rows.flat() : rows;
          lines = flat.map((r) => Object.values(r)[0]).filter((v) => typeof v === 'string');
          throw new RollbackAfterTest(lines);
        })
        .catch((e) => {
          if (e instanceof RollbackAfterTest) return;
          throw e;
        });

      for (const line of lines) console.log(`  ${line}`);
      const bad = lines.filter((l) => /^not ok/.test(l));
      if (bad.length) failed += bad.length;
    } catch (error) {
      console.error(`  ERROR: ${error.message}`);
      failed++;
    }
  }

  console.log(failed === 0 ? '\nALL TESTS PASS' : `\n${failed} FAILURE(S)`);
  if (failed) process.exitCode = 1;
}

class RollbackAfterTest extends Error {
  constructor(lines) {
    super('rollback');
    this.lines = lines;
  }
}

// --- main ------------------------------------------------------------------

const [command, arg] = process.argv.slice(2);
const sql = connect(postgres, await requireDatabaseUrl());

try {
  if (command === 'migrate') await migrate(sql);
  else if (command === 'test') await runTests(sql);
  else if (command === 'sql') console.table(await sql.unsafe(arg));
  else if (command === 'file') {
    // Run a whole .sql file outside the migration ledger - used by CI to
    // bootstrap the roles and auth schema the image does not ship.
    const body = await readFile(path.join(ROOT, arg), 'utf8');
    await sql.unsafe(body);
    console.log(`applied ${arg}`);
  } else {
    console.error('usage: node run.mjs migrate | test | sql "<statement>" | file <path.sql>');
    process.exit(1);
  }
} finally {
  await sql.end({ timeout: 5 });
}
