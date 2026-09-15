// Proves public.custom_access_token_hook will work when Supabase Auth calls it
// on the hosted database, for a few real accounts, inside a transaction that is
// always rolled back.
//
// The hosted `postgres` role cannot SET ROLE supabase_auth_admin, so this checks
// what that role needs from the catalogue - USAGE on public and EXECUTE on the
// hook - and then runs the hook. It is SECURITY DEFINER, so once Auth may call
// it, everything it does runs as its owner, which is who runs it here.
//
// Run this before enabling the hook, and after any migration that touches it:
// once enabled, a hook that errors stops EVERY login on the project, staff
// and customers alike. Prints roles only - never ids, phones or tokens.
//
//   node scripts/db/probe-claims-hook.mjs

import postgres from 'postgres';
import { requireDatabaseUrl, connect } from './env.mjs';

const sql = connect(postgres, await requireDatabaseUrl());
let failed = false;

try {
  await sql.begin(async (tx) => {
    const [priv] = await tx`
      select has_schema_privilege('supabase_auth_admin', 'public', 'USAGE') as usage,
             has_function_privilege('supabase_auth_admin',
               'public.custom_access_token_hook(jsonb)', 'EXECUTE') as exec,
             p.prosecdef as definer
        from pg_proc p where p.oid = 'public.custom_access_token_hook(jsonb)'::regprocedure`;
    console.log(`supabase_auth_admin: usage on public=${priv.usage}, execute=${priv.exec}; security definer=${priv.definer}`);
    if (!priv.usage || !priv.exec || !priv.definer) failed = true;

    const users = await tx`select id from auth.users order by created_at desc limit 5`;

    if (users.length === 0) {
      console.log('no accounts yet - probing a random id');
      users.push({ id: crypto.randomUUID() });
    }

    for (const { id } of users) {
      const event = { user_id: id, claims: { sub: id, role: 'authenticated' } };
      try {
        const [{ out }] = await tx`select public.custom_access_token_hook(${tx.json(event)}) as out`;
        const claims = out?.claims ?? {};
        const sane = claims.sub === id && claims.role === 'authenticated' && typeof claims.app_role === 'string';
        console.log(`${sane ? 'ok  ' : 'BAD '} app_role=${claims.app_role ?? '(none)'}  salon_id=${'salon_id' in claims ? 'set' : 'absent'}`);
        if (!sane) failed = true;
      } catch (e) {
        console.log(`FAIL ${e.message}`);
        failed = true;
        throw e;
      }
    }
    throw new Error('rollback');
  });
} catch (e) {
  if (e.message !== 'rollback') {
    console.log(`error: ${e.message}`);
    failed = true;
  }
} finally {
  await sql.end();
}

if (failed) {
  console.log('\nHOOK PROBE FAILED - do not enable the hook.');
  process.exit(1);
}
console.log('\nHOOK PROBE PASSED - safe to enable.');
