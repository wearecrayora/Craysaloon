import 'server-only';

/**
 * Server errors from the console, to Sentry (ARCHITECTURE 16).
 *
 * Over Sentry's envelope API directly - the same approach as the Edge
 * Functions' alert path (supabase/functions/_shared/runtime.ts): no SDK to
 * load, patch or keep in step with Next.
 *
 * What is sent is deliberately thin. Never a request body, never a header (a
 * cookie is a session), never a query string. The message is scrubbed of any
 * run of six or more digits, so a phone number, an OTP or an account number
 * that reached an error message stops here. The console handles customer data;
 * its error reports must not.
 */

import { scrub } from '@/lib/scrub';

export async function reportServerError(
  error: unknown,
  where: { path?: string; method?: string; routeType?: string },
) {
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) return;

  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, '');
    const key = u.username;
    const eventId = crypto.randomUUID().replaceAll('-', '');
    const name = error instanceof Error ? error.name : 'Error';
    const message = scrub(error instanceof Error ? error.message : String(error));
    // The path without its query string; ids in it are uuids, not people.
    const path = where.path ? where.path.split('?')[0] : undefined;

    const header = JSON.stringify({ event_id: eventId, sent_at: new Date().toISOString() });
    const item = JSON.stringify({ type: 'event' });
    const payload = JSON.stringify({
      event_id: eventId,
      level: 'error',
      platform: 'javascript',
      logger: 'console',
      environment: process.env.NODE_ENV === 'production' ? 'production' : 'development',
      exception: { values: [{ type: name, value: message }] },
      tags: { surface: 'console', route_type: where.routeType ?? 'unknown', method: where.method ?? '' },
      transaction: path,
      timestamp: Date.now() / 1000,
    });

    await fetch(`${u.protocol}//${u.host}/api/${project}/envelope/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-sentry-envelope',
        'X-Sentry-Auth': `Sentry sentry_version=7, sentry_key=${key}, sentry_client=crayora-console/1.0`,
      },
      body: `${header}\n${item}\n${payload}\n`,
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    // A report that fails must not fail the request. The error is in the Worker's log.
  }
}
