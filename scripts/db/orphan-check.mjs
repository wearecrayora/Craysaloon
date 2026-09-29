// Every function must be reachable from something that actually runs.
//
//   node scripts/db/orphan-check.mjs
//
// Four times in M7-M10 a function was correct, gated, and CALLED BY NOTHING:
//
//   * app.send_due_reminders   - reminders scheduled, never sent        (0066)
//   * app.* over PostgREST     - the dispatcher could not see them      (0068)
//   * wallet_debit_at_checkout - the wallet could be filled, not spent  (0069)
//   * on_visit_completed, on_booking_confirmed - Automations A and C
//                                had never run in production           (0075)
//
// Each one passed its own gate, because its gate called it directly. A gate that
// exercises a function by calling it tells you the function works; it tells you
// nothing about whether anything else ever will. This asks the other question.
//
// A function is REACHABLE if any of these call it:
//   1. another function's body (pg_proc.prosrc) - transitively, from a root
//   2. the app, the console or an Edge Function (the repo's source)
//   3. a schedule (scripts/db/schedule.sql)
//   4. a trigger
//   5. an entry point Postgres or Auth calls by configuration (ENTRY_POINTS)
//
// Reachability is computed from ROOTS (2-5) through the call graph (1), not by
// "is it mentioned anywhere" - a function called only by another orphan is an
// orphan too, which is exactly how 0075 hid: on_visit_completed was "called",
// by send_due_reminders' neighbour in the same file, by nothing that ran.

import postgres from 'postgres';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { ROOT, requireDatabaseUrl, connect } from './env.mjs';

// Called by configuration rather than by code. Each entry needs its reason.
const ENTRY_POINTS = new Map([
  ['public.custom_access_token_hook', 'Supabase Auth calls it on every token (config.toml)'],
  ['app_admin.close_privileges', 'called at the end of every migration that adds an app_admin function (0020)'],
]);

// Deliberately uncalled, with the reason. An entry here is a hole in the check
// and has to be argued for, like plpgsql-check's EXEMPT list.
const ALLOWED_ORPHANS = new Map([
  // Helpers the PHASES say land with a later milestone are NOT allowed here:
  // write the caller in the same session as the function, or do not write it.
]);

// --canary: inject a function nothing calls, and require the check to report
// it. A gate that has only ever been seen passing is not known to be a gate;
// this proves the reachability walk still finds an orphan, without creating
// anything in the shared database.
const CANARY = process.argv.includes('--canary');
const CANARY_NAME = 'app.canary_unreachable_function';

const SOURCE_DIRS = ['app/lib', 'console/app', 'console/server', 'console/lib', 'supabase/functions'];
const SOURCE_EXT = /\.(dart|ts|tsx|js|mjs)$/;

async function walk(dir) {
  const out = [];
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walk(full)));
    else if (SOURCE_EXT.test(e.name)) out.push(full);
  }
  return out;
}

const sql = connect(postgres, await requireDatabaseUrl());

