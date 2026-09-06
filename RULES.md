# Cray Salon — Rules

**Read this before writing any code. Every session.**

This is the compressed, imperative form of `ARCHITECTURE.md`. It tells you what to do.
`ARCHITECTURE.md` tells you *why*, and `Cray-Salon-PRD-v4.md` tells you *what to build*.

| | |
|---|---|
| **Applies to** | Cray Salon — Flutter app, Supabase backend, Next.js console on Vercel |
| **Companions** | `ARCHITECTURE.md` (mechanisms) · `Cray-Salon-PRD-v4.md` (scope) · `DESIGN.md` (visual) · `PHASES.md` (order) · `IMPLEMENTATION.md` (screens, routes, API) |
| **Status** | Binding. A rule here is not a preference |

**How to use this file.** §1 is the ten rules that matter most — if you remember nothing else,
remember those. §2 lists things that **deliberately do not exist**; check it before building
anything that sounds reasonable. §3–§11 are the full rules by area. §12 is the release gate.

**If a rule blocks you, do not work around it.** Several of these are licensing or legal
boundaries and look like arbitrary friction from inside a single task. Say what you're blocked
on and ask.

---

## 1. The ten that matter most

1. **Every table has `salon_id`. Every query is tenant-scoped. RLS is enabled *and forced*.**
   Never write a query that can return another salon's data.
2. **One phone number = one active salon binding.** No switch path in the app, no such API.
3. **Money never moves by hand.** No owner, no manager, nobody at the salon can change a customer's
   balance. Five callers may post to a ledger; that list is closed (§5.2).
4. **Ledgers are append-only.** Reversals are new rows. Never `UPDATE`, never `DELETE`.
5. **Customer money settles into the salon's own Razorpay account.** Crayora holds no float, ever.
6. **Salons are created only through the console** — never SQL, never a migration, never a deploy.
7. **Salon code comes before login.** Never authenticate before the salon is known.
8. **Secrets are server-side only, encrypted at rest, never readable back** through any UI or API.
9. **Mark-complete works offline and syncs idempotently.** Money does not move offline.
10. **The leak tests are release gates.** Never skipped, never deleted, never narrowed to pass.

---

## 2. Things that do not exist — do not build them

Each of these was **deliberately removed**. They look like reasonable features. They are not
missing; they are absent on purpose. If a ticket asks for one, escalate rather than implement.

| Do not build | Why it does not exist |
|---|---|
| A wallet adjustment screen, endpoint, or permission for owners/managers | Largest internal-fraud surface in the product. An off-by-default permission is one support request away from being on |
| Any way to expire **paid** credit | Unfair contract term under the Consumer Protection Act 2019; weakens the closed-loop position |
| A refund-to-bank or cash-out path | Closed-loop is what keeps this outside RBI PPI licensing |
| A Crayora-held balance, float, or payout flow | Would make Crayora an unlicensed payment aggregator |
| Credit usable at a salon other than the issuer | Would make the wallet a semi-closed PPI, requiring authorisation |
| A "switch salon" / "join another salon" screen or API | Binding is exclusive; changes are audited Crayora-support actions only |
| Runtime launcher-icon replacement | Android compiles the launcher icon into the APK. Use the pinned home-screen shortcut |
| OTP templating, branding, or validation | The OTP template and sender belong to Message Central and cannot be changed by code |
| An in-app owner self-signup or self-provisioning wizard | Crayora provisions salons; owners do not |
| A hard delete of any row in `invoices`, `payments`, `wallet_transactions`, `loyalty_ledger` | Statutory retention. Archive and anonymise instead |
| A global phone-number lookup across salons | Cross-tenant enumeration |

---

## 3. Tenancy and isolation

3.1 `salon_id uuid not null` on every tenant table, and the **first column of every composite
index**.

3.2 `enable row level security` **and** `force row level security` on every tenant table. Without
`force`, the table owner bypasses RLS and a migration silently sees everything.

3.3 Policies target `to authenticated`. Never `to public`. `to anon` only for the salon-code
resolver.

