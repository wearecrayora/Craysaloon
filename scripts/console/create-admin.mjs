// Create (or promote) a Crayora operator.
//
//   node scripts/console/create-admin.mjs <email> "<Full Name>" \
//        --password-file <path outside the repo> [--super]
//
// Two things have to exist before anyone can use the console:
//
//   1. a Supabase Auth user - the console signs in against Supabase Auth, and
//   2. a row in public.platform_admins - which is what app_admin.assert_admin()
//      checks, and what makes an action attributable in audit_log.
//
// Neither is something the console can create for itself: provisioning the
// first operator is a bootstrap problem, and RULES 6.1's "no console action
// requires SQL" is about SALONS, not about Crayora's own staff.
//
// The generated password is written to --password-file and NEVER printed.
// Anything printed to a terminal ends up in scrollback, shell history and, in
// this project's case, an agent transcript. Point it somewhere outside the
// repository, read it once, change the password, delete the file.

import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import postgres from 'postgres';
import { ROOT, loadEnv, connect } from '../db/env.mjs';

const args = process.argv.slice(2);
const email = args[0];
const name = args[1];
const outIdx = args.indexOf('--password-file');
const passwordFile = outIdx >= 0 ? args[outIdx + 1] : null;
const isSuper = args.includes('--super');

if (!email || !name || !passwordFile) {
  console.error(
    'usage: node scripts/console/create-admin.mjs <email> "<Full Name>" ' +
      '--password-file <path> [--super]\n\n' +
      'The password file must be OUTSIDE the repository.',
  );
  process.exit(1);
}

if (path.resolve(passwordFile).startsWith(path.resolve(ROOT))) {
  console.error(
    'Refusing to write a password inside the repository. Use a path outside it.',
  );
  process.exit(1);
}

const env = await loadEnv();
const url = env.SUPABASE_URL;
const secret = env.SUPABASE_SECRET_KEY;
if (!url || !secret) {
  console.error('SUPABASE_URL and SUPABASE_SECRET_KEY must be set in .env');
  process.exit(1);
}

const auth = async (p, init = {}) =>
  fetch(`${url}/auth/v1${p}`, {
    ...init,
    headers: {
      apikey: secret,
      Authorization: `Bearer ${secret}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });

// A-Z a-z 0-9 and a few symbols that survive copy/paste out of a text file.
function password(bytes = 24) {
  const alphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^*-_=+';
  return Array.from(randomBytes(bytes))
    .map((b) => alphabet[b % alphabet.length])
    .join('');
}

// --- 1. the Auth user -------------------------------------------------------

let userId = null;

const found = await auth(`/admin/users?page=1&per_page=200`);
if (!found.ok) {
  console.error(`Could not list users: ${found.status} ${await found.text()}`);
  process.exit(1);
}
const { users = [] } = await found.json();
const existing = users.find((u) => (u.email ?? '').toLowerCase() === email.toLowerCase());

let generated = null;

if (existing) {
  userId = existing.id;
  console.log(`Auth user already exists for ${email}; leaving its password alone.`);
} else {
  generated = password();
  const created = await auth('/admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email,
      password: generated,
      email_confirm: true,
    }),
  });
  if (!created.ok) {
    console.error(`Could not create the Auth user: ${created.status} ${await created.text()}`);
    process.exit(1);
  }
  userId = (await created.json()).id;
  console.log(`Created Auth user for ${email}.`);
}

// --- 2. the platform_admins row --------------------------------------------

const sql = connect(postgres, env.DATABASE_URL);
try {
  await sql`
    insert into public.platform_admins (id, email, name, is_super, active)
    values (${userId}::uuid, ${email}, ${name}, ${isSuper}, true)
    on conflict (id) do update
      set email = excluded.email,
          name = excluded.name,
          is_super = excluded.is_super,
          active = true`;
  console.log(`platform_admins row is in place (is_super = ${isSuper}).`);
} finally {
  await sql.end({ timeout: 5 });
}

// --- 3. the password, to a file, once ---------------------------------------

if (generated) {
  await writeFile(
    passwordFile,
    [
      `Crayora console - temporary password for ${email}`,
      '',
      generated,
      '',
      'Sign in at http://localhost:3000/login, enrol two-factor when prompted,',
      'then change this password. Delete this file afterwards.',
      '',
    ].join('\n'),
    'utf8',
  );
  console.log(`\nTemporary password written to:\n  ${passwordFile}`);
  console.log('It was not printed here on purpose. Change it after first sign-in.');
} else {
  console.log('\nNo new password was generated (the account already existed).');
  console.log('Use the existing password, or reset it from the Supabase dashboard.');
}
