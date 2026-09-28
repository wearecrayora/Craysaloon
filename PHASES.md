# Cray Salon — Build Phases

**The order of work, what blocks what, and what "done" means at each step.**

| | |
|---|---|
| **Companions** | `RULES.md` (binding) · `Cray-Salon-PRD-v4.md` (scope) · `ARCHITECTURE.md` (mechanisms) · `DESIGN.md` (visual) · `IMPLEMENTATION.md` (screens, routes, API) |
| **Expands** | PRD §17 (the milestone list) and ARCHITECTURE §19 (milestone → mechanism) |
| **Adds** | Phase grouping with demo-able exits · the non-obvious dependencies · **the two non-code tracks that are the real critical path** · per-session instructions |

> **The thing this file exists to say:** the code is not the critical path. Legal sign-off,
> Meta verification, a Play Store account and a pilot salon all have lead times measured in
> weeks, and none of them start themselves. Track B (§8) is what decides your launch date.

---

## 1. How to use this file

- **One milestone per Claude Code session.** Never ask for a phase, and never for the whole app.
- Each milestone card (§4–§7) names exactly what to read before starting. Feed the session
  **`RULES.md` + the named sections**, not the whole document set.
- **`IMPLEMENTATION.md` lists the exact screens, routes and server functions each milestone
  builds.** Pair the card with its rows there so nothing is left orphaned.
- A milestone is done when its gates pass — not when the code is written. Gates are in the card.
- **Do not build ahead.** Each card has a *Not yet* list. Building Tier 2 tables early is the most
  reliable way to make Tier 1 late.

---

## 2. Three tracks, run in parallel

Most plans fail because they track only the first column.

| Track | What it is | Who | Blocking?              |
|---|---|---|---|
| **A — Build** | Milestones M0–M13, then Tier 2/3 | Claude Code sessions | Sequential, mostly |
| **B — Operations** | Legal, accounts, verifications, Play Store, pilot salon | Jyotiranjan / Crayora | **Long lead times. Starts at Phase 0** |
| **C — Pilot** | The 30-day pilot (PRD §18) | Crayora + one salon | Starts after Phase 5 |

**Track B is the one that will delay launch.** Meta business verification, a Play Store developer
account, and a lawyer reviewing a Data Processing Agreement do not compress. Start them in
Phase 0 (§8).

---

## 3. Phase map

| Phase | Milestones | Goal — stated as what you can demonstrate |
|---|---|---|
| **0 — Foundation** | M0–M1 | *"The database refuses to leak, and the test proves it on a table added today."* |
| **1 — A salon exists** | M2–M4 | *"I provisioned a salon in 25 minutes without SQL, handed over the QR, and a customer joined and saw the salon's own app."* |
| **2 — A salon runs its day** | M5–M6 | *"The owner ran a full day — walk-ins, bookings, add-ons, mark-complete — with the wi-fi off."* |
| **3 — The loop closes** | M7–M10 | *"A customer topped up, got a reminder, rebooked, referred a friend, and the owner saw all four on the dashboard."* |
| **4 — Crayora runs the business** | M11–M12 | *"A salon went past due and went read-only by itself. A customer exported their data."* |
| **5 — Ship** | M13 | *"It's on the Play Store and the release checklist is green."* |
| **6 — Deepen** | M14+ | Tier 2: packages, loyalty, staff app, GST, feedback |
| **7 — Scale** | M15+ | Tier 3: multi-branch, white-label APK, gift cards |

**Phases 0–5 are the product.** Do not start Phase 6 until a real salon has run the loop for
30 days (§9).

---

## 4. Dependencies — why this order

Most of the order is obvious. These five are not, and getting them wrong costs a rebuild.

**① The console comes before login.** *(M2 before M3)*
Login needs a salon code to resolve and per-salon Message Central credentials to send the OTP
from. Both are created in the console. Building auth first means building it twice.

**② The shared design-token package comes before both the console preview and the app theme.**
*(inside M2)* If the console re-implements the preview, the operator's preview lies about what the
customer sees (ARCHITECTURE §7.2). One package, two consumers.

