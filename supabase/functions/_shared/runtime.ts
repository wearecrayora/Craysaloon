// Shared plumbing for the Edge Functions: the service-role client, the
// customer's address, JSON responses, alerting, and the crash guard.

import { AsyncLocalStorage } from 'node:async_hooks';
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/**
 * The request's trace id (PHASES M12, 15 Oct 2026). The app sends one with
 * every call (`x-trace-id`); a caller that does not gets one made here. It is
 * on every alert and log line this request writes, and goes back on the
 * response - so a crash report in the app, a function log line and a Sentry
 * alert can be matched to the same tap.
 */
const traceStore = new AsyncLocalStorage<string>();
const TRACE = /^[A-Za-z0-9-]{8,64}$/;

export function currentTrace(): string | null {
  return traceStore.getStore() ?? null;
}

/**
 * The service-role client. Supabase injects SUPABASE_URL and a legacy
 * SUPABASE_SERVICE_ROLE_KEY into every function. This project uses the new
 * sb_secret_ key format, set as a function secret named CRAY_SECRET_KEY -
 * not SUPABASE_SECRET_KEY, because Supabase reserves the SUPABASE_ prefix for
 * the secrets it injects and refuses custom ones that use it.
 */
export function admin(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('CRAY_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Supabase URL or secret key is not configured');
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

/**
 * The CUSTOMER's address, from this function's incoming request.
 *
 * It must be passed to the database explicitly: when this function calls
 * PostgREST, the address PostgREST records is this function's own, and
 * keying a rate limit on that puts every customer in one bucket (0030).
 */
export function clientAddress(req: Request): string {
  const cf = req.headers.get('cf-connecting-ip');
  if (cf) return cf.trim();
  const xff = req.headers.get('x-forwarded-for');
  if (xff) return xff.split(',')[0]!.trim();
  return 'unknown';
}

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      // An OTP response must never be cached by anything between us and the
      // phone: a cached challenge id is a login someone else can finish.
      'Cache-Control': 'no-store',
    },
  });
}

/** The alert's area, from its prefix: otp_*, payments_*, dispatch_* / fcm_*. */
function areaOf(event: string): string {
  if (event.startsWith('otp_')) return 'otp';
  if (event.startsWith('payments_')) return 'payments';
  if (event.startsWith('dispatch_') || event.startsWith('fcm_')) return 'dispatch';
  return event.split('_')[0] ?? 'edge';
}

/**
 * RULES 7.1.3: a fallback to Crayora's account is never a normal state, so
 * every occurrence is ALERTED, not just logged. The same path carries every
 * other Edge Function alert - payments, dispatch - and the crash guard below.
 *
 * Sent to Sentry over its envelope API directly - no SDK, because the whole
 * point of an alert path is that it has nothing in it that can fail to load.
 * Callers pass reason codes and ids only. Never a phone, a code or a token.
 */
export async function alert(event: string, extra: Record<string, string | number | null> = {}) {
  // Always visible in the function logs, even with no DSN configured.
  const trace = currentTrace();
  console.error(JSON.stringify({ alert: event, trace_id: trace, ...extra }));

  const dsn = Deno.env.get('SENTRY_DSN');
  if (!dsn) return;
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, '');
    const key = u.username;
    const eventId = crypto.randomUUID().replaceAll('-', '');
    const header = JSON.stringify({ event_id: eventId, sent_at: new Date().toISOString() });
    const item = JSON.stringify({ type: 'event' });
    const area = areaOf(event);
    const payload = JSON.stringify({
      event_id: eventId,
      level: event.endsWith('_crashed') ? 'error' : 'warning',
      platform: 'javascript',
      logger: area,
      message: { formatted: event },
      tags: { area, event, ...(trace ? { trace_id: trace } : {}) },
      extra,
      timestamp: Date.now() / 1000,
    });
    await fetch(`${u.protocol}//${u.host}/api/${project}/envelope/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-sentry-envelope',
        'X-Sentry-Auth': `Sentry sentry_version=7, sentry_key=${key}, sentry_client=craysalon-otp/1.0`,
      },
      body: `${header}\n${item}\n${payload}\n`,
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    // An alert that fails must not fail the login. It is already in the log.
  }
}

/**
 * Deno.serve with a crash guard. An exception nobody caught used to reach
 * only the function log - a dispatcher or a webhook could fail on every call
 * and nobody would be told. Now it is alerted as `<area>_crashed`, by the
 * function's name and the error's CLASS only: an error message can carry
 * whatever the failing call was handed, and Sentry is not where that goes.
 */
export function serve(area: string, fn: string, handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    const sent = req.headers.get('x-trace-id') ?? '';
    const trace = TRACE.test(sent) ? sent : crypto.randomUUID();
    return await traceStore.run(trace, async () => {
      let res: Response;
      try {
        res = await handler(req);
      } catch (e) {
        console.error(`${fn} crashed [${trace}]:`, e);
        await alert(`${area}_crashed`, { function: fn, error: e instanceof Error ? e.name : typeof e });
        res = json(500, { error: 'internal' });
      }
      try {
        res.headers.set('x-trace-id', trace);
      } catch {
        // An immutable response (a pass-through) keeps its headers; the log has the id.
      }
      return res;
    });
  });
}
