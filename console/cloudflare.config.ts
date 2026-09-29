import { bindings, defineConfig, defineWorker } from "cf/config";

/**
 * The Crayora console on Cloudflare (replaces Vercel, 29 Sep 2026).
 *
 * Every secret the console reads is DECLARED here, so a deploy that forgets one
 * warns instead of failing at the first request. Locally they come from
 * `.dev.vars` (gitignored); in production from the Worker's encrypted secrets
 * (`npx wrangler secret put <NAME>`), never from this file.
 *
 * No caching of any kind: every page is per-admin and holds customer data.
 */
export default defineConfig({
  worker: defineWorker({
    name: "craysalon-console",
    entrypoint: "vinext/server/fetch-handler",
    compatibilityDate: "2026-09-29",
    compatibilityFlags: ["nodejs_compat"],
    assets: { notFoundHandling: "none" },
    // An admin console gets ONE public address. Preview URLs would give every
    // version its own, each a separate door to protect.
    previewUrls: false,
    env: {
      ASSETS: bindings.assets(),

      // The admin plane: a direct Postgres connection (ADR-35). Use the
      // Supabase TRANSACTION pooler URL (port 6543).
      ADMIN_DATABASE_URL: bindings.secret(),

      // Public values, but read at runtime by the server too.
      NEXT_PUBLIC_SUPABASE_URL: bindings.secret(),
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: bindings.secret(),

      // QR packs and uploaded assets.
      R2_ENDPOINT: bindings.secret(),
      R2_BUCKET: bindings.secret(),
      R2_ACCESS_KEY_ID: bindings.secret(),
      R2_SECRET_ACCESS_KEY: bindings.secret(),

      // SENTRY_DSN is optional, so it is deliberately NOT declared: a declared
      // secret is REQUIRED, and a deploy without it is refused. Set it when a
      // console Sentry project exists (`npx wrangler secret put SENTRY_DSN`);
      // the Worker sees it without a declaration. Until then server errors go
      // to the Worker's logs only.
    },
  }),
});
