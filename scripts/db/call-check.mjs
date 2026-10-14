// Every call into the database matches a function that exists - by NAME of
// argument for PostgREST callers, by COUNT for the console's direct SQL.
//
//   node scripts/db/call-check.mjs
//
// Found 13 Oct 2026: provisioning a salon failed in production with
// "provision_salon(..., text, jsonb) does not exist" - a call that compiled,
// passed every gate, and had never been run against the deployed stack. The
// orphan check proves a function is CALLED; nothing proved the call FITS. This
// does, from the live catalog:
//
//   * app (Dart) and Edge Functions (TS): `rpc('name', {p_a: .., p_b: ..})`.
//     PostgREST resolves by argument NAME - an unknown key, or a missing
//     argument with no default, is "function not found" at runtime.
//   * console (TS): `app_admin.name(${a}, ${b}, ...)` in SQL. Postgres resolves
//     by count and type; the count is checked here, and every structured value
//     must carry a cast (`::text[]`, `::jsonb`) - the driver sends parameters
//     untyped through the transaction pooler.

import postgres from 'postgres';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { ROOT, requireDatabaseUrl, connect } from './env.mjs';

async function walk(dir, ext) {
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
    if (e.isDirectory()) out.push(...(await walk(full, ext)));
    else if (ext.test(e.name) && !/\.test\.|_test\./.test(e.name)) out.push(full);
  }
  return out;
}

/** The text from `open` (an opening bracket) to its matching close. */
function balanced(src, open) {
  const pairs = { '(': ')', '{': '}', '[': ']' };
  const stack = [];
  let quote = null;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === '\\') { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === "'" || c === '"') { quote = c; continue; }
    if (pairs[c]) stack.push(pairs[c]);
    else if (c === stack[stack.length - 1]) {
      stack.pop();
      if (!stack.length) return src.slice(open + 1, i);
    }
  }
  return null;
}

/** Top-level comma-separated pieces of an argument list. */
function splitTop(s) {
  const parts = [];
  let depth = 0, quote = null, cur = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quote) {
      cur += c;
      if (c === '\\') { cur += s[++i] ?? ''; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === "'" || c === '"' || c === '`') { quote = c; cur += c; continue; }
    if ('([{'.includes(c)) depth++;
    if (')]}'.includes(c)) depth--;
    if (c === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) parts.push(cur);
  return parts.map((p) => p.trim()).filter(Boolean);
}

const sql = connect(postgres, await requireDatabaseUrl());
const failures = [];
let checked = 0;

try {
  const fns = await sql`
    select n.nspname as schema, p.proname as name, p.pronargs::int as nargs,
           p.pronargdefaults::int as ndefaults,
           coalesce(p.proargnames, '{}') as argnames,
           coalesce(p.proargmodes, '{}') as argmodes
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app', 'app_admin') and p.prokind = 'f'`;
  const byName = new Map();
  for (const f of fns) {
    const key = `${f.schema}.${f.name}`;
    // Input arguments only (modes i / b / v, or no modes at all).
    const inputs = f.argnames.filter((_, i) => !f.argmodes.length || ['i', 'b', 'v'].includes(f.argmodes[i]));
    (byName.get(key) ?? byName.set(key, []).get(key)).push({ ...f, inputs });
  }

  // --- PostgREST callers: names ------------------------------------------------
  const rpcFiles = [
    ...(await walk(path.join(ROOT, 'app/lib'), /\.dart$/)),
    ...(await walk(path.join(ROOT, 'supabase/functions'), /\.ts$/)),
    ...(await walk(path.join(ROOT, 'console'), /\.(ts|tsx)$/)),
    ...(await walk(path.join(ROOT, 'cron/src'), /\.ts$/)),
  ];
  for (const file of rpcFiles) {
    const src = await readFile(file, 'utf8');
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    for (const m of src.matchAll(/\.rpc(?:<[^>]*>)?\(\s*['"`]([a-z_][a-z0-9_]*)['"`]/g)) {
      const name = m[1];
      const overloads = byName.get(`public.${name}`);
      checked++;
      if (!overloads) {
        failures.push(`${rel}: rpc('${name}') - no such function in public`);
        continue;
      }
      // The params object, if any, follows the name.
      const after = src.slice(m.index + m[0].length, m.index + m[0].length + 20000);
      const brace = after.search(/^\s*,\s*(params:\s*)?\{/);
      let keys = [];
      if (brace === 0) {
        const open = m.index + m[0].length + after.indexOf('{');
        const body = balanced(src, open) ?? '';
        if (/\.\.\./.test(body)) continue; // spread: not statically knowable
        keys = splitTop(body)
          .map((kv) => /^['"]?([a-z_][a-z0-9_]*)['"]?\s*:/.exec(kv)?.[1])
          .filter(Boolean);
      }
      const fits = overloads.some((f) => {
        const required = f.inputs.slice(0, f.inputs.length - f.ndefaults);
        return keys.every((k) => f.inputs.includes(k)) && required.every((r) => keys.includes(r));
      });
      if (!fits) {
        const want = overloads.map((f) => `(${f.inputs.join(', ')})`).join(' or ');
        failures.push(`${rel}: rpc('${name}', {${keys.join(', ')}}) - the function takes ${want}`);
      }
    }
  }

  // --- the console's direct SQL: counts and casts --------------------------------
  const consoleFiles = await walk(path.join(ROOT, 'console/server'), /\.ts$/);
  for (const file of consoleFiles) {
    const src = await readFile(file, 'utf8');
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    for (const m of src.matchAll(/\b(app_admin|app|public)\.([a-z_][a-z0-9_]*)\(/g)) {
      const key = `${m[1]}.${m[2]}`;
      const overloads = byName.get(key);
      if (!overloads) continue; // a table or something not ours
      const inner = balanced(src, m.index + m[0].length - 1);
      if (inner == null) continue;
      const args = splitTop(inner);
      checked++;
      const n = args.length;
      if (!overloads.some((f) => n >= f.nargs - f.ndefaults && n <= f.nargs)) {
        const want = overloads.map((f) => `${f.nargs - f.ndefaults}..${f.nargs}`).join(' or ');
        failures.push(`${rel}: ${key}(...) passes ${n} arguments - the function takes ${want}`);
      }
      for (const a of args) {
        if (/^\$\{\s*sql\.(array|json)\(/.test(a) && !/\}::[a-z_]+(\[\])?\s*$/.test(a)) {
          failures.push(`${rel}: ${key}(...) passes ${a.slice(0, 40)}... with no cast - it arrives as text`);
        }
      }
    }
  }

  console.log(`${checked} database calls checked against the live catalog.`);
  if (failures.length) {
    console.error('\nCALLS THAT DO NOT FIT A FUNCTION:\n');
    for (const f of failures) console.error(`  ${f}`);
    console.error('\nCALL CHECK FAILED. Each of these fails at runtime, on the first click.');
    process.exitCode = 1;
  } else {
    console.log('CALL CHECK PASSED - every call fits a function that exists.');
  }
} finally {
  await sql.end({ timeout: 5 });
}
