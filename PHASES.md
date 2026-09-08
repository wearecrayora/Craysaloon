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
| **Not yet** | Billing screens (M11) · support mode (M12) · platform metrics (M11) · transfer/unbind (M4) · **“Test connection” (M3)** — verifying a credential means *using* it, and decryption belongs inside an Edge Function at the moment of use (§8.1). Storing is write-only and done; a stored credential simply stays `untested` until then, and the console says so rather than implying otherwise |
| **Done when** | Someone who has never seen the codebase provisions a salon end to end in <30 min · no step touches SQL · a saved secret cannot be read back through UI or API · a failing palette **blocks** publish · `setup → active` happens only by explicit human action · every action appears in `audit_log` |

### M3 — Salon-code-first auth ⭐

| | |
|---|---|
| **Read** | `RULES.md` §4, §7.1, §7.4 · PRD §6.4, §12.1, §12.1a · ARCHITECTURE §5.1, §5.2, §5.6 |
| **Build** | `resolve_join_code()` returning display name + branding, `anon`-callable, rate-limited · `start_join(code, phone)` writing `join_intents` · the `sms-hook` Edge Function with **signature verification** · `resolve_otp_sender()`: intent → binding → staff → **refuse** · platform fallback with alerting · the custom access token hook minting claims · rate limits per phone / IP / device / salon-per-day |
| **Not yet** | Binding itself (M4). Auth ends at a valid session |
| **Done when** | An OTP request with no salon context is **refused** · the hook rejects unsigned requests · the token never appears in any log or breadcrumb · a salon with broken credentials falls back **and alerts** · the login screen already wears the salon's branding |

> **Note:** the Message Central platform account must exist before this milestone starts (§8).

### M4 — Binding and white-label ⭐

| | |
|---|---|
| **Read** | `RULES.md` §4, §8, §12A · PRD §6.5, §6.6 · ARCHITECTURE §5.4, §5.5, §7 · `DESIGN.md` §3, §5.3, §6 |
| **Build** | `bind_customer()` — atomic, consuming the join intent, bumping `cver` · the confirmation screen naming the salon · **`already_bound` that never names the other salon** · `app_admin.unbind_customer` / `transfer_customer` with required `acknowledged_balance_paise` · **consent defaults written at binding** (dependency ③) · full theming from tokens, cached offline · pinned home-screen shortcut · per-salon notification channel |
| **Not yet** | The launcher icon. It cannot be changed at runtime (RULES §2) |
| **Done when** | The binding-exclusivity test passes · no tenant-reachable switch/unbind/transfer path exists · a transfer leaves wallet and history with the old salon · the app re-themes without a restart · it renders correctly under a dark brand, a pale brand and the neutral default · consent rows exist for every bound customer |

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

**M6 — Booking, slots, add-ons, offline queue.** The exclusion constraint, `app.available_slots()`
shared by client and server, `booking_items` **with price snapshots** (dependency ④), the outbox,
and the **"Needs attention"** inbox.
*Read:* `RULES.md` §9 · PRD §9.3 · ARCHITECTURE §6.5, §10 · `DESIGN.md` §6.3, §6.4, §6.5.
*Done when:* two concurrent bookings for the same barber cannot both succeed · **no add-on is ever
pre-checked** · mark-complete is one tap and works offline · a rejected offline action surfaces
with a one-tap fix and is never dropped.

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

**M8 — Reminders and push.** Automations A, C, K; the ack protocol; learned intervals.
*Read:* PRD §9.2, §10.1, §12 · ARCHITECTURE §6.6, §6.7, §11, §12.
*Done when:* exactly one reminder per cycle (enforced by index, not code) · escalation is
**ack-gated**, never FCM-response-gated · a salon without approved WhatsApp templates still works
completely.

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
