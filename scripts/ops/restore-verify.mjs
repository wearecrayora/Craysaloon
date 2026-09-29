// RESTORE DRILL - verify that a restored copy of the database is the database.
//
// "An untested backup is not a backup" (ARCHITECTURE 16). Run by
// .github/workflows/restore-drill.yml, in two halves:
//
//   node scripts/ops/restore-verify.mjs snapshot   (against SOURCE_DB_URL, just
//                                                   before the dump is taken)
//   node scripts/ops/restore-verify.mjs verify     (against TARGET_DB_URL, after
//                                                   the restore)
//
// What "the restore worked" means here, checked rather than assumed:
//   1. every table in public/app/app_admin exists in the copy;
//   2. the money and identity tables hold EXACTLY the rows they held at the
//      snapshot - these change only by a person's action, never by a timer;
//   3. append-only tables hold at least what they held (a scheduled job may
//      add rows between the snapshot and the dump; nothing may remove them);
//   4. RLS is enabled AND forced on every table that has it at the source -
//      a restore that drops FORCE is a restore that leaks;
//   5. every wallet balance still equals the sum of its ledger;
//   6. phone hashing gives the SAME answer as the source - the pepper lives in
//      Vault, Vault is encrypted per project, and a copy that hashes a number
//      differently is a copy where nobody can ever log in again;
//   7. the last migration applied is noted against this repository's.
// The workflow then runs the full pgTAP suite against the copy, which proves
// the functions, triggers and policies came back working, not just present.
//
// Never prints a connection string, a row, or a phone number: counts only.