3.4 Inside a policy, write `(select auth.uid())`, never bare `auth.uid()` — the subquery form is
hoisted out of the per-row loop.

3.5 Tenant lookups go through the `stable security definer` helpers (`app.current_salon_id()`,
`app.salon_writable()`). Do not inline the JWT parse.

3.6 `DELETE` policies exist for almost nothing. Use statuses.

3.7 All Supabase access from the app goes through `SupabaseGateway`. CI fails the build on `.from(`
or `.rpc(` outside `lib/data/remote/`.

3.8 `customer_identities` and `binding_events` are cross-tenant and have **zero policies**. No
tenant role may read them. Access only via `security definer` functions.

3.9 Writes are gated on `app.salon_writable()` so a suspended or past-due tenant loses
`INSERT`/`UPDATE` at the database, not in the UI.

---

## 4. Identity, binding and the join flow

4.1 **Salon code first, then login.** The app resolves the code, themes itself, shows the salon
name, and only then asks for a phone number.

4.2 One phone number has exactly **one active binding**. Enforced by the `customer_identities`
primary key, not by application logic.

4.3 Binding completes **in the same step as first login**. The unbound state is a crash-recovery
edge case, not a place to put features.

4.4 The "already registered" error **never names the other salon**. That would be a cross-tenant
leak dressed as an error message.

4.5 Unbind and transfer are `app_admin.*` functions, super-admin only, reason-required, writing
`audit_log` **and** `binding_events` in the same transaction.

4.6 A transfer moves the binding and **nothing else** — wallet, history, loyalty and packages stay
with the old salon. `acknowledged_balance_paise` is a required parameter, so support cannot
complete a transfer without having looked up and disclosed the balance.

4.7 Phone numbers are stored as a **peppered HMAC**, pepper in Vault. A plain hash over a ~10⁹
keyspace is equivalent to plaintext.

4.8 Accounts are for the phone holder, who must be an adult. A child's details are a note on an
adult's record, never an account.

---

## 5. Money

### 5.1 Ledger integrity

5.1.1 `wallet_transactions` and `loyalty_ledger` are append-only. Enforced twice: `revoke update,
delete`, **and** a `before update or delete` trigger that raises — the trigger catches
service-role mistakes the grant does not.

5.1.2 All money is `bigint` **paise**. Never float. Never client-side decimal.

5.1.3 The only write path is a `security definer` function that takes a `for update` lock on
`wallet_accounts`, recomputes, inserts, and updates the cached balance in one transaction.
Without that lock, two concurrent checkouts both read a stale balance and overdraw.

5.1.4 `balance_after` is written by that function. Never by a client.

5.1.5 Nightly reconciliation **alerts on drift, never heals it**. Drift is a P1.

### 5.2 The five callers

Only these may post to a ledger. The list is closed and asserted by test:

| # | Caller | Trigger |
|---|---|---|
| 1 | `app.wallet_credit_from_payment` | A **captured** Razorpay webhook |
| 2 | `app.wallet_debit_at_checkout` | A spend, via the allocation waterfall |
| 3 | `app.wallet_expire_lot` | Automation L — **bonus lots only** |
| 4 | `app.referral_release_reward` | Automation D, after a paid first visit |
| 5 | `app_admin.wallet_correct` | Crayora super-admin only, reason-required, audit-logged |

### 5.3 Credit rules

5.3.1 Paid and bonus credit are **separate lots** with independent expiry.

5.3.2 Spend order: **package → wallet → gateway**; within wallet, **bonus first, then paid, both
FIFO by expiry**.

5.3.3 **Bonus credit may expire** (default 180 days, set by the owner **in the app**). **Paid
credit never expires** — there is no field and no code path.

5.3.4 Expiry terms are **captured onto the lot at issue time**, never read live. Changing the rule
affects only credit issued afterwards.

5.3.5 Top-ups are non-refundable **on request**, but: a cancelled service reverses **into** the
wallet, and if the salon closes, is suspended, or the customer transfers away, **the salon must
settle the outstanding balance**. Never silently forfeit.

