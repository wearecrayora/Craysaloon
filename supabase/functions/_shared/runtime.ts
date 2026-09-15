// Shared plumbing for the OTP Edge Functions: the service-role client, the
// customer's address, JSON responses, and alerting.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/**
 * The service-role client. Supabase injects SUPABASE_URL and a legacy
 * SUPABASE_SERVICE_ROLE_KEY into every function; this project uses the new
 * key format, so SUPABASE_SECRET_KEY is set as a function secret and wins.
 */
export function admin(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
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

/**
 * RULES 7.1.3: a fallback to Crayora's account is never a normal state, so
 * every occurrence is ALERTED, not just logged.
 *
 * Sent to Sentry over its envelope API directly - no SDK, because the whole
 * point of an alert path is that it has nothing in it that can fail to load.
 * Callers pass reason codes and ids only. Never a phone, a code or a token.
 */
export async function alert(event: string, extra: Record<string, string | number | null> = {}) {
  // Always visible in the function logs, even with no DSN configured.
  console.error(JSON.stringify({ alert: event, ...extra }));

  const dsn = Deno.env.get('SENTRY_DSN');
  if (!dsn) return;
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, '');
    const key = u.username;
    const eventId = crypto.randomUUID().replaceAll('-', '');
    const header = JSON.stringify({ event_id: eventId, sent_at: new Date().toISOString() });
    const item = JSON.stringify({ type: 'event' });
    const payload = JSON.stringify({
      event_id: eventId,
      level: 'warning',
      platform: 'javascript',
      logger: 'otp',
      message: { formatted: event },
      tags: { area: 'otp', event },
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
