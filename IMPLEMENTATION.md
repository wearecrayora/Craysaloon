# Cray Salon — Implementation Map

**Every surface, every route, every server call, and who builds it when.**

| | |
|---|---|
| **Companions** | `RULES.md` (binding) · `PHASES.md` (order) · `Cray-Salon-PRD-v4.md` (scope) · `ARCHITECTURE.md` (mechanisms) · `DESIGN.md` (visual) |
| **This file answers** | *What screens exist? What does each one read and write? What is the complete server API? Where does the code live?* |
| **Does not duplicate** | Feature rationale (PRD) · mechanism design (ARCHITECTURE) · component styling (DESIGN) |

> **Read this alongside a milestone card in `PHASES.md`.** The card says what to build; this file
> says exactly which screens and functions that means.

---

## 1. Surface inventory

**Four app shells, one console.** The shell is chosen from `app_role` at session start
(`ARCHITECTURE.md` §9.3). A user never sees two shells at once.

### 1.1 App — Unbound shell (`app_role: customer_unbound`, or no session)

| # | Route | Screen | M |
|---|---|---|---|
| U1 | `/` | Bootstrap — restore session, resolve shell, cached branding | 0 |
| U2 | `/join` | **Salon code** — scan QR or type code | 3 |
| U3 | `/join/confirm` | **Salon confirmation** — *"You're joining &lt;Salon&gt;"*, branded | 3 |
| U4 | `/join/phone` | **Phone entry** — already salon-branded | 3 |
| U5 | `/join/otp` | **OTP verify** — resend with cooldown | 3 |
| U6 | `/join/welcome` | Binding complete → offer home-screen shortcut | 4 |

### 1.2 App — Customer shell (`app_role: customer`)

| # | Route | Screen | M |
|---|---|---|---|
| C1 | `/home` | **Home** — balance, next-visit-due, Book CTA, active offer | 7 |
| C2 | `/wallet` | **Wallet** — balance, paid/bonus breakdown, history | 7 |
| C3 | `/wallet/add` | **Add Money** — packs, **disclosure block**, pay | 7 |
| C4 | `/wallet/add/result` | Payment result — success / pending / failed | 7 |
| C5 | `/book/service` | Book ① service select | 6 |
| C6 | `/book/addons` | Book ② **add-ons — never pre-selected** | 6 |
| C7 | `/book/slot` | Book ③ barber + slot | 6 |
| C8 | `/book/review` | Book ④ review, total, confirm | 6 |
| C9 | `/booking/:id` | Booking detail — reschedule / cancel | 6 |
| C10 | `/visits` | Visit history | 5 |
| C11 | `/refer` | **Refer & Earn** — code, share, pending/successful | 9 |
| C12 | `/settings` | Settings — language, notifications | 4 |
| C13 | `/settings/privacy` | **Consent per purpose**, export, delete request | 12 |
| C14 | `/feedback/:visitId` | Post-visit rating *(Tier 2)* | 14+ |

### 1.3 App — Owner shell (`app_role: owner` / `manager`)

| # | Route | Screen | M |
|---|---|---|---|
| O1 | `/day` | **Day view — mark-complete. The most important screen.** | 5 |
| O2 | `/day/walk-in` | Add walk-in booking | 6 |
| O3 | `/attention` | **Needs attention** — rejected offline actions | 6 |
| O4 | `/customers` | Customer list — keyset paginated, searchable | 5 |
| O5 | `/customers/:id` | Customer detail — history, **balance read-only** | 5 |
| O6 | `/dashboard` | **Dashboard** — stat tiles + cohort chart | 10 |
| O7 | `/catalogue/services` | Services CRUD | 5 |
| O8 | `/catalogue/addons` | Add-ons CRUD + relevance | 5 |
| O9 | `/staff` | Staff + working hours | 5 |
| O10 | `/settings/rules` | **Wallet bonus rule + bonus expiry**, reminder cycles, cancellation policy | 7 |
| O11 | `/settings/hours` | Working hours, holidays | 5 |
| O12 | `/billing` | Subscription status, plan, **messaging spend per channel beside reminder conversion** (never one without the other), marketing-escalation setting (SMS default / WhatsApp opt-in) | 11 |
| O13 | `/salon` | Salon profile — display name, branding *(read-only)* | 4 |