5.3.6 The Add Money screen shows, **before payment**: bonus amount, bonus expiry, that paid credit
never expires, that credit works only at this salon, and that it cannot be withdrawn as cash.

### 5.4 Payments

5.4.1 Each salon uses **its own Razorpay account**. Crayora never receives, holds, pools or
disburses customer money.

5.4.2 Webhooks are the source of truth, not the client callback.

5.4.3 Resolve the salon from the **webhook path token**, never from the request body — the body is
attacker-controlled.

5.4.4 Verify the signature with **that salon's** secret. Dedupe on `webhook_events(provider,
event_id)` — insert first, then process. Re-verify the amount against the order before posting
credit.

5.4.5 Credit is posted **only** on `captured`.

5.4.6 Booking line items snapshot price and duration at booking time. Re-pricing a service must
never rewrite past revenue.

---

## 6. Provisioning and the console

6.1 Salons are created **only** through the console. No console action may require SQL, a
migration, or a deploy.

6.2 Provisioning is **one transaction**. A failure creates nothing — no half-provisioned tenant,
no orphaned code.

6.3 **Activation is always a deliberate human action.** Nothing else may flip `setup → active` —
no payment event, no timer, no side effect of saving a form.

6.4 The setup fee is collected **offline**. The console records amount, date, reference and who
marked it paid. There is no payment integration for it.

6.5 **Every admin mutation goes through an `app_admin.*` function that writes `audit_log` in the
same transaction.** A route handler cannot forget the audit because the write and the log are one
statement.

6.6 The service role key is used for exactly one thing: calling `app_admin.*`. It lives in Edge
Function secrets and Vercel **server** env. Never in a browser bundle, never in the APK.

6.7 Admin accounts require MFA and never carry a `salon_id` claim.

6.8 Support mode is time-boxed, reason-required, and reads through PII-masking views. Un-masking is
a separate, separately-logged action.

6.9 The console can change a salon's **status**. It can never delete its data.

6.10 The owner logs into the **same Android app** with the mobile number registered in the console.
No owner self-signup.

---

## 7. Messaging

### 7.1 Who sends

7.1.1 Every message — OTP included — sends from **the salon's own** Message Central and WhatsApp
Business accounts, from day one.

7.1.2 **No DLT registration anywhere.** Message Central is top-up-and-send.

7.1.3 Crayora's account is a **fault-only fallback** (credentials missing, untested, send failed).
Never a normal state, so every occurrence is logged, counted **and alerted**.

7.1.4 OTP sender resolution, server-side, from our own tables — never from client-supplied data:
pending join intent → existing binding → owner/staff record → **refuse**.

7.1.5 A request with no salon context is **refused**. There is no code path that sends.

### 7.2 Three tiers of message control

| Channel | Authored by | We store | Branding |
|---|---|---|---|
| **Push** | Us, entirely | Full body text per locale | **Full and guaranteed** |
| **WhatsApp** | The operator, in the **Message Central dashboard**, per salon at setup | Template ID and variable order only — **never body text** | Full, once written there |
| **RCS** | The operator, in the Message Central portal, per salon agent | Template id + variable order | **Full and native** — the verified agent carries the salon's name and logo |
| **OTP SMS** | Message Central. Fixed | Nothing | **None** |

7.2.1 Never write code that templates, brands or validates an OTP body. There is no hook.

7.2.2 `{{salon}}` is a **required** variable in every push template. A template without it fails
seed-time validation.

7.2.3 We can validate that a WhatsApp template exists per key and locale and that variable counts
match. We cannot validate wording — that is an operator checklist item.

### 7.3 The channel ladder

7.3.1 Order: consent check → **push** → **RCS** → WhatsApp → SMS. RCS sits above WhatsApp because
it is cheaper and natively brand-verified, but its reach is conditional — check `rcs_capable(phone)`
(cached) before spending a send, and fall through when it is not.

7.3.2 **Never trust FCM's response as delivery.** It confirms acceptance by Google, nothing more.
Every push carries a `delivery_id`; the app acks on receipt; escalation happens only after an
unacked window (booking 5 min · receipt 15 min · reminder 6 h · billing 1 h).

7.3.3 Mark a token dead immediately on `UNREGISTERED` / `INVALID_ARGUMENT`.

7.3.4 **The ladder degrades, never blocks.** A salon with no approved WhatsApp templates still
works completely — login and push are unaffected. Record `no_channel_available`; do not retry
forever and do not raise an error.

7.3.5 OTP sits outside the ladder: always SMS, never queued, never escalated, no consent gate.

7.3.6 Marketing goes only to customers who opted in. Opt-out is honoured at the ladder's first step.

### 7.4 The OTP hook

7.4.1 **Verify Supabase's hook signature and reject anything else.** An open hook URL is a free-SMS
machine pointed at someone's bill.

7.4.2 Never log the OTP token — not in logs, not in a Sentry breadcrumb, not in an error payload.

7.4.3 Rate-limit **before** sending.

---

## 8. Branding and white-label

8.1 Branding is a server-driven token document with a `version`. A version bump re-themes installed
apps without a reinstall.

8.2 It is fetchable **unauthenticated by salon code** (branding only, `active` salons only,
rate-limited) so the login screen is already the salon's.

8.3 The app and the console consume **one shared token schema**. Otherwise the operator's preview
lies about what the customer sees.

8.4 Never hard-code a colour. CI rejects raw `Color(0x…)` outside the token layer.

8.5 Never block first paint on a font download. Render with the fallback and swap.

8.6 If branding cannot be fetched, render a neutral default. Never a half-themed screen, and
**never another salon's branding**.

8.7 The cached document is authoritative offline — the app stays branded.

8.8 **The launcher icon cannot be changed at runtime.** Offer the pinned home-screen shortcut with
the salon's logo and name. A per-salon signed APK is the only real alternative and is deferred.

8.9 Notification small icon stays a generic monochrome mark (Android renders it as a silhouette).
Large icon, title and channel name are the salon's.

8.10 Publishing branding runs a **contrast check** and blocks an unreadable palette.

---

## 9. Offline

9.1 Offline covers **capture**: mark-complete, walk-in booking, add/edit customer.

9.2 Offline **never** covers money or binding. Both are server-authoritative decisions.

9.3 Every server RPC takes a `client_action_id`. `idempotency_keys(salon_id, key)` is unique; a
replay returns the original result.

9.4 Mark-complete is an idempotent state transition (`confirmed → completed`). Replays are no-ops.

9.5 An offline completion records **intent**. The wallet debit, loyalty award and package decrement
run server-side at sync.

9.6 Rejected offline actions surface in a **"Needs attention"** inbox with the reason and a one-tap
fix. **Never silently dropped.**

---

## 10. Automations and jobs

10.1 Use the **transactional outbox**: domain write → `domain_events` row in the same transaction →
`pg_cron` → `pgmq` → worker. Never fire HTTP from a trigger — it is not transactional.

10.2 Every automation is guarded by a **database** uniqueness or state-transition constraint, not by
"we only call it once". At-least-once delivery plus idempotent handlers is the only combination
that survives retries, redeploys and offline replay.

10.3 Exactly one reminder per cycle, enforced by a unique index on `(salon_id, customer_id,
service_id, cycle_key)`.

10.4 Scheduled scans are **tenant-sharded** — one job per salon. One bad tenant must not stall the
platform.

10.5 Dead-lettered jobs raise a Sentry alert. Work that fails silently is worse than work that
fails loudly.

10.6 Dashboard metrics are pre-aggregated and **reconciled nightly with an alert on mismatch** —
never silently corrected.

---

## 11. Security, privacy and law

11.1 Secrets — platform and per-salon — live server-side only, encrypted at rest (Vault), and are
**never readable back**. The console shows last-4 and a *Test connection* result.

11.2 Rotation replaces; it never reveals.

11.3 Never log phone numbers, OTPs, tokens, secrets, or full payment payloads.

11.4 R2 objects are private by default, keyed `salon/{salon_id}/{kind}/{uuid}`, served by
short-lived presigned URLs issued only after an access check. Photos additionally require
`consent = true`.

11.5 Rate limits: OTP (phone + IP + device + **per salon per day**), `start_join` (tightest — it
causes a paid SMS), salon-code lookup, bind attempts.

11.6 **Consent is a ledger, not a boolean.** Per-purpose, append-only, withdrawal is a new row.
Withdrawal must be as easy as consent.

11.7 **The salon is the Data Fiduciary; Crayora is the Data Processor.** The app shows a
**per-salon** grievance contact, not just a Crayora one.

11.8 Erasure is **anonymisation**: clear name and birthday, replace phone with its salted hash,
detach `auth_user_id`, hard-delete photos from R2, **retain** financial rows against the anonymous
id.

11.9 Purging a salon deletes **operational and personal** data only. `invoices`, `payments`,
`wallet_transactions` and `loyalty_ledger` move to a restricted, anonymised archive for the
statutory period. Offer an export first, and require outstanding credit to be settled.

11.10 A wallet top-up produces a **receipt, never a tax invoice**. GST arises on the service
invoice at redemption. Invoice numbers are sequential per salon per financial year.

11.11 **Licensing boundaries — if a change would cross one, stop and escalate.** It is a licensing
question, not a design question:
- customer money into a Crayora account, or
- credit spendable at a salon that did not issue it.

---

## 12. Definition of done

A change is not done until all of these hold.

**Hard gates — CI fails the build:**

- [ ] **Cross-tenant leak test** — catalogue-driven, so a table added today is covered today
- [ ] **Binding exclusivity test** — double-bind rejected; no tenant-reachable unbind/transfer path;
      the error names no salon
- [ ] **Money test** — no owner/manager-reachable function writes to a ledger; `UPDATE`/`DELETE`
      raise for every role; the ledger-caller set equals the five in §5.2; no paid lot can expire
- [ ] Migrations apply from zero (`supabase db reset`)
- [ ] Secret scan clean, including the APK and the Vercel client bundle
- [ ] Lints: domain purity, no `.from(` outside `data/remote/`, no raw `Color(0x…)`

**Also required:**

- [ ] The feature's PRD acceptance criteria pass
- [ ] Empty, loading and error states exist
- [ ] Offline behaviour matches §9 — including the rejection path
- [ ] Anything user-visible works in `en`, `hi` and `hi_Latn`

---

## 12A. Design

Visual and interaction rules live in **`DESIGN.md`** and are binding. The ones most often broken:

12A.1 The app is **white-labelled** — brand colour, fonts, logo and radius come from the salon.
Never hard-code any of them, and never tint surfaces with the brand colour.

12A.2 `onPrimary`, `brandInk` and every hover/disabled/container step are **derived at publish**,
never entered by an operator. Publish is blocked if contrast fails.

12A.3 **Status and chart colours are never themed.** Chart series use a fixed, CVD-validated
palette capped at three; a fourth series folds into "Other".

12A.4 **Never animate a money value.** No count-up, no ticker.

12A.5 **No bounce or elastic easing.** Skeletons do not shimmer.

12A.6 Money uses **tabular figures** and **Indian grouping** (`₹1,20,500`).

12A.7 A salon serving Hindi customers may only use a **Devanagari-capable** font; Devanagari gets
+2dp line height and zero letter-spacing.

12A.8 Spacing comes from the 4dp scale. Type comes from the role table. No raw hex, no raw sizes.

---

## 13. When you are unsure

- **Mechanism** → `ARCHITECTURE.md` wins.
- **Scope or intent** → `Cray-Salon-PRD-v4.md` wins.
- **They disagree** → fix the loser in the same session; don't leave it for later.
- **A rule blocks the task** → say so and ask. Do not work around it, and do not assume it is
  stale — several of these are licensing boundaries that look like friction from inside one task.
- **You are about to add a capability listed in §2** → stop. It was removed on purpose.