**③ Consent capture lands at binding, not at the DPDP milestone.** *(M4, not M12)*
Reminders start sending at M8. If the consent ledger only arrives at M12, four milestones of
marketing go out with no recorded opt-in — a DPDP breach you then cannot retro-fix, because the
consent was never captured. **M4 writes consent defaults; M12 adds the export and erasure
tooling.**

**④ Price snapshots come before the dashboard.** *(M6 before M10)*
`booking_items` must snapshot price and duration at booking time. Without it, an owner editing a
service price silently rewrites past revenue and every dashboard number drifts (RULES §5.4.6).

**⑤ The wallet lot model comes before packages.** *(M7 before M14)*
Packages redeem *before* wallet in the allocation waterfall. If lots and `payment_allocations`
aren't right at M7, Tier 2 becomes a ledger migration instead of a feature.

**Two more worth holding in mind:** the money leak test is written at **M7** when the ledgers land,
not deferred to M13; and the money-disclosure UI (DESIGN §6.2) ships **with** M7, not with
"release states" at M13 — it is a legal requirement, not polish.

---

## 5. Phase 0 — Foundation

> **Goal:** a repo that can hold the product, and a database that cannot leak.
> **Exit:** the catalogue-driven leak test passes and is wired as a CI gate.

### M0 — Scaffold

| | |
|---|---|
| **Read** | `RULES.md` · PRD §0, Appendix A · ARCHITECTURE §17, §18 |
| **Build** | Monorepo per ARCHITECTURE §17 · `CLAUDE.md`, and all four docs at the root · Flutter app boots · **hosted** Supabase dev project reachable via `scripts/db/run.mjs` (option A — no local stack, no Docker) · FCM wired · i18n scaffold with `en` / `hi` / `hi_Latn` · **`packages/design-tokens`** (schema only) · Sentry in app and functions · CI skeleton |
| **Not yet** | Any screen with real content. Any table |
| **Done when** | App boots to a placeholder in all three locales · `node scripts/db/run.mjs migrate` applies cleanly to the hosted project · CI runs and is green · secret scan wired |

### M1 — Schema, RLS, and the leak test

| | |
|---|---|
| **Read** | `RULES.md` §3 · PRD §7, §8 · ARCHITECTURE §5.3, §5.8, §6.1, §6.2 |
| **Build** | Every Tier 1 table with `salon_id` · `enable` **and** `force` RLS everywhere · `app.current_salon_id()`, `app.salon_writable()` · the `app` schema helpers · `customer_identities` + `binding_events` with **zero policies** · ledger tables with revoked grants **and** the blocking trigger · the booking exclusion constraint · the reminder `cycle_key` unique index · **the catalogue-driven leak test** |
| **Not yet** | Tier 2/3 **feature** tables — `packages`, `customer_packages`, `package_redemptions`, `waitlist`, `feedback`, `invoices`, `photos`, `gift_cards`, `campaigns`, `branches`. Designed (PRD §8.3), not created. The Tier 1 **infrastructure** listed alongside them in §8.3 — `audit_log`, `loyalty_ledger`, `notification_tokens` and the machinery tables — **is** created here, for the reasons in §8.3 |
| **Done when** | Leak test passes structurally *and* behaviourally · a deliberately unprotected test table makes it **fail** — automated as `scripts/db/negative-control.mjs` and run in CI, not verified once by hand · migrations apply from zero onto an empty database in CI · CI gate wired |

> **What usually goes wrong here:** someone omits `force row level security` because `enable`
> "worked". It works until a migration or a service-role connection reads the table, and then it
> silently reads everything. The structural half of the leak test exists to catch exactly this.

---

## 6. Phase 1 — A salon exists

> **Goal:** Crayora can create a salon, and a customer can join it and see the salon's own app.
> **Exit:** a non-engineer provisions a real salon in under 30 minutes, hands over a printed QR,
> and someone binds and lands in a fully branded app.

This is the first genuinely demo-able moment, and the first point at which the product's central
claim — *it looks like the salon's own app* — is either true or not.

### M2 — Console v1 on Vercel ⭐

