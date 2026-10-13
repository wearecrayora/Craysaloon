// Copy Supabase's ICT logs into ops.ict_logs (Mumbai) and keep 180 days of them
// (CERT-In; migration 0099). Run hourly by .github/workflows/ict-logs.yml.
//
//   node scripts/ops/pull-logs.mjs
//
// Needs SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF and DATABASE_URL (from the
// environment, or .env locally).
//
// The Management API's `logs` endpoint (ClickHouse SQL over one `logs` table;
// the old per-source `logs.all` was removed on 23 Sep 2026) holds only the
// plan's short window, so each run copies what arrived since the newest row
// already held - capped to the last 23 hours - and the primary key makes any
// overlap a no-op.
//
// WHAT IS KEPT, and why not everything: the pooler logs a line for every
// connection - ~10,000 a day on this project, mostly CI - and 180 days of all
// of it would outgrow the database. So every ACCESS and AUTHENTICATION record
// is kept (API requests, sign-ins and the auth audit trail, PostgREST, Edge
// Functions), and from the database and the poolers only what a security
// review needs: errors, failures, denials, authentication and permission lines.
//
// It prints COUNTS only: log lines carry IP addresses and request paths, and a
// job log is not where they belong.

import postgres from 'postgres';
import { loadEnv, connect } from '../db/env.mjs';

const ACCESS = [
  'edge_logs',
  'auth_logs',
  'auth_audit_logs',
  'postgrest_logs',
  'function_edge_logs',
  'function_logs',
];
const NOISY = ['postgres_logs', 'pgbouncer_logs', 'supavisor_logs'];
const SECURITY = '(?i)error|fatal|fail|denied|authenticat|password|permission|refused|unauthori';
const PAGE = 500;
const MAX_LOOKBACK_MS = 23 * 60 * 60 * 1000;
const RETENTION = '180 days';
const MESSAGE_MAX = 1000;

const env = await loadEnv();
for (const name of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_PROJECT_REF', 'DATABASE_URL']) {
  if (!env[name]) {
    console.error(`${name} is not set - no logs copied.`);
    process.exit(1);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const list = (xs) => xs.map((x) => `'${x}'`).join(', ');

/** One query against the logs API, pacing itself and backing off on 429. */
async function query(sql, start, end) {
  const url = new URL(
    `https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/analytics/endpoints/logs`,
  );
  url.searchParams.set('sql', sql);
  url.searchParams.set('iso_timestamp_start', start.toISOString());
  url.searchParams.set('iso_timestamp_end', end.toISOString());

  for (let attempt = 0; attempt < 8; attempt++) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}` } });
    if (res.status === 429 || res.status >= 500) {
      const wait = Number(res.headers.get('retry-after')) * 1000 || 15000 * (attempt + 1);
      await sleep(Math.min(wait, 120000));
      continue;
    }
    if (!res.ok) throw new Error(`logs API ${res.status}`);
    const body = await res.json();
    if (body.error) {
      // "Backend error! Retry your query." is transient; anything else is not.
      if (/retry/i.test(String(body.error))) {
        await sleep(15000 * (attempt + 1));
        continue;
      }
      throw new Error(`logs API error: ${String(body.error).slice(0, 200)}`);
    }
    await sleep(3000); // pace: the endpoint is rate-limited per project
    return body.result ?? [];
  }
  throw new Error('logs API still failing after 8 attempts');
}

/** ClickHouse returns "2026-10-13T03:25:29.670868" - UTC, without a zone. */
const toDate = (ts) => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(ts) ? ts : `${ts}Z`);
/** ...and takes "2026-10-13 03:25:29.670868" back. */
const ch = (d) => d.toISOString().replace('T', ' ').replace('Z', '');

const sql = connect(postgres, env.DATABASE_URL);
let copied = 0;
let failed = false;

try {
  const [{ since }] = await sql`select max(logged_at) as since from ops.ict_logs`;
  const end = new Date();
  const floor = new Date(end.getTime() - MAX_LOOKBACK_MS);
  let from = since && since > floor ? new Date(since) : floor;

  try {
    for (;;) {
      const rows = await query(
        `select id, source, timestamp, event_message, log_attributes
           from logs
          where timestamp > toDateTime64('${ch(from)}', 6, 'UTC')
            and (source in (${list(ACCESS)})
                 or (source in (${list(NOISY)}) and match(event_message, '${SECURITY}')))
          order by timestamp asc
          limit ${PAGE}`,
        from,
        end,
      );
      if (rows.length === 0) break;

      const batch = rows.map((r) => ({
        source: r.source,
        event_id: String(r.id),
        logged_at: toDate(r.timestamp),
        // Capped: a database error line carries the whole failing statement -
        // ~10 KB a row - and a security review needs the gist, not the SQL.
        message: r.event_message == null ? null : String(r.event_message).slice(0, MESSAGE_MAX),
        metadata: r.log_attributes ?? null,
      }));
      const inserted = await sql`
        insert into ops.ict_logs ${sql(batch, 'source', 'event_id', 'logged_at', 'message', 'metadata')}
        on conflict (source, event_id) do nothing
        returning 1`;
      copied += inserted.length;

      if (rows.length < PAGE) break;
      const last = batch[batch.length - 1].logged_at;
      if (!(last > from)) break; // no progress - stop rather than loop
      from = last;
    }
  } catch (e) {
    console.error(`copy failed: ${e.message}`);
    failed = true;
  }

  const purged = await sql`
    delete from ops.ict_logs where logged_at < now() - ${RETENTION}::interval returning 1`;
  const [{ n, oldest, size }] = await sql`
    select count(*)::int as n, min(logged_at) as oldest,
           pg_size_pretty(pg_total_relation_size('ops.ict_logs')) as size
      from ops.ict_logs`;
  console.log(
    `copied ${copied}; purged ${purged.length} older than ${RETENTION}; holding ${n} rows ` +
      `(${size})${oldest ? ` since ${oldest.toISOString()}` : ''}`,
  );
} finally {
  await sql.end();
}

process.exit(failed ? 1 : 0);
