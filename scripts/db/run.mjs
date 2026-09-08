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

import postgres from 'postgres';
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '../..');

async function loadEnv() {
  // CI points DATABASE_URL at a local Supabase stack and has no .env, so the
  // environment always wins and a missing file is not an error there.
  const file = path.join(ROOT, '.env');
  if (!existsSync(file)) return { ...process.env };
  const env = {};
  for (const line of (await readFile(file, 'utf8')).split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
  // Environment beats .env: CI overrides without editing anything.
  return { ...env, ...process.env };
}

function connect(url) {
  return postgres(url, {
    max: 1,
    // Migrations contain multi-statement DDL; prepared statements would break
    // it, and the pooler does not support them anyway.
    prepare: false,
    idle_timeout: 20,
    connect_timeout: 30,
    onnotice: () => {},
  });
}

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
const env = await loadEnv();
const url = env.DATABASE_URL;

if (!url) {
  console.error(
    'DATABASE_URL is not set in .env.\n' +
      'Supabase dashboard > Project Settings > Database > Connection string > URI.\n' +
      'Use the DIRECT connection (port 5432) - the transaction pooler does not\n' +
      'support all the DDL these migrations need.',
  );
  process.exit(1);
}

const sql = connect(url);
try {
  if (command === 'migrate') await migrate(sql);
  else if (command === 'test') await runTests(sql);
  else if (command === 'sql') console.table(await sql.unsafe(arg));
  else {
    console.error('usage: node run.mjs migrate | test | sql "<statement>"');
    process.exit(1);
  }
} finally {
  await sql.end({ timeout: 5 });
}