> **O5 shows a balance and cannot change it.** There is no adjust control, no endpoint, and no
> permission (`RULES.md` §2). If a screen sketch contains one, the sketch is wrong.

### 1.4 App — Staff shell *(Tier 2)*

| # | Route | Screen | M |
|---|---|---|---|
| S1 | `/my/schedule` | Own schedule + assigned bookings | 14+ |
| S2 | `/my/schedule/:id` | Mark complete, add-on/bill update, tip | 14+ |
| S3 | `/my/earnings` | Commission from completed visits | 14+ |

### 1.5 Console (Next.js on Vercel)

| # | Route | Screen | M |
|---|---|---|---|
| K1 | `/login` | Admin login — **MFA required** | 2 |
| K2 | `/salons` | Salon list — status, plan, **bind rate**, last active | 2 |
| K3 | `/salons/new` | **Provision wizard** — identity → branding → catalogue → rules → integrations → commercials → owner | 2 |
| K4 | `/salons/:id` | Salon overview | 2 |
| K5 | `/salons/:id/branding` | **Branding studio** — live preview, contrast gate, publish | 2 |
| K6 | `/salons/:id/catalogue` | Services, add-ons, staff, rules | 2 |
| K7 | `/salons/:id/credentials` | **Write-only** secrets + *Test connection* | 2 |
| K8 | `/salons/:id/messaging` | WhatsApp template status, RCS agent status, send/ack rates **and cost per channel**, **OTP fallback count** | 8 |
| K9 | `/salons/:id/qr` | QR pack — regenerate, download PDF | 2 |
| K10 | `/salons/:id/billing` | Record offline setup fee · **activate** · subscription · dunning | 11 |
| K11 | `/salons/:id/support` | **Support mode** — time-boxed, reason, masked PII | 12 |
| K12 | `/customers/binding` | **Unbind / transfer** — reason + acknowledged balance | 4 |
| K13 | `/customers/wallet-correct` | **The only human path to a balance** | 7 |
| K14 | `/metrics` | MRR, churn, activation, push:WhatsApp, time-to-first-bind | 11 |
| K15 | `/flags` | Per-salon feature flags | 11 |
| K16 | `/audit` | Audit log — filter by salon, actor, action | 2 |

---

## 2. Screen specs — the ones that carry real complexity

The rest follow the patterns in `DESIGN.md` §6. These do not.

### U2–U6 · The join flow *(M3–M4)*

| | |
|---|---|
| **Entry** | Cold open · QR deep link `https://join.craysalon.in/s/<code>` (code pre-filled) · Play Install Referrer |
| **Reads** | `app.resolve_join_code(code)` → `{display_name, branding}` — **anon**, rate-limited |
| **Writes** | `app.start_join(code, phone)` → `join_intents` · `supabase.auth.signInWithOtp` · `app.bind_customer(...)` |
| **States** | Idle · scanning (camera permission denied → manual entry) · resolving · **invalid code** · **salon not active** · rate-limited · OTP sent · OTP wrong (attempts left) · OTP expired · **already bound** · binding · bound |
| **Theming** | From U3 onward the app wears the salon's branding — logo, palette, fonts. This is the moment the white-label promise is kept |

**Rules that bite here**

- The app themes itself **before** the phone screen. Never authenticate before the salon is known.
- **`already_bound` never names the other salon.** Copy: *"This number is already registered with a
  salon."* Nothing more.
- The OTP screen is salon-branded, because **the SMS itself cannot be** (`DESIGN.md` §9 / PRD
  §12.1a). This screen carries the identity the SMS can't.
- Binding and first login complete together. If the app dies between them, U1 finds the live
  `join_intent` on resume and completes silently; an expired intent returns to U2 with a plain
  explanation.