import { readFile, writeFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import postgres from 'postgres';
import { ROOT, connect } from '../db/env.mjs';

const SNAPSHOT = path.join(process.env.RUNNER_TEMP ?? '.', 'restore-snapshot.json');

// Change only through a person's action. Exact equality is required.
const EXACT = [
  'salons', 'subscriptions', 'subscription_payments', 'customers', 'customer_identities',
  'users', 'wallet_accounts', 'wallet_lots', 'wallet_transactions', 'loyalty_ledger',
  'payments', 'visits', 'bookings', 'consents', 'binding_events', 'data_rights_requests',
  'platform_admins', 'services', 'add_ons', 'staff',
];

// Append-only, but a scheduled job may add to them between snapshot and dump.
const AT_LEAST = ['audit_log', 'domain_events', 'notifications', 'notification_deliveries'];

async function facts(sql) {
  const tables = await sql`
    select n.nspname as schema, c.relname as name, c.relrowsecurity as rls,
           c.relforcerowsecurity as forced
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'r' and n.nspname in ('public', 'app', 'app_admin')
     order by 1, 2`;

  const counts = {};
  for (const t of tables.filter((t) => t.schema === 'public')) {
    const [row] = await sql`select count(*)::bigint as n from ${sql('public')}.${sql(t.name)}`;
    counts[t.name] = Number(row.n);
  }

  const [latest] = await sql`select max(version) as v from public.schema_migrations`;

  // A fixed, fictional number - never a customer's. Only equality matters.
  let probe = null;
  try {
    const [row] = await sql`select encode(app.phone_hash('9000000009'), 'hex') as h`;
    probe = row.h;
  } catch {
    probe = null;
  }

  return {
    tables: tables.map((t) => ({ key: `${t.schema}.${t.name}`, rls: t.rls, forced: t.forced })),
    counts,
    latest_migration: latest?.v ?? null,
    phone_hash_probe: probe,
  };
}

async function snapshot() {
  const url = process.env.SOURCE_DB_URL;
  if (!url) throw new Error('SOURCE_DB_URL is not set');
  const sql = connect(postgres, url);
  try {
    const f = await facts(sql);
    await writeFile(SNAPSHOT, JSON.stringify(f));
    console.log(`Snapshot: ${f.tables.length} tables, latest migration ${f.latest_migration}.`);
  } finally {
    await sql.end({ timeout: 5 });
  }
}

async function verify() {
  const url = process.env.TARGET_DB_URL;
  if (!url) throw new Error('TARGET_DB_URL is not set');
  const before = JSON.parse(await readFile(SNAPSHOT, 'utf8'));
  const sql = connect(postgres, url);
  const failures = [];

  try {
    const after = await facts(sql);
    const afterTables = new Map(after.tables.map((t) => [t.key, t]));

    // 1 + 4. Every table, with its protection.
    for (const t of before.tables) {
      const got = afterTables.get(t.key);
      if (!got) {
        failures.push(`${t.key} is missing from the copy`);
        continue;
      }
      if (t.rls && !got.rls) failures.push(`${t.key} lost ROW LEVEL SECURITY in the restore`);
      if (t.forced && !got.forced) failures.push(`${t.key} lost FORCE ROW LEVEL SECURITY in the restore`);
    }

    // 2. Money and identity: exact.
    for (const name of EXACT) {
      if (!(name in before.counts)) continue;
      const a = before.counts[name];
      const b = after.counts[name];
      if (a !== b) failures.push(`${name}: ${a} rows at the source, ${b} in the copy`);
    }

    // 3. Append-only: nothing lost.
    for (const name of AT_LEAST) {
      if (!(name in before.counts)) continue;
      if ((after.counts[name] ?? 0) < before.counts[name]) {
        failures.push(`${name}: ${before.counts[name]} rows at the source, only ${after.counts[name]} in the copy`);
      }
    }

    // 5. Every balance is still its ledger.
    const [drift] = await sql`
      select count(*)::int as n
        from public.wallet_accounts w
       where w.balance_paise <> coalesce((select sum(t.amount_paise) from public.wallet_transactions t
                                           where t.customer_id = w.customer_id), 0)`;
    if (drift.n > 0) failures.push(`${drift.n} wallet balance(s) no longer equal their ledger`);

    // 6. The same pepper: logins still work.
    if (!after.phone_hash_probe) {
      failures.push('phone hashing does not work in the copy - the pepper was not restored to Vault');
    } else if (after.phone_hash_probe !== before.phone_hash_probe) {
      failures.push('the copy hashes phone numbers DIFFERENTLY - a different pepper; no existing customer could log in');
    }

    // 7. The copy is at the repository's schema.
    const files = (await readdir(path.join(ROOT, 'supabase/migrations')))
      .filter((f) => /^\d{4}_.*\.sql$/.test(f))
      .sort();
    const repoLatest = files.at(-1)?.replace(/\.sql$/, '') ?? null;
    if (after.latest_migration !== before.latest_migration) {
      failures.push(`latest migration: ${before.latest_migration} at the source, ${after.latest_migration} in the copy`);
    }
    // A source behind the repository is worth knowing, but it is not a failed
    // restore - the copy faithfully has what the source had.
    if (repoLatest && after.latest_migration !== repoLatest) {
      console.warn(`note: the database is at ${after.latest_migration}, the repository at ${repoLatest}`);
    }

    console.log(`Tables checked: ${before.tables.length}. Exact: ${EXACT.length}. Append-only: ${AT_LEAST.length}.`);
    for (const name of EXACT.filter((n) => n in before.counts)) {
      console.log(`  ${name.padEnd(24)} ${String(after.counts[name]).padStart(8)}`);
    }
  } finally {
    await sql.end({ timeout: 5 });
  }

  if (failures.length) {
    console.error('\nRESTORE DRILL FAILED - the copy is not the database:');
    for (const f of failures) console.error(`  ${f}`);
    process.exit(1);
  }
  console.log('\nRESTORE VERIFIED - every table, every protection, every balance came back.');
}

const mode = process.argv[2];
if (mode === 'snapshot') await snapshot();
else if (mode === 'verify') await verify();
else {
  console.error('usage: node scripts/ops/restore-verify.mjs snapshot | verify');
  process.exit(2);
}