| | |
|---|---|
| **Read** | `RULES.md` §6, §11 · PRD §6.2, §6.3, §11, §16A.1 · ARCHITECTURE §5.7, §8, §14 · `DESIGN.md` §3, §12 |
| **Build** | Next.js on Vercel, MFA admin auth against `platform_admins` · **every mutation through an `app_admin.*` function that writes `audit_log` in the same transaction** · the provisioning flow as **one transaction** · branding studio with live preview from `packages/design-tokens` · **publish-time contrast gate** · Vault-backed write-only credentials with *Test connection* · salon code generation + printable QR pack to R2 · owner invite · **manual activation** as a separate deliberate action |
| **Not yet** | Billing screens (M11) · support mode (M12) · platform metrics (M11). *Transfer/unbind shipped with M4; the Customer binding desk is built.* **“Test connection”: Message Central is verified on save** (the pair is checked with Message Central before it is stored, no SMS sent, and a mismatched pair is refused). Razorpay, WhatsApp and RCS are still stored write-only and stay `untested`, and the console says exactly that rather than implying otherwise |
| **Done when** | Someone who has never seen the codebase provisions a salon end to end in <30 min · no step touches SQL · a saved secret cannot be read back through UI or API · a failing palette **blocks** publish · `setup → active` happens only by explicit human action · every action appears in `audit_log` |

### M3 — Salon-code-first auth ⭐

| | |
|---|---|
| **Read** | `RULES.md` §4, §7.1, §7.4 · PRD §6.4, §12.1, §12.1a · ARCHITECTURE §5.1, §5.2, §5.6 |
| **Build** | `resolve_join_code()` returning display name + branding, `anon`-callable, rate-limited · `start_join(code, phone)` writing `join_intents` · the `otp-send` and `otp-verify` Edge Functions — Message Central VerifyNow generates, sends and verifies; Supabase issues the session only after it confirms (ADR-36) · `otp_challenges` bound server-side to phone and salon, ≤5 attempts · `resolve_otp_sender()`: intent → binding → staff → **refuse** · platform fallback with alerting · the custom access token hook minting claims · rate limits per phone / IP / device / salon-per-day |
| **Not yet** | Binding itself (M4). Auth ends at a valid session |
| **Status** | Built and live-verified 2026-09-15: a real OTP from Message Central, a session, replay refused, no plaintext phone in `auth.users`. The claims hook shipped with M4's server half (0034) and is enabled on the hosted project |
| **Done when** | An OTP request with no salon context is **refused** · a code is only ever checked against the challenge the server issued, never one the client names · a session is issued only on `VERIFICATION_COMPLETED` · the token never appears in any log or breadcrumb · a salon with broken credentials falls back **and alerts** · the login screen already wears the salon's branding |

> **Note:** the Message Central platform account must exist before this milestone starts (§8).

### M4 — Binding and white-label ⭐