try {
  const fns = await sql`
    select n.nspname as schema, p.proname as name, p.prosrc as src,
           (p.prorettype = 'trigger'::regtype) as is_trigger,
           exists (select 1 from pg_trigger t where t.tgfoid = p.oid and not t.tgisinternal)
             as has_trigger
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('app', 'app_admin', 'public')
       and p.prokind = 'f'
       -- pgTAP and extension functions live in public too; they are not ours.
       and not exists (select 1 from pg_depend d
                        where d.objid = p.oid and d.deptype = 'e')`;

  if (CANARY) {
    fns.push({
      schema: 'app',
      name: 'canary_unreachable_function',
      src: 'select 1',
      is_trigger: false,
      has_trigger: false,
    });
  }

  const byName = new Map();
  for (const f of fns) {
    const key = `${f.schema}.${f.name}`;
    if (!byName.has(key)) byName.set(key, []);
    byName.get(key).push(f);
  }
  const names = [...byName.keys()];

  // --- roots ---------------------------------------------------------------
  const code = [];
  for (const dir of SOURCE_DIRS) {
    for (const file of await walk(path.join(ROOT, dir))) {
      code.push(await readFile(file, 'utf8'));
    }
  }
  const repo = code.join('\n');
  const schedule = await readFile(path.join(ROOT, 'scripts/db/schedule.sql'), 'utf8');

  // Column DEFAULTs and RLS POLICY expressions call functions too - my_salon_id()
  // is called by four catalogue tables' salon_id default and by nothing else.
  // pg_get_expr omits the schema of anything on the search path, so these are
  // matched on the bare name.
  const exprRows = await sql`
    select pg_get_expr(d.adbin, d.adrelid) as expr from pg_attrdef d
    union all
    select coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
      from pg_policy p`;
  const exprs = exprRows.map((r) => r.expr).join('\n');

  const reachable = new Set();
  const why = new Map();
  const mark = (name, reason) => {
    if (reachable.has(name)) return false;
    reachable.add(name);
    why.set(name, reason);
    return true;
  };

  for (const name of names) {
    const bare = name.split('.')[1];
    const [schema] = name.split('.');
    if (ENTRY_POINTS.has(name)) mark(name, `entry point: ${ENTRY_POINTS.get(name)}`);
    else if (byName.get(name).some((f) => f.has_trigger)) mark(name, 'trigger');
    else if (schedule.includes(name) || schedule.includes(`${bare}(`)) mark(name, 'schedule');
    else if (new RegExp(`(^|[^a-z_])${bare}\\(`).test(exprs)) {
      mark(name, 'a column default or an RLS policy');
    }
    // Only PUBLIC functions are callable over the API. An app.* name appearing in
    // the repo is NOT a root - PostgREST cannot see it (0068) - so it must be
    // reached through the call graph like everything else.
    else if (schema === 'public' && new RegExp(`['"\`]${bare}['"\`]`).test(repo)) {
      mark(name, 'called from the app, console or an Edge Function');
    }
    // The console calls app_admin.* over a direct connection, by schema-qualified
    // name in SQL - that IS a real caller.
    else if (schema === 'app_admin' && repo.includes(`app_admin.${bare}(`)) {
      mark(name, 'called from the console');
    }
  }

  // --- the call graph --------------------------------------------------------
  let grew = true;
  while (grew) {
    grew = false;
    for (const caller of [...reachable]) {
      for (const f of byName.get(caller) ?? []) {
        for (const callee of names) {
          if (callee === caller || reachable.has(callee)) continue;
          const [cs, cn] = callee.split('.');
          // Qualified calls only: every body sets search_path = '' so an
          // unqualified name cannot resolve to one of ours anyway.
          if (f.src.includes(`${cs}.${cn}(`)) {
            if (mark(callee, `called by ${caller}`)) grew = true;
          }
        }
      }
    }
  }

  // --- rpc() calls PostgREST cannot resolve -----------------------------------
  // 0068 and 0078: an Edge Function or the app calling rpc('x') where x exists
  // only in app or app_admin. PostgREST exposes `public`; the call returns
  // "function not found" at runtime, and in 0078 that meant no Razorpay payment
  // could ever credit a wallet. Reported separately because it is not an orphan
  // - it is a caller pointed at nothing.
  const publicNames = new Set(names.filter((n) => n.startsWith('public.')).map((n) => n.slice(7)));
  const invisible = [];
  for (const m of repo.matchAll(/\.rpc(?:<[^>]*>)?\(\s*['"`]([a-z_][a-z0-9_]*)['"`]/g)) {
    if (!publicNames.has(m[1])) invisible.push(m[1]);
  }

  const orphans = names
    .filter((n) => !reachable.has(n) && !ALLOWED_ORPHANS.has(n))
    // Trigger FUNCTIONS attached to nothing are reported by plpgsql-check; the
    // question here is reachability of callable code.
    .sort();

  console.log(`${names.length} functions, ${reachable.size} reachable from something that runs.\n`);

  if (CANARY) {
    const caught = orphans.includes(CANARY_NAME);
    if (caught) {
      console.log(`NEGATIVE CONTROL PASSED - the injected ${CANARY_NAME} was reported unreachable.`);
    } else {
      console.error(`NEGATIVE CONTROL FAILED - ${CANARY_NAME} was NOT reported. The walk is broken.`);
    }
    await sql.end({ timeout: 5 });
    process.exit(caught ? 0 : 1);
  }

  if (invisible.length > 0) {
    console.error('rpc() CALLS POSTGREST CANNOT SEE - these names exist only outside `public`:\n');
    for (const n of [...new Set(invisible)].sort()) console.error(`  rpc('${n}')`);
    console.error(
      '\nEvery one of these returns "function not found" at runtime. In 0078 this\n' +
        'meant no Razorpay payment could ever credit a wallet. Add a public wrapper,\n' +
        'service-role only, as 0068 and 0078 do.\n',
    );
    process.exitCode = 1;
  }

  if (orphans.length > 0) {
    console.error('UNREACHABLE - correct or not, nothing that runs will ever call these:\n');
    for (const o of orphans) console.error(`  ${o}`);
    console.error(
      '\nORPHAN CHECK FAILED. Four times in M7-M10 a function like these passed its own\n' +
        'gate and never ran in production. Write its caller, or delete it - or, if\n' +
        'something outside this repo calls it, add it to ENTRY_POINTS with the reason.',
    );
    process.exitCode = 1;
  } else {
    console.log('ORPHAN CHECK PASSED - every function is reachable from a root.');
  }
} finally {
  await sql.end({ timeout: 5 });
}
