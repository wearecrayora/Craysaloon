# Cray Salon

Multi-tenant SaaS for local salons in India, **white-labelled per salon**. One codebase, one
database, many salons, fully isolated by Postgres row-level security.

Crayora sells and provisions each salon from a Next.js super-admin console. Salon owners do not
self-onboard. A customer scans the salon's QR, installs the app, enters the salon code, logs in by
OTP, and lands in an app that looks like their salon's own.

Android ships first for cost reasons. The code is iOS-compatible from day one and CI builds iOS on
a macOS runner every commit, so it cannot quietly rot.

## Documents

Read these before changing anything. They are binding, not background.

| File | What it is |
|---|---|
| [`RULES.md`](RULES.md) | The binding rules. §2 lists capabilities that deliberately **do not exist** |
| [`PHASES.md`](PHASES.md) | Build order and milestone acceptance |
| [`IMPLEMENTATION.md`](IMPLEMENTATION.md) | Every screen, route, RPC and Edge Function |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Mechanisms, invariants, ADRs. On mechanism, this wins |
| [`DESIGN.md`](DESIGN.md) | Tokens, typography, layout, motion, charts |
| [`Cray-Salon-PRD-v4.md`](Cray-Salon-PRD-v4.md) | Scope and acceptance criteria. On scope, this wins |

`Cray-Salon-PRD-v3.md` is superseded and kept only as history.

## Stack

Flutter app · Next.js console on Vercel · Supabase (Postgres, Auth, Edge Functions) ·
Cloudflare R2 · Razorpay and Message Central **per salon, on the salon's own accounts** ·
Firebase Cloud Messaging · Sentry · `en` / `hi` / `hi_Latn`.

## Working on it

Development runs against a **hosted** Supabase project. There is no local stack, no Docker, and
`supabase db reset` is never used — the dev project is shared, and a reset would wipe it.

```sh
cp .env.example .env          # then fill it in; .env is gitignored and must stay that way

./scripts/db-push.sh          # apply migrations to the hosted dev project
node scripts/db/run.mjs test  # run the pgTAP release gates

./scripts/lint-gates.sh       # structural gates from RULES.md
./scripts/secret-scan.sh      # no credential may enter the repo or a build
./scripts/l10n-check.sh       # every string exists in all three locales
```

In CI the same gates run from zero against an empty `supabase/postgres` container, so the schema
cannot come to depend on state that only exists on the dev project.

## The gates that must never be weakened

Six database gates fail the build. They are never skipped, deleted, or narrowed to pass:

- **Cross-tenant leak test** — catalogue-driven, so a table added today is covered today
- **Binding exclusivity** — one phone number, exactly one salon, no switch path anywhere
- **Money** — ledgers are append-only, and neither owner nor manager can reach one
- **Index scope** — tenant indexes lead with `salon_id`, or are named and justified
- **Admin plane** — no tenant role can reach `app_admin`, every admin mutation is audited in the
  same transaction, provisioning is atomic, and no credential can be read back
- **Negative controls** — an unprotected table and an unaudited admin function are created on
  purpose, and the matching gate *must* go red. A gate only ever observed passing is not known to
  be a gate

## Security

No credential belongs in this repository. Per-salon secrets live in Supabase Vault and are
**write-only** — there is no API or screen that reads one back. `google-services.json`,
`GoogleService-Info.plist` and `.env` are gitignored, and `scripts/secret-scan.sh` runs in CI
against the repo and the built APK.

If you find a credential in here, treat it as live and rotate it.
