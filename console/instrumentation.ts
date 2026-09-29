/**
 * Next's server hook: every error thrown while rendering a page, running a
 * server action or a route handler reaches Sentry (ARCHITECTURE 16), scrubbed
 * (server/sentry.ts). Without a SENTRY_DSN it does nothing.
 */
export async function register() {}

export async function onRequestError(
  error: unknown,
  request: { path: string; method: string },
  context: { routeType: string },
) {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  const { reportServerError } = await import('./server/sentry');
  await reportServerError(error, {
    path: request.path,
    method: request.method,
    routeType: context.routeType,
  });
}