- Camera permission denial is a **first-class path**, not an error — typing the code is equal.

### C3 · Add Money *(M7)* — the highest-risk screen in the product

| | |
|---|---|
| **Reads** | `salons.wallet_rule` (bonus rule, min top-up, **bonus expiry days**) |
| **Writes** | Edge Function `create-payment-order` → Razorpay (the **salon's** account) |
| **States** | Idle · amount chosen · creating order · gateway open · pending · **captured** · failed · cancelled |

**The disclosure block sits above the pay button. Body size. Not collapsed. Not behind a link.**
It states, in the customer's language:

1. the amount and the bonus (`₹500 → ₹550`);
2. the **bonus expiry date**, as a date;
3. **paid credit never expires**;
4. usable **only at this salon**;
5. **cannot be withdrawn as cash**.

Credit posts **only** on webhook `captured` — never on the client callback (`RULES.md` §5.4.5).
The result screen (C4) must survive the app being killed mid-payment: on resume it polls payment
status rather than assuming failure.

### O1 · Day view *(M5–M6)* — the screen everything depends on

| | |
|---|---|
| **Reads** | Bookings for the selected day, from the **local cache first**, reconciled with the server |
| **Writes** | `app.mark_visit_complete(booking_id, final_amount, tip, client_action_id)` — idempotent, queued when offline |
| **States** | Loading · empty · list · **offline banner** · row-pending-sync · row-rejected |

- **Mark-complete is one tap. No confirm dialog.** The undo is tapping again.
- Feedback is **immediate and local** — the row settles at once whether or not the network
  answered. Offline is the normal case.
- A pending row shows a sync indicator; it is **not** an error style.
- A rejected row moves to O3 with the reason and a one-tap fix, and is **never** silently dropped.
- Nothing on this screen may wait on an animation or a network round-trip.
- **This screen must be fully usable in airplane mode.** That is a test, not an aspiration.

### C6 · Add-ons *(M6)*

Every add-on renders **unchecked**, always. Rows show name, `+₹price`, `+N min`. The running
total **and** the duration update on the same frame as the tap — no debounce, no spinner.
Changing add-ons changes the required slot length, so the slot grid on C7 must visibly refresh
rather than silently re-filter. Unavailable add-ons are **removed**, not greyed.

### O6 · Dashboard *(M10)*

Stat tiles (`DESIGN.md` §6.6), not charts: today's revenue, today's bookings, average bill,
repeat vs new, wallet collected, outstanding credit, reminder-generated bookings, **bind rate**.
Below them, the **cohort retention chart** — 30/60/90-day return, wallet vs non-wallet:

- Two series → `series1` / `series2`, fixed assignment (`DESIGN.md` §9.1).
- Legend **and** direct labels. Y axis `0–100%`, labelled.
- Tooltip carries the exact figures **and the cohort size** — a rate without an `n` is a claim
  without evidence.
- A **table view** of the same numbers sits below. It is the accessibility fallback and the thing
  the owner will screenshot.

All figures come from `daily_salon_metrics` / `retention_cohorts`, never from live aggregation.

### K3 · Provision wizard *(M2)*

Seven steps — identity, branding, catalogue, rules, integrations, commercials, owner — but
**one transaction** at the end (`ARCHITECTURE.md` §5.7). A failure creates nothing.

The wizard saves a **local draft** between steps so a 25-minute session survives a refresh; the
draft is not a database row. On submit, `app_admin.provision_salon(payload)` runs everything and
leaves the salon in status `setup`. **Activation is a separate, deliberate click** on K10.

### K5 · Branding studio *(M2)*

Live preview rendered from `packages/design-tokens` — the same package the Flutter app consumes,
so the preview cannot lie (`ARCHITECTURE.md` §7.2). Publish runs the **contrast gate** and is
**blocked** on failure, naming the failing pair. Publishing bumps `salon_branding.version`, which
re-themes installed apps on their next open.

---

## 3. Server API surface

### 3.1 Postgres RPCs — customer/owner reachable

| Function | Caller | Returns | Guarantees |
|---|---|---|---|
| `app.resolve_join_code(code)` | **anon** | `{display_name, branding}` | Active salons only · nothing else, ever · rate-limited |
| `app.start_join(code, phone)` | **anon** | `{ok}` | Writes `join_intents` (15 min TTL) · tightest rate limit in the system |
| `app.bind_customer(code)` | `customer_unbound` | `{customer_id}` | Atomic · consumes intent · seeds consent · bumps `cver` · `already_bound` names no salon |
| `app.get_branding()` | any tenant | token document | Tenant-scoped |
| `app.available_slots(salon_id, service_id, staff_id, date)` | customer, owner | slot list | Same function client and server use |
| `app.create_booking(...)` | customer, owner | `{booking_id}` | Idempotent on `client_action_id` · exclusion constraint decides conflicts |
| `app.cancel_booking(booking_id, reason)` | customer, owner | `{ok}` | Status transition · emits `booking.cancelled` |
| `app.mark_visit_complete(booking_id, final_amount, tip, client_action_id)` | owner, staff | `{visit_id}` | **Idempotent** · offline-queued · emits `visit.completed` |
| `app.record_consent(purpose, granted)` | customer | `{ok}` | Append-only |
| `app.ack_notification(delivery_id)` | any tenant | `{ok}` | Stamps `acked_at` — gates escalation |
| `app.request_data_export()` | customer | `{job_id}` | DPDP |

### 3.2 Postgres RPCs — internal only (jobs and workers)

`app.wallet_credit_from_payment` · `app.wallet_debit_at_checkout` · `app.wallet_expire_lot`
*(bonus lots only — raises on a paid lot)* · `app.referral_release_reward` · `app.rl_consume`
· `app.resolve_otp_sender`.

**These five are the complete set of ledger callers** together with `app_admin.wallet_correct`
(`RULES.md` §5.2). The money leak test asserts the set has not grown.

### 3.3 `app_admin.*` — console server routes only

Every one writes `audit_log` **in the same transaction**. There is no way to call one without
being logged.

| Function | Notes |
|---|---|
| `provision_salon(payload)` | One transaction; leaves status `setup` |
| `activate_salon(salon_id, reason)` | The **only** path to `active`. Never automatic |
| `suspend_salon` / `reactivate_salon` | Status only. Never deletes |
| `publish_branding(salon_id, tokens)` | Runs the contrast gate; bumps `version` |
| `set_integration_secret(salon_id, provider, secret)` | **Write-only. No read counterpart exists** |
| `test_integration(salon_id, provider)` | Returns pass/fail + reason. Never the credential |
| `unbind_customer(phone_hash, reason)` | Correction path |
| `transfer_customer(phone_hash, to_salon_id, reason, acknowledged_balance_paise)` | **Refuses without the acknowledged balance** |
| `wallet_correct(customer_id, amount_paise, reason)` | The only human path to a balance |
| `record_setup_fee(salon_id, amount_paise, paid_on, reference)` | Offline payment record |
| `start_support_session(salon_id, reason)` | Time-boxed; every read inside is logged |

### 3.4 Edge Functions

| Function | Trigger | Identity | Must |
|---|---|---|---|
| `sms-hook` | GoTrue Send-SMS hook | service role | **Verify the hook signature** · resolve sender via `resolve_otp_sender` · never log the token · rate-limit before send · fall back to platform + alert |
| `rzp-webhook/{token}` | Razorpay, **per salon** | service role | Resolve salon **from the path token**, never the body · verify with that salon's secret · dedupe on `event_id` · re-verify amount |
| `create-payment-order` | Client | user JWT | Compute the amount **server-side** |
| `dispatcher` | `pg_cron`, 1 min | service role | Drain `domain_events` → `pgmq` |
| `worker` | `pgmq` | service role | Idempotent handlers; dead-letter → Sentry |
| `notification-send` | worker | service role | The **category-aware** ladder: utility = push -> WhatsApp Utility -> SMS; marketing = push -> SMS -> WhatsApp Marketing (owner opt-in only). Salon credentials; skips unapproved WhatsApp cleanly; RCS rung designed but unpriced |
| `escalation-sweep` | `pg_cron`, 1 min | service role | Promote unacked pushes past their window |
| `export-customer-data` | RPC job | service role | JSON+CSV → R2 → 7-day signed URL |
| `qr-pack-render` | Console | service role | PDF → R2 → signed URL |

**Console admin API is Next.js route handlers**, not Edge Functions — they hold the service role
server-side and call `app_admin.*` (`ARCHITECTURE.md` §14.1).

---

## 4. Critical flows

### 4.1 Join *(M3–M4)*

```
scan/type code ──► app.resolve_join_code        (anon, rate-limited)
                        │ branding + name
                        ▼
                   theme the app  ◄── the white-label promise is kept here
                        │
                   confirm salon
                        ▼
                   app.start_join(code, phone)   ──► join_intents (15 min)
                        │
                   signInWithOtp ──► sms-hook ──► resolve_otp_sender
                        │                              │ intent → salon
                        │                              ▼
                        │                     salon's Message Central
                        │                     (platform fallback + alert)
                   verify OTP
                        ▼
                   app.bind_customer  ──► customer_identities (atomic)
                                      ──► customers + consent defaults
                                      ──► binding_events
                                      ──► cver++ → token refresh → salon_id claim
                                      ──► domain_event customer.bound → Automation J
```

### 4.2 Offline mark-complete *(M6)*

```
tap ✓ ──► optimistic local state (immediate)
     └──► outbox row { op: mark_complete, client_action_id, payload }

reconnect ──► drain FIFO ──► app.mark_visit_complete(..., client_action_id)
                                   │
              ┌────────────────────┼────────────────────┐
           applied              replay                rejected
              │                (no-op via              │
              ▼               idempotency_keys)        ▼
      domain_event visit.completed                "Needs attention" (O3)
              ▼                                    reason + one-tap fix
   Automation A: last-visit · next-due · ONE reminder
                 loyalty · package decrement · commission · metrics
```

**Money moves server-side, at sync.** The device records intent only (`RULES.md` §9.5).

### 4.3 Top-up *(M7)*

```
C3 Add Money ──► create-payment-order (server computes amount)
                      ▼
              Razorpay — THE SALON'S account
                      ▼
        rzp-webhook/{salon token}  ──► verify sig with that salon's secret
                                   ──► dedupe on event_id
                                   ──► re-verify amount vs order
                                   ──► only on `captured`:
                                          app.wallet_credit_from_payment
                                            → wallet_lots: paid (no expiry)
                                            → wallet_lots: bonus (+expiry, terms captured)
                                            → 2 ledger rows with balance_after
                                   ──► Automation B: receipt
```

### 4.4 Reminder → booking *(M8)*

```
Automation A ──► reminders row (unique on salon+customer+service+cycle_key)
                      ▼
              due ──► notification (intent)
                      ▼
              consent check ──► push (delivery_id)
                                   │
                        acked ─────┴───── not acked past window
                          │                      │
                        done                escalate → salon's WhatsApp
                       cost 0                (or skip if unapproved →
                                              no_channel_available)
                      ▼
              customer books ──► booking.confirmed ──► Automation C
                                                       stops duplicate reminders
```

---

## 5. File map

```
/
  CLAUDE.md  RULES.md  PHASES.md  IMPLEMENTATION.md
  DESIGN.md  ARCHITECTURE.md  Cray-Salon-PRD-v4.md

/packages/design-tokens/          ← consumed by BOTH app and console
  schema.json  tokens.ts  derive.ts  contrast.ts

/app/lib/
  core/        config · errors · result · logging · i18n · connectivity · theme
  data/
    remote/    supabase_gateway.dart   ← the ONLY place `.from(` / `.rpc(` appears
    local/     drift/  daos/  outbox/  branding_cache/
    repositories/
  domain/      entities · value_objects · use_cases      (no supabase import)
  features/
    join/  auth/  wallet/  booking/  customers/  day/
    attention/  dashboard/  referral/  settings/  staff/
  app/         router · shells · di
/app/l10n/     app_en.arb  app_hi.arb  app_hi_Latn.arb

/console/
  app/(auth)/login/
  app/salons/[id]/{branding,catalogue,credentials,messaging,qr,billing,support}/
  app/{customers,metrics,flags,audit}/
  server/admin/            ← service role lives here, calls app_admin.* only
  components/branding-preview/   ← renders from packages/design-tokens

/supabase/
  migrations/    0001_schema · 0002_rls · 0003_functions · 0004_constraints …
  functions/     sms-hook · rzp-webhook · create-payment-order · dispatcher ·
                 worker · notification-send · escalation-sweep ·
                 export-customer-data · qr-pack-render · _shared/
  tests/         rls/ (leak + binding) · money/ · bookings/ · automations/
  seed/

/docs/adr/   /docs/runbooks/
```

---

## 6. Traceability

Feature → surfaces → server calls → milestone. Use this to check nothing is orphaned.

| Feature (PRD) | Screens | Server | M |
|---|---|---|---|
| Provisioning §6.2 | K3, K5–K7, K9 | `provision_salon`, `publish_branding`, `set_integration_secret`, `qr-pack-render` | 2 |
| Activation §6.2 | K10 | `record_setup_fee`, `activate_salon` | 2/11 |
| Join & binding §6.4–6.5 | U2–U6 | `resolve_join_code`, `start_join`, `sms-hook`, `bind_customer` | 3–4 |
| White-label §6.6 | all app screens, K5 | `get_branding` | 4 |
| Transfer / unbind §6.5 | K12 | `unbind_customer`, `transfer_customer` | 4 |
| Catalogue §8.2 | O7–O9, K6 | table CRUD (RLS) | 5 |
| Booking + add-ons §9.3 | C5–C9, O2 | `available_slots`, `create_booking` | 6 |
| Mark-complete §4 | O1, S2 | `mark_visit_complete` → Automation A | 5–6 |
| Offline queue §15 | O1, O3 | outbox + `idempotency_keys` | 6 |
| Wallet §9.1 | C1–C4, O5, O10 | `create-payment-order`, `rzp-webhook`, ledger callers | 7 |
| Wallet correction §8.5 | K13 | `wallet_correct` | 7 |
| Reminders §9.2 | push only | Automations A, C, K · `ack_notification` · ladder incl. RCS | 8 |
| Refer & Earn §9.4 | C11 | `referral_release_reward` (D) | 9 |
| Dashboard §9.5 | O6 | `daily_salon_metrics`, `retention_cohorts` (E) | 10 |
| Billing §14 | O12, K10, K14 | Automation I | 11 |
| DPDP §16A.4 | C13, K11 | `record_consent`, `request_data_export`, anonymise | 12 |

---

## 7. Screen build checklist

Apply to **every** screen before calling it done. This is `DESIGN.md` §13 in a per-screen form.

- [ ] **Four states** — empty, loading (static skeleton, no shimmer), error, **offline**
- [ ] Renders under a **dark brand, a pale brand, and the neutral default**
- [ ] Renders in **light and dark**, stamped and system
- [ ] `en`, `hi` (Devanagari metrics), `hi_Latn` (longest strings) — no clipping
- [ ] **200% text scale** — no clipping, no overlap
- [ ] Targets ≥48dp; primary action reachable one-handed
- [ ] Money: tabular figures, Indian grouping, labelled
- [ ] No raw hex, no raw font size, no off-scale spacing
- [ ] Reduced motion honoured; **no money animates**
- [ ] Every interactive element has a semantic label
- [ ] Reads are tenant-scoped through `SupabaseGateway`
- [ ] Writes that can happen offline carry a `client_action_id`
