# Cray Salon — Project Context

## What this is

Multi-tenant SaaS Android app for local salons, **white-labelled per salon**. One codebase, one
database, many salons, fully isolated. Retention loop: wallet, reminders, add-ons, packages,
loyalty, referrals, owner dashboard.

**Crayora SELLS and PROVISIONS each salon** from a Next.js super-admin console on Vercel. Owners
do **not** self-onboard.

## Read these every session

| File | What it is |
|---|---|
| **`RULES.md`** | **THE BINDING RULES. Read first, every session, before any code.** §2 lists capabilities that deliberately do not exist |
| `PHASES.md` | Build order, milestone cards, what to read per milestone |
| `IMPLEMENTATION.md` | Every screen, route, RPC and Edge Function |
| `Cray-Salon-PRD-v4.md` | Scope, features, acceptance criteria |
| `ARCHITECTURE.md` | Mechanisms, invariants, ADRs. **On mechanism, ARCHITECTURE wins** |
| `DESIGN.md` | Tokens, typography, layout, components, motion, charts |

Scope disputes go to the PRD. Mechanism disputes go to ARCHITECTURE. Fix the loser in the same
session — drift between the documents is how a rule quietly dies.

## Stack (do not substitute without asking)

- **App:** Flutter / Dart, install-first. **Android ships first (cost), iOS-ready from day one.**
  `app/ios` exists and CI builds it on a macOS runner every commit - never let it rot
- **Console:** Next.js on Vercel
- **Auth:** Supabase Auth, phone OTP
- **OTP delivery:** Message Central via Supabase's **Send SMS Hook**, routed to **the salon's own
  account** (salon code is entered BEFORE login). Crayora's account is a logged, alerted fallback.
  **No DLT registration anywhere** — Message Central is top-up-and-send
- **DB + isolation:** Supabase Postgres + Row-Level Security
- **Files:** Cloudflare R2 (logos, photos, invoices, QR packs) — signed URLs for private objects
- **Serverless + all messaging/payment calls:** Supabase Edge Functions
- **Payments:** Razorpay — **each salon's own account**. Wallet top-ups are non-refundable
- **Push:** Firebase Cloud Messaging — primary channel, ack-gated
- **Crash reporting:** Sentry
- **i18n:** `en` / `hi` / `hi_Latn` from day one

## Environment

- **Development runs against the HOSTED Supabase project** — no Docker, no local stack
  (`PHASES.md` option A). Apply migrations with `scripts/db-push.sh`. **Never `db reset`** — it
  would wipe shared data.
- Secrets live in `.env` (gitignored). `.env.example` documents the shape.
- Supabase uses the **new API key format**: `sb_publishable_…` (public, ships in the client) and
  `sb_secret_…` (**server-side only**). JWTs are **ES256, verified via JWKS** — there is no shared
  symmetric secret.
- Vendored agent skills are gitignored. Reinstall with:
  `npx -y skills add cloudflare/skills --skill '*' --yes`

## Non-negotiable rules

Full list in `RULES.md`. The ones most often broken:

1. Every table has `salon_id`. Every query tenant-scoped. RLS **enabled AND forced**.
   Never write a query that can return another salon's data.
2. **Salon code comes before login.** Never authenticate before the salon is known.
3. One phone number has exactly **one active binding**. No switch path, no such API.
   Unbind and transfer are audited Crayora super-admin actions only.
4. Secrets are server-side only, encrypted at rest, **never readable back** through any UI or API.
5. `wallet_transactions` and `loyalty_ledger` are **append-only**. Reversals are new rows.
   **Money never moves offline.**
6. **Only five callers may post to a ledger** (`RULES.md` §5.2). Neither owner nor manager is one.
   Do not build an adjustment screen, endpoint, or permission.
7. Wallet top-ups are **non-refundable**; **paid credit never expires** (no field, no code path);
   bonus expiry is set by the owner in the app and captured onto each lot at issue.
8. **Licensing boundaries — never "simplify" these:** customer money settles into the salon's own
   Razorpay account (no Crayora float), and credit is redeemable only at the issuing salon.
9. Add-ons are **never pre-selected**.
10. Referral rewards release only after a **completed, paid** first visit.
11. Salons are provisioned **only** through the console — never SQL, never a deploy. Activation is
    a deliberate human action.
12. Prefer push (free) over WhatsApp (paid, billed to the salon); gate escalation on a delivery
    **ack**, never on FCM's response.
13. Owner write-actions — above all **mark-complete** — work offline and sync idempotently.
    Rejected actions surface in "Needs attention", never dropped.
14. Consent is per-purpose and withdrawable. The **salon** is the Data Fiduciary; Crayora is the
    Processor. Never hard-delete a financial record — archive and anonymise.
15. **The launcher icon cannot be changed at runtime** on either platform. Android: in-app
    branding + pinned home-screen shortcut. **iOS has no equivalent** - in-app branding only.
    Do not attempt anything else.
15b. **Android ships first; the code stays iOS-compatible.** Never write platform-specific code
    outside a platform abstraction, and never let `app/ios` fall out of sync. CI builds iOS on a
    macOS runner because nobody here has a Mac.
16. **The OTP message cannot be branded** — its template belongs to Message Central. Do not write
    code that templates, brands or validates it.

## Design

`DESIGN.md` is binding. Most often broken:

- The app is **white-labelled** — never hard-code a colour, font or radius, and never tint
  surfaces with the brand colour.
- `onPrimary`, `brandInk` and every derived step are computed at publish. Publish is **blocked**
  if contrast fails.
- **Status and chart colours are never themed.** Charts use a fixed CVD-validated palette capped
  at three series.
- **Never animate a money value.** No bounce easing. Skeletons do not shimmer.
- Money: tabular figures, Indian grouping (`₹1,20,500`).
- A salon serving Hindi customers may only use a **Devanagari-capable** font; Devanagari gets
  +2dp line height and zero letter-spacing.

## Definition of done

Each feature passes its PRD acceptance criteria, the milestone gates in `PHASES.md`, and the
per-screen checklist in `IMPLEMENTATION.md` §7.

**Hard CI gates:** the catalogue-driven cross-tenant leak test, the binding-exclusivity test, and
the money test — plus the leak test's **negative control**, which creates an unprotected table on
purpose and requires the leak test to go red. Never skipped, never deleted, never narrowed to
pass. A gate that has only ever been seen passing is not known to be a gate.

## Build order

Follow `PHASES.md`. One milestone per session. Console (M2) and binding (M4) come before the
product surfaces. Simulated payments first, then live.
