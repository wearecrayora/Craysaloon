// Where DATABASE_URL comes from, in one place.
//
// Two callers need it (the migration/test runner and the leak test's negative
// control) and they must agree, because "which database did that run against?"
// is not a question anyone should have to ask about a release gate.
//
// CI has no .env and points DATABASE_URL at its own container, so a missing
// file is normal there and the environment always wins.

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

export const ROOT = path.resolve(import.meta.dirname, '../..');

export async function loadEnv() {
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

export async function requireDatabaseUrl() {
  const { DATABASE_URL } = await loadEnv();
  if (!DATABASE_URL) {
    console.error(
      'DATABASE_URL is not set in .env.\n' +
        'Supabase dashboard > Project Settings > Database > Connection string > URI.\n' +
        'Use the DIRECT connection (port 5432) - the transaction pooler does not\n' +
        'support all the DDL these migrations need.',
    );
    process.exit(1);
  }
  return DATABASE_URL;
}

// Never printed, never logged: the URL carries the password.
export function connect(postgres, url) {
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