| | |
|---|---|
| **Read** | `RULES.md` §4, §8, §12A · PRD §6.5, §6.6 · ARCHITECTURE §5.4, §5.5, §7 · `DESIGN.md` §3, §5.3, §6 |
| **Progress** | **Server half done, live 2026-09-15** (0034, 0035): the claims hook is enabled on the hosted project (probe-first), `otp-verify` binds before it mints a session, `already_bound` names no salon, consent defaults are written at binding, `customer.bound` is emitted, and `app_admin.unbind_customer` / `transfer_customer` exist, reason-required and audited, ending the customer's sessions. Gate: `supabase/tests/rls/bind_flow_test.sql`. The console's **Customer binding** desk (K12) is built: super-admin only (0036 corrected 0034, which allowed any operator), an audited exact-number lookup, and a transfer that refuses any balance but the real one. **App side built 2026-09-27:** the join flow (U2-U6) against the real server contract, theming from the published resolved tokens (ADR-40) including offline from the cache, the pinned home-screen shortcut (Android; absent on iOS by necessity) and the per-salon notification channel. Gates: `app/test/join_flow_test.dart`, `brand_tokens_test.dart`, `salon_home_test.dart`, `join_code_test.dart`. The QR path landed the same day: an in-app camera scanner, the deep link for a QR opened by the phone's own scanner, and `join/` - the static site serving `/s/<code>` and (generated at deploy, never committed) `assetlinks.json`. **Still to build:** reading the Play Install Referrer on first launch, which needs a Play Console listing (M13 owns release signing and the listing), and the iOS app-site-association file, which needs an Apple team id |
| **Build** | Binding inside `otp-verify` via `otp_finish_login()` — atomic, consuming the join intent, before any session exists (ADR-39; replaces the `bind_customer()` + `cver` design) · the confirmation screen naming the salon · **`already_bound` that never names the other salon** · `app_admin.unbind_customer` / `transfer_customer` with required `acknowledged_balance_paise` · **consent defaults written at binding** (dependency ③) · full theming from tokens, cached offline · pinned home-screen shortcut · per-salon notification channel · **the join domain**: `join.craysalon.in` serving `/.well-known/assetlinks.json` (the app's signing fingerprint) and a `/s/<code>` fallback that sends a phone without the app to the Play listing, carrying the code through Install Referrer. *Added after the QR pack shipped in M2: every printed QR encodes this URL, and no milestone had been scheduled to make it exist* |
| **Not yet** | The launcher icon. It cannot be changed at runtime (RULES §2) |
| **Done when** | The binding-exclusivity and bind-flow tests pass · no tenant-reachable switch/unbind/transfer path exists · a transfer leaves wallet and history with the old salon · the app re-themes without a restart · it renders correctly under a dark brand, a pale brand and the neutral default · consent rows exist for every bound customer · **a printed QR opens the app with the code pre-filled, or - without the app - the Play listing, and the code survives the install** |

---

## 7. Phases 2–7

### Phase 2 — A salon runs its day *(M5–M6)*

> **Exit:** the owner completes a full day's work with the wi-fi switched off, and everything
> syncs when it comes back.

**M5 — Catalogue and records.** Services, add-ons, staff, customer profiles, visit history, and
the Drift read cache.
*Read:* PRD §8.2 · ARCHITECTURE §6.2, §9, §10.1 · `DESIGN.md` §6.
*Done when:* every list is keyset-paginated, reads work offline from cache, and lists render at
200% text scale.
*Progress (2026-09-27):* the read half is built and gated. `public.list_customers` - keyset on
(last_visit_at, id), name-prefix or whole-number search, **SECURITY INVOKER** so every RLS policy
still applies (gate: `rls/list_customers_test.sql`, 13 assertions). In the app: the Drift read
cache, `RecordsRepository` (server first, cache when offline, and the screen SAYS which), the
role-based router and shells (ARCH 9.1), O4 customer list, O5 customer record - **balance shown,
not editable, asserted by a test that requires the controls to be absent** - and the read-only
catalogue lists O7/O8/O9. 200% text scale is asserted as a test, not eyeballed. Catalogue editing followed the same day: add and edit for services, add-ons and the team, money
leaving the form as integer paise, hidden-not-deleted, and **controls shown only to an owner or a
manager** - a courtesy on top of 0041, which refuses the write in the database whatever the app
sends. Building it exposed the write-side twin of the read bug 0038 fixed: **a customer repriced a
service to 1 paisa**, a staff member could have promoted themselves, and an owner could have
activated their own salon (RULES 3.8b; gate: `rls/write_scope_test.sql`). **Still to build:** O1 the
day view, which belongs with bookings (M6).

**M6 — Booking, slots, add-ons, offline queue.** The exclusion constraint, `app.available_slots()`
shared by client and server, `booking_items` **with price snapshots** (dependency ④), the outbox,
and the **"Needs attention"** inbox.
*Read:* `RULES.md` §9 · PRD §9.3 · ARCHITECTURE §6.5, §10 · `DESIGN.md` §6.3, §6.4, §6.5.
*Done when:* two concurrent bookings for the same barber cannot both succeed · **no add-on is ever
pre-checked** · mark-complete is one tap and works offline · a rejected offline action surfaces
with a one-tap fix and is never dropped.
*Progress (2026-09-27):* the server half is built and gated - `available_slots` (one definition,
shared by both apps and the server), `create_booking` (price and duration snapshotted, idempotent
on `client_action_id`, races decided by the exclusion constraint), `mark_visit_complete`
(idempotent transition, replays are no-ops) and `cancel_booking` (frees the chair immediately).
Gate: `booking/booking_test.sql`, 34 assertions, with a negative control that DROPS the exclusion
constraint and requires the gate to go red.
*App side (same day):* the **outbox** (`data/local/outbox.dart`) - the one local source of truth,
which survives a cache wipe and an app upgrade because both would otherwise throw away a morning's
mark-completes; the **day view (O1)** with one-tap complete at 56dp, working with the wi-fi off and
showing how much work is waiting; **walk-in (O2)** with add-ons that start unticked and times that
come from the same function the database accepts; and **"Needs attention" (O3)** where a refusal
lands with a reason a person can act on, a one-tap retry that reuses the same action id, and a
discard that is always deliberate. Gates: `app/test/outbox_test.dart` (13) and
`day_screen_test.dart` (8). **Still to build:** connectivity-triggered draining (today the queue
drains when the day view opens or acts) and the reminder engine's side of visits (M8).

### Phase 3 — The loop closes *(M7–M10)*

> **Exit:** one customer completes the whole loop and the owner can see it happen.

**M7 — Wallet and payments.** Lots, the ledger functions, the allocation waterfall, per-salon
Razorpay with path-token webhooks, Automations B and L.
*Read:* `RULES.md` §5 · PRD §8.5, §9.1, §14, §16A.2 · ARCHITECTURE §6.3, §6.4, §8.3, §13.1 ·
`DESIGN.md` §6.1, §6.2.
*Done when:* the **money leak test** passes — only the five callers post to a ledger, no
owner/manager path exists, `UPDATE`/`DELETE` raise for every role, no paid lot can expire ·
concurrent debits cannot overdraw · the disclosure block renders above the pay button.
*Simulated payments are acceptable here; real Razorpay before Phase 5.*
*Progress (2026-09-27):* the ledger is built and gated. `app.wallet_post` is the **one** function
that writes a ledger row - it takes the row lock, recomputes, inserts and updates the cached
balance, so "cannot overdraw" exists once rather than in five places. Four of the five permitted
callers exist: credit from a captured payment (idempotent per payment, bonus terms captured onto the
lot at issue), debit at checkout (**bonus lots first, oldest expiry first**, with allocations
recorded per lot so a refund could unwind precisely), bonus-lot expiry (which **refuses a paid
lot**), and `app_admin.wallet_correct` - super-admin only, reason required, audited, and the only
human path to a balance anywhere. `app.referral_release_reward` is deliberately absent until
referrals exist (M9): a function that moves money before the rule justifying it is worse than a
missing one. Gate: 18 new assertions in `money/ledger_test.sql`, plus a negative control that adds a
second ledger writer and requires the gate to go red. *Payments (same session):* `create-payment-order` and `rzp-webhook/{token}` are built, with the
salon's own Razorpay keys fetched at the moment of use - **no Crayora account exists to fall back
on, by design** (RULES 8). The webhook resolves the salon from its path token, verifies the body's
HMAC with that salon's own webhook secret, dedupes on the event id, and re-verifies the amount
against the payment row before a paisa is credited. Razorpay needs two secrets, so the console now
collects both and shows the operator that salon's webhook URL to paste into their dashboard.
0049 also **generalised the one credential door** rather than adding a second: `otp_salon_sender`
now calls `salon_provider_secret`, so the schema still has exactly one function that reads Vault -
asserted by the gate, which names both it and the pepper reader. *App and automations (2026-09-28):* the **wallet (C2)** and **Add Money (C3)** are built. The
disclosure block is above the pay button, at body size, uncollapsed, and every number on it comes
from `topup_quote` - the screen never computes a bonus, so it cannot promise one the ledger would
refuse. The pay button is **disabled until the quote lands**, because a pay button live before the
disclosure is a payment made without it. A test asserts the block sits physically above the button.

**The app never says a payment succeeded.** `PaymentSheet` can report `submitted` at best; the
credit follows Razorpay's webhook. The Razorpay SDK is deliberately not wired yet
(`UnavailablePaymentSheet`), and the screen says the last step is not switched on rather than
offering a dead button - a simulated sheet that reported success would be one merge from shipping,
and the customer it fails believes they hold credit they do not have. **Razorpay wired the same
day:** `RazorpayPaymentSheet` opens Checkout against the salon's own key, and it **drops the
payment id and signature the callback carries** - a client-reported payment id is a claim, and
treating a claim as evidence is how a wallet gets credited for a payment nobody made. Proguard
keeps are in place before minification is turned on at M13, because Razorpay is reached by
reflection and R8 would strip it in the one build nobody tests by hand. `create-payment-order` and
`rzp-webhook` were **not deployed** until now; both are, with the verify_jwt settings config.toml
specifies, and both refuse an unauthenticated call.

**What is left is console work, not code:** the test salon has **no stored Razorpay credential and
no wallet rule** (`{}`, so no bonus and no minimum), and its **Message Central credential is
missing too** - which means every OTP so far went out on Crayora's fallback account and raised a
fallback alert, exactly as designed but not as intended for a live test. All three are set in the
console, which is deliberately the only path (RULES 8.12).

**Automation B** is the `wallet.topped_up` event, emitted inside the same transaction as the
credit, carrying the amount, the bonus and its expiry so a receipt never re-derives its own
trigger. It inherits the credit's idempotency: one credit, one receipt, however many times
Razorpay redelivers. **Automation L** is `app.expire_due_bonus_lots` (per salon, guarded by
`wallet_lots.expired_at`) and `app.nudge_expiring_bonus` (one warning per lot, ever, guarded by a
unique index - a nightly sweep is not a nightly message). **The schedule is not attached**: pg_cron
is not installed on this project, so M8 wires the nightly trigger with the rest of the scheduled
surface. Gate: 14 new assertions in `money/ledger_test.sql`.

**M8 — Reminders and push.** Automations A, C, K; the ack protocol; learned intervals.
*Read:* PRD §9.2, §10.1, §12 · ARCHITECTURE §6.6, §6.7, §11, §12.
*Done when:* exactly one reminder per cycle (enforced by index, not code) · escalation is
**ack-gated**, never FCM-response-gated · a salon without approved WhatsApp templates still works
completely.
*Progress (2026-09-28):* **server half done and gated** (0059-0064, `messaging/reminder_test.sql`,
33 assertions, two new negative controls). Automation A writes the last visit, the learned median,
today's metrics and exactly one reminder; Automation C confirms and marks the reminder `converted`,
which is also what makes conversion measurable; Automation K promotes only deliveries that are
**unacked past their window**. The ladder skips every rung a salon has not configured, so a salon
with no WhatsApp templates and no RCS agent works completely. Templates are seeded in all three
locales and a trigger refuses any body that names the product to a customer.

**Four bugs, and the gate found all four.** Three were a column or constraint assumed instead of
read (`booking_items` has kind/ref_id, `customers` has last_visit_at, `sample_n` counts visits) -
plpgsql validates no body at CREATE time, so each applied cleanly and would have failed at the
first mark-complete. The fourth was real: a replay converted its OWN reminder, freeing the partial
index and inserting a duplicate, so a replayed offline mark-complete would have sent two reminders
for one haircut and billed the salon for both.

**The ack is wired in all three places**, including the background isolate - which is the one that
matters, because most pushes arrive when nobody is looking at the app, and an unacked push
escalates to a channel the salon pays for. The schedule is live: one `pg_cron` entry a minute,
running `app.run_due_automations()` with per-salon exception isolation, verified firing on the
hosted project.

**Still to build:** a live push, which needs an FCM service account the project does not have, and
a trigger for `dispatch-notifications` from outside the database - deliberately outside, because
nothing scheduled in the database may hold a credential (RULES 8.12). The function is written,
type-checked, and reports `push_not_configured` rather than pretending.

**M9 — Refer & Earn.** Automation D.
*Done when:* a reward releases only after a completed **paid** first visit; self-referral rejected
by constraint; a cancelled or refunded visit releases nothing.

**M10 — Dashboard and cohorts.** Automation E, `daily_salon_metrics`, `retention_cohorts`, nightly
reconciliation.
*Read:* PRD §9.5 · ARCHITECTURE §6.8 · **`DESIGN.md` §6.6, §9** (stat tiles first; ≤3 series;
fixed palette; direct labels; table fallback).
*Done when:* card totals match completed transactions exactly · reconciliation **alerts** on
mismatch rather than healing · the cohort chart has a legend, direct labels, an `n`, and a table
view · **there is no wallet-adjustment control anywhere**.

### Phase 4 — Crayora runs the business *(M11–M12)*

**M11 — Billing.** Offline setup-fee recording, subscription state, Automation I, read-only grace,
console billing and platform metrics.
*Read:* PRD §14, §16A.6 · ARCHITECTURE §13.2.
*Done when:* read-only grace is enforced **in the database** · retention notices fire at day 60 and
80 · plan entitlements are checked server-side.

**M12 — Compliance and observability.** DPDP export and anonymise, opt-out surfaces, per-salon
grievance contact, Sentry across all three surfaces, backups **and a rehearsed restore**, support
mode, runbooks.
*Read:* `RULES.md` §11 · PRD §16, §16A.4, §16A.6 · ARCHITECTURE §15.4, §15.6, §16.
*Done when:* anonymise preserves ledger integrity **and** binding exclusivity · purge splits
personal from financial · a restore drill has actually been performed · support mode is time-boxed
and reason-required.

### Phase 5 — Ship *(M13)*

**M13 — Release.** Empty / loading / error / offline states everywhere, the full PRD §20 checklist,
the Play Store build.
*Read:* `RULES.md` §12 · `DESIGN.md` §13 · PRD §20.
*Done when:* **every box in PRD §20 is ticked** · every box in `DESIGN.md` §13 is ticked · no
secret appears in the APK or the Vercel client bundle · the app is live on the Play Store.

### Phase 6 — Deepen *(M14+)*
Packages, loyalty, waitlist and queue, lifecycle automation, feedback/NPS, staff shell and
commission, GST invoicing, photo gallery, home service. **All additive — no Tier 1 schema
rewrite.** Do not start until §9 is satisfied.

### Phase 7 — Scale *(M15+)*
Multi-branch (`branch_id` **below** `salon_id`, never replacing it), per-salon white-label APK,
gift cards (**after** written legal sign-off), inventory, campaigns, dynamic pricing, WhatsApp
chatbot.

---

## 8. Track B — Operations (start in Phase 0)

These have external lead times. Nothing in Track A unblocks them, and they will decide the launch
date. Start every one of them now.

| Item | Needed by | Lead time | Notes |
|---|---|---|---|
| **Supabase projects** — local, staging, production | M0 | Hours | Enable PITR on production |
| **Play Store developer account** | M13, but **start Phase 0** | **Weeks** — identity verification, and new accounts face testing requirements before public release | The single most commonly underestimated item |
| **Crayora Message Central account** | **M3** | Days | Blocks auth. Confirm in writing that provider registrations cover traffic sent for salons (PRD §16A.5) |
| **Crayora Razorpay account** | M11 | Days–weeks | For subscriptions. Business documents required |
| **Cloudflare R2 + Sentry** | M0–M2 | Hours | |
| **Curated font allow-list** — `latin` and **`latin+devanagari`** sets | **M2** | Hours | Console cannot ship its branding studio without it (`DESIGN.md` §5.4) |
| **QR pack print design** — counter card, mirror sticker, poster | M2 | Days | Rendered by the console; the design is yours |
| **⚖️ Crayora–salon agreement + Data Processing Agreement** | **Before the first paying salon** | **Weeks** | DPDP requires it; without it the *salon* is non-compliant |
| **⚖️ Customer terms + per-salon privacy notice** | Before first paying salon | Weeks | Names the salon as Data Fiduciary |
| **⚖️ Counsel: non-PPI / non-payment-aggregator position** | Before first paying salon | Weeks | PRD §16A.1 |
| **⚖️ CA: GST treatment + statutory retention period** | Before first paying salon | Weeks | PRD §16A.3, §16A.6 |
| **Per-salon Message Central account** | At each salon's setup | Days | Crayora sets it up (PRD Q-D) |
| **Per-salon WhatsApp Business + Meta template approval** | Before that salon's WhatsApp rung | **Weeks** — business verification | Never blocks onboarding; the ladder skips WhatsApp |
| **Per-salon Razorpay account** | At each salon's setup | Days | Money settles to the salon |
| **Pilot salon recruited + baseline measured** | Before Phase 5 exit | Weeks | PRD §18, §19 |

---

## 9. The gate before the first paying salon

Do not take money from a salon owner until **all** of these hold. This is the one place where
"we'll fix it after launch" is genuinely not available.

- [ ] Phases 0–5 complete; PRD §20 checklist fully green
- [ ] **Real** Razorpay wired (not simulated), per-salon, with webhook signature verification
- [ ] Message Central live for Crayora and for that salon
- [ ] ⚖️ Salon agreement + DPA signed
- [ ] ⚖️ Customer terms and privacy notice published, naming the salon as Data Fiduciary
- [ ] ⚖️ Counsel has confirmed the closed-loop and non-payment-aggregator position
- [ ] ⚖️ CA has confirmed GST treatment and the retention period
- [ ] Grievance officer named and contactable, for the salon and for Crayora
- [ ] Breach-notification runbook written **and rehearsed**
- [ ] Backup restore **rehearsed**, not merely configured
- [ ] The salon's outstanding-credit settlement obligation is in the signed contract

---

## 10. Track C — The 30-day pilot

Starts after Phase 5, with one salon (PRD §18).

**Before week 1:** record the baseline — average bill, repeat-visit gap, weekly customers,
no-shows, current referral method. Without a baseline the pilot proves nothing.

| Week | Focus | Watch |
|---|---|---|
| **W1** | Setup + train the owner on **one** workflow, and on the **QR handover** | **Bind rate.** If customers aren't being asked to scan, nothing else can work |
| **W2** | Wallet + reminders live; check payment, refund and balance daily | Ledger drift · reminder→booking conversion |
| **W3** | Add-ons + referrals for completed customers | Add-on acceptance · referral validity |
| **W4** | Compare against baseline | Repeat rate, average bill |

**After:** keep only what produced real usage or saved the owner time. **Bind rate is the leading
indicator for everything** — a low bind rate is a training problem, not a product problem, and no
feature will fix it.

---

## 11. Running one session

```
Read RULES.md.
Then read: <the sections named in the milestone card>.
Implement <milestone> per PRD <sections>. Acceptance criteria are in those sections.
Do not build anything in the card's "Not yet" list.
Stop when the card's gates pass.
```

Three habits that keep this working:

1. **Never widen the milestone mid-session.** A tempting adjacent feature is a separate session.
2. **Gates before green.** "The code is written" is not done; the card's gates passing is done.
3. **When the PRD and ARCHITECTURE disagree** — mechanism goes to ARCHITECTURE, scope to the PRD —
   **fix the loser in the same session.** Drift between the documents is how a rule quietly dies.

---

## 12. Progress

| Phase | M | Milestone | Status |
|---|---|---|---|
| 0 | 0 | Scaffold | ☐ |
| 0 | 1 | Schema + RLS + leak test | ☐ |
| 1 | 2 | ⭐ Console v1 | ☐ |
| 1 | 3 | ⭐ Salon-code-first auth | ☐ |
| 1 | 4 | ⭐ Binding + white-label | ☐ |
| 2 | 5 | Catalogue + records + cache | ☐ |
| 2 | 6 | Booking + slots + offline queue | ☐ |
| 3 | 7 | Wallet + payments | ☐ |
| 3 | 8 | Reminders + push ack | ☐ |
| 3 | 9 | Refer & Earn | ☐ |
| 3 | 10 | Dashboard + cohorts | ☐ |
| 4 | 11 | Billing + dunning | ☐ |
| 4 | 12 | DPDP + observability | ☐ |
| 5 | 13 | Release + Play Store | ☐ |
| — | — | **§9 gate — first paying salon** | ☐ |
| 6 | 14+ | Tier 2 | ☐ |
| 7 | 15+ | Tier 3 | ☐ |

**Track B** (§8) runs alongside from Phase 0 and has its own checklist there.
