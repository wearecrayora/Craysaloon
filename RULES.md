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
| Runtime launcher-icon replacement | Both platforms compile the icon at build time. Android: use the pinned home-screen shortcut. **iOS has no equivalent at all** - in-app branding only (RULES 8.11) |
| OTP templating, branding, or validation | The OTP template and sender belong to Message Central and cannot be changed by code |
| An in-app owner self-signup or self-provisioning wizard | Crayora provisions salons; owners do not |
| A hard delete of any row in `invoices`, `payments`, `wallet_transactions`, `loyalty_ledger` | Statutory retention. Archive and anonymise instead |
| A global phone-number lookup across salons | Cross-tenant enumeration |
| **Promotional SMS** - any marketing campaign delivered by SMS | Message Central's own DLT registration covers the OTP and service messages it sends under its name. Nobody has confirmed **in writing** that it extends to a salon's marketing content, and unregistered promotional SMS is a TRAI/TCCCPA violation billed to whoever sent it. Decision of 28 Sep 2026: **no promotional SMS until that confirmation exists.** Push and WhatsApp marketing are unaffected, and push is preferred anyway (§12) |
| **Any owner, manager or staff screen, endpoint or permission to view or change the salon's provider credentials** — Message Central Customer ID or token, Razorpay keys, WhatsApp, RCS | They are set and changed **only by Crayora**, in the super-admin console, behind MFA, audited (8.12). A salon-side path would put the account that receives customers' money one stolen owner phone away from an attacker: change the Razorpay key and every top-up lands in someone else's account |

---

## 3. Tenancy and isolation

3.1 `salon_id uuid not null` on every tenant table, and the **first column of every composite
index that serves a tenant query**.

The reason is not tidiness. Forced RLS adds an implicit `salon_id = app.current_salon_id()` to
every tenant query, so an index that does not lead with `salon_id` cannot serve it, and the
fallback scan gets slower with every salon onboarded.

Three kinds of index are exempt, because leading with `salon_id` would make them **wrong**, not
merely redundant:

- **Global uniqueness constraints.** Webhook idempotency (`webhook_events (provider, event_id)`)
  must hold across every salon. Adding `salon_id` would let the same provider event be replayed
  under a second tenant — a security defect, not an optimisation.
- **Partial indexes over the global rows**, defined `where salon_id is null` (the default message
  templates). There is nothing to lead with.
- **Natural-key primary keys of join tables**, where `salon_id` is implied by the other columns
  and a separate `(salon_id, …)` index serves the lookups — as `service_addons` does.

Enforced by `supabase/tests/rls/index_scope_test.sql`, which is catalogue-driven and carries the
exemptions by name. A new violation fails CI and has to be argued for in that file.

> This rule originally said "every composite index", full stop. An audit found four indexes
> breaking it and concluded all four were correct — the rule was wrong. Following it literally
> would have opened the webhook replay hole described above.

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

3.8a **A customer sees their OWN rows, not their salon's.** Tenant scoping is necessary and not
sufficient: `authenticated` includes customers, so `salon_id = app.current_salon_id()` alone lets
one customer read every other customer of the salon. Ownership is enforced by a **RESTRICTIVE**
policy - `app.current_app_role() <> 'customer' or customer_id = app.current_customer_id()` - on
every table naming a customer, because permissive policies are **OR'd** and a narrow one beside a
broad one grants the union. A new table with a `customer_id` and no restrictive policy **fails CI**
(customer-scope gate). Staff PII (`public.users`) and the salon's own business records (billing,
metrics, audit, schedules) are closed to customers entirely. This is not hypothetical: it shipped,
and it was found by signing in as a real customer (0038, ADR-41).

3.8b **Who may WRITE is a rule, not a screen.** Tenant scoping answers "is this my salon", never
"am I allowed", and no permissive write policy in this schema ever mentioned a role - so a customer
**repriced a service to 1 paisa** in a test, a staff member could have updated their own `role` in
`public.users`, and an owner could have flipped their own salon to `active` or changed the join code
on cards already printed. The write model, enforced by **RESTRICTIVE** policies (0041, 0042):

| May write | Tables |
|---|---|
| **Crayora only** (console) | `salons`, `salon_branding` |
| **Server only** (a `security definer` function, never a device) | `visits`, `booking_items`, `reminders` |
| **Owner or manager** | `services`, `add_ons`, `service_addons`, `staff`, `staff_schedules`, `staff_time_off`, `users`, `message_templates` |
| **Own rows only** | `customers`, `consents`, `notification_tokens`, `bookings` |

`SELECT` is untouched: a customer still reads the menu, or they cannot book. A new tenant-writable
table **fails CI** until it is covered or named as own-rows (write-scope gate). Hiding a control in
the UI is a courtesy to the user, never the enforcement.

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
with the old salon. `acknowledged_balance_paise` is a required parameter **and must equal the
balance the customer holds at that moment** (0036), so support cannot complete a transfer without
having looked up and disclosed the real figure — typing `0` is refused.

4.6a Support looks the number up with `app_admin.lookup_binding`: **super-admin only, one complete
number, a typed reason, an `audit_log` row on every call — found or not — keeping the last four
digits only.** No partial match, no list, no tenant path. That is what keeps it on the right side of
§2's ban on a global phone lookup: it cannot enumerate, and every use leaves a named trail.

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
marked it paid. There is no payment integration for it. A salon cannot be activated until the fee
is `paid`, or `waived` with a reason (0087).

6.4a **A lapsed subscription is read-only, computed from dates** (0087). `salon_writable()` requires
`billing_open()`; do not replace it with a job that flips `salons.status`, and do not add a write
path that skips `salon_writable()`. Reads, consent withdrawal, a captured Razorpay payment and
login for the salon's existing people stay open. Subscription payments are offline, append-only
and need a reference, like the setup fee.

6.5 **Every admin mutation goes through an `app_admin.*` function that writes `audit_log` in the
same transaction.** A route handler cannot forget the audit because the write and the log are one
statement.

6.6 The service role key is used for exactly one thing: calling `app_admin.*`. It lives in Edge
Function secrets and Vercel **server** env. Never in a browser bundle, never in the APK.

6.7 Admin accounts require MFA and never carry a `salon_id` claim.

6.8 Support mode is time-boxed, reason-required, and reads through PII-masking views. Un-masking is
a separate, separately-logged action. *(Built in 0089: at most two hours, the phone masked to its
last four digits, no customer data at all without a live session.)*

6.9 The console can change a salon's **status**. It can never delete its data - with **one**
exception, the offboarding purge (0089), which deletes *personal and operational* data only:
purge due, the owner offered an export, customer credit settled, a super-admin, a reason and the
name typed back. It never deletes a financial row. A purged salon's status is final. A manual
grace or suspension is lifted only by `reactivate_salon` (0092): super-admin, reason, audited.

6.10 The owner logs into the **same Android app** with the mobile number registered in the console.
No owner self-signup.

---

## 7. Messaging

### 7.1 Who sends

7.1.1 Every message — OTP included — sends from **the salon's own** Message Central and WhatsApp
Business accounts, from day one.

7.1.2 **No DLT registration anywhere.** Message Central is top-up-and-send, and its OTPs go out
under Message Central's own DLT-registered name.

7.1.2a **Message Central owns the OTP end to end** — it generates, sends and verifies the code.
Supabase issues a session only after Message Central returns `VERIFICATION_COMPLETED`. Never
call `signInWithOtp`, never enable Supabase's phone provider, never build a Send SMS Hook:
VerifyNow cannot deliver a code it did not generate (ADR-36).

7.1.3 Crayora's account is a **fault-only fallback** (credentials missing, untested, send failed).
Never a normal state, so every occurrence is logged, counted **and alerted** — **with one
exception: an operator-granted messaging trial.**

7.1.3a **Messaging trial** (0032, ADR-37). An operator may grant a salon a trial of up to 365 days,
with a required reason, audited. Until it ends, that salon's customer OTPs are sent from Crayora's
account **on purpose**, recorded as sender `trial`, and **not alerted** — so a salon can go live
before setting up its own Message Central account. Three rules hold during a trial:
- once Crayora has entered the salon's **own** account in the console, that account is used,
  trial or not;
- trial sends are counted separately and never inflate the fault-fallback count;
- the trial is an **OTP-cost** concession only — it is not a billing trial, and it changes nothing
  about the setup fee or the subscription.

7.1.3b **Grace, then block** (0033, ADR-38). After the trial the operator may grant a **grace period**
of up to 365 days, with a reason, audited; granted during a trial it starts when the trial ends.
Crayora still sends the salon's OTPs during grace, recorded as sender `grace`, not alerted. When the
trial and any grace have ended and the salon **still has no Message Central account of its own**, the
salon is **blocked**: no new customer can join, no OTP is sent, and no write succeeds
(`app.salon_writable()` is false). A block:
- **never** gates reads — a customer already logged in can still see their wallet, which the salon
  owes them (PRD §16A);
- **never** stops a customer withdrawing consent (DPDP) — `consents_customer_insert` stays outside
  `salon_writable`;
- **never** changes the salon's status to `suspended`, which would start the road to purging its
  data;
- lifts **the moment Crayora enters the salon's own account in the console**. It is a condition
  computed from dates,
  not an event fired by a job.

A salon that was never given a trial or grace is not blocked by this: it falls back to Crayora's
account as an alerted fault (7.1.3), as before.

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

7.3.1 **The order depends on the category, because WhatsApp's pricing does.** Push always first
(Rs 0). Then:

| Category | Escalation | Why |
|---|---|---|
| **Utility** (confirmations, receipts) | WhatsApp Utility (Rs 0.17) → SMS (Rs 0.22) | WhatsApp Utility is **cheaper than SMS**, and richer, and branded |
| **Marketing** (reminders, lifecycle) | **SMS (Rs 0.22)** → WhatsApp Marketing (Rs 1.28) **only on owner opt-in** | WhatsApp Marketing is **6x SMS**, and marketing is the high-volume category |
| **OTP** | WhatsApp Auth (Rs 0.17) → SMS (Rs 0.30) | The one cost every user incurs; provider handles the fallback |

7.3.1a Marketing escalation **defaults to SMS**. WhatsApp Marketing is an owner setting, and the
dashboard shows **cost beside reminder conversion** so the owner switches on evidence, not a hunch.
Never show one of those numbers without the other.

7.3.1b RCS is designed into the ladder but **unpriced — do not build it until it has a number**
(§22 Q-G). Its reach is conditional too: check `rcs_capable(phone)` (cached) before spending a send.

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

8.8 **The launcher icon cannot be changed at runtime**, on either platform. Android: offer the
pinned home-screen shortcut with the salon's logo and name. **iOS: there is no equivalent** - you
cannot add a home-screen icon programmatically, and alternate app icons must be bundled at build
time, which a white-label app with unknown salons cannot do. On iOS the branding is in-app only
until a per-salon build.

8.11 **Android ships first; the code stays iOS-compatible.** The launch is Android-only for cost
reasons, not architectural ones. Never write platform-specific code outside a platform abstraction,
never assume Android in shared code, and never let `app/ios` fall out of sync. CI builds iOS on a
macOS runner precisely because nobody here has a Mac - if that job goes red, fix it then, not
months later.

8.9 Notification small icon stays a generic monochrome mark (Android renders it as a silhouette).
Large icon, title and channel name are the salon's.

8.10 Publishing branding runs a **contrast check** and blocks an unreadable palette.

8.12 **Provider credentials are Crayora's to set, never the salon's.** A salon's Message Central
Customer ID and token, Razorpay keys, WhatsApp and RCS details are entered, rotated and removed
**only** in the Crayora super-admin console, through `app_admin.set_integration_secret`. No owner,
manager or staff role can read or write `salon_integrations`, and no function a tenant can call
touches it or Vault — the admin-plane gate asserts both from the catalogue, so a future
`update_my_razorpay_key` fails CI the day it is written. The owner app has no Integrations or
Credentials screen and never will.

---

## 9. Offline

9.1 Offline covers **capture**: mark-complete, walk-in booking, add/edit customer.

9.2 Offline **never** covers money or binding. Both are server-authoritative decisions.

9.3 Every server RPC takes a `client_action_id`. `idempotency_keys(salon_id, key)` is unique; a
replay returns the original result.

9.4 Mark-complete is an idempotent state transition (`confirmed | in_progress → completed`).
Replays are no-ops. Completing a booking that was never started records it as a start without the
code (0084).

9.4a **Starting** a service with the customer's code is **online only** — the code is checked by
the server, and staff can never read it. Starting **without** the code is a capture action like
mark-complete: queued, offline-safe, and never silent — the server records why, and the owner
sees every one. Do not add a path that starts a service and records no reason.

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
Withdrawal must be as easy as consent. "Latest wins" is ordered by `occurred_at` **and `id`**: two
changes in one transaction share a timestamp, and the wrong tiebreak resolves to *still consented*
(0052).

11.6a **Consent without notice is not consent.** Before or with the request, the customer is told -
in their own language, one of `en` / `hi` / `hi_Latn` - **what** is collected, **why**, **who** the
Data Fiduciary is (the salon, not Crayora), **how to withdraw**, **how to complain**, and to whom.
A tick-box with no notice is a defect, not a shortcut (DPDP ss.5, 6).

11.6b **Only the person themselves may consent.** No owner, manager or stylist path ticks a box for
a customer, and the database refuses one that tries. Consent someone else gave is not consent.

11.6c **`service_communication` is the service**, not marketing: booking confirmations, receipts and
the reminder they asked for. It is not offered as a toggle; the way out is erasure. Everything else
is opt-in and starts **off**.

11.7 **The salon is the Data Fiduciary; Crayora is the Data Processor.** The app shows a
**per-salon** grievance contact, not just a Crayora one.

11.7a **A salon cannot be activated without a named privacy contact** - a person, plus an email or
a phone number (`app_admin.activate_salon` refuses; 0053). It is published **before login**, by
`resolve_join_code`, with the salon's name and branding, because the notice has to be readable at
the moment consent is asked for. Crayora is the escalation when a salon does not answer in 30 days,
never the first line.

11.7b **The published privacy policy is a statement about the system**, not marketing copy
(`join/public/privacy.html`, served at `join.craysalon.in/privacy`). Every claim in it must be
checkable against a migration, a gate or an Edge Function. **If the software changes, the policy
changes in the same commit** - a policy that describes a system we no longer run is worse evidence
than no policy at all.

11.8 Erasure is **anonymisation**: clear name and birthday, replace phone with its salted hash,
detach `auth_user_id`, hard-delete photos from R2, **retain** financial rows against the anonymous
id.

11.9 Purging a salon deletes **operational and personal** data only. `invoices`, `payments`,
`wallet_transactions` and `loyalty_ledger` move to a restricted, anonymised archive for the
statutory period. Offer an export first, and require outstanding credit to be settled.

11.9a **The statutory period is 8 years** from the end of the financial year, for `invoices`,
`payments`, `wallet_transactions` and `loyalty_ledger` (decision of 28 Sep 2026; **to be confirmed
by a CA**, and that confirmation is owed before the first real salon). The published privacy policy
states this number to customers, so the retention job, this rule and that page move together or not
at all.

11.10 **A breach has two clocks, and both start when we become AWARE.**
**6 hours** to CERT-In for a listed cyber incident, and **72 hours** to the Data Protection Board
with facts, cause, mitigation and findings - with affected customers told without delay, in plain
language, by the **salon** as Data Fiduciary. Never wait for certainty before notifying: the Rules
expect an initial report and an update, not one perfect one. The steps, the contacts and the
wording are in **`RUNBOOK-BREACH.md`**, which names one human as owner and is rehearsed - an
unrehearsed runbook has unknown steps in it.

11.11 **Every data-principal right is answerable with a date.** Access, erasure and grievance are
rows with a due date and an outcome (`data_rights_requests`, 0051). A refusal is allowed; silence
is not, and "we kept your invoices because the law requires it" is an answer.

11.12 A wallet top-up produces a **receipt, never a tax invoice**. GST arises on the service
invoice at redemption. Invoice numbers are sequential per salon per financial year.

11.13 **Licensing boundaries — if a change would cross one, stop and escalate.** It is a licensing
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
- [ ] **Index scope test** — every composite index on a tenant table leads with `salon_id`, or is
      named and justified as an exemption (§3.1)
- [ ] **Messaging access test** — trial, then grace, then block, walked in order on one salon; a
      block stops joins, OTPs and writes, never reads or consent withdrawal, never changes status,
      and lifts the moment Crayora enters the salon's own account in the console
- [ ] **Join flow test** — only an active salon's code resolves, to its name and branding and
      nothing else; a salon in setup and an unknown code look identical (no oracle); typing
      variants normalise, but a character outside the alphabet is never guessed at; a live join
      intent decides which salon's account sends the OTP
- [ ] **Money test, in motion** — exactly ONE function inserts a ledger row and only the permitted
      callers call it, asserted from the catalogue; no device can call any of them; a top-up credits
      paid and bonus as separate lots with the paid one carrying no expiry; spending empties BONUS
      first; overdrawing is refused rather than clamped or partially applied; two debits in a row
      cannot together overdraw; a PAID lot cannot be expired even by the expiry function; a
      correction is audited and issues paid-kind credit. Negative control: **a second function that
      writes a ledger row makes it go red**
- [ ] **Data rights test** — a customer can see what they agreed to and withdraw it themselves;
      withdrawal is a NEW ledger row and the original consent survives unedited; the SALON cannot
      tick a consent box for a customer; access, erasure and grievance can be asked for and land on
      the salon with a due date; erasure removes name, number, birthday and the login link while the
      salted hash and every financial row remain (DPDP ss.6, 11, 12(3), 13)
- [ ] **Booking test** — two bookings for the same chair at the same time cannot both succeed, nor
      can an overlapping one, while the minute the first ends is free; a replayed booking returns
      the original and creates no second row; price and duration are snapshotted, so repricing a
      service never rewrites what a past booking cost; an add-on not offered with the service is
      refused; mark-complete is idempotent under a replay AND under a fresh action id; a customer
      books and cancels only their own, and never completes a visit. Negative control: **dropping
      the exclusion constraint makes it go red**
- [ ] **Write scope test** — every tenant-writable table names WHO may write it or is a documented
      own-rows table; an owner cannot change their salon's status, join code or branding; a staff
      member cannot promote themselves in `public.users`; a customer cannot touch the catalogue or
      write their own visit history; and a customer can still edit their own profile and read the menu
- [ ] **Customer list test** — the owner's list function is **SECURITY INVOKER** (a definer version
      would outrank RLS and undo 3.8a), pages by keyset rather than OFFSET with no row repeated or
      skipped, searches by name prefix or WHOLE number but never a partial number, cannot be asked
      for an unbounded page, is unreachable before login, and returns a customer nothing but
      themselves
- [ ] **Customer scope test** — inside ONE salon, a signed-in customer reads only their own
      customer row, wallet, ledger, consents and bookings; the other customer's rows are
      unreachable by any query they can express; the staff table - which holds staff phone
      numbers - returns nothing; the salon's menu still does; and an owner still sees everything.
      Plus the catalogue half: every table naming a customer HAS the restrictive policy
- [ ] **Bind flow test** — first login binds to the salon on the server's challenge, in the same
      step, with the verified number and DPDP-correct consent defaults; a number bound elsewhere is
      refused naming no salon; staff are attached, never made customers; the claims hook stamps
      role and salon and never gives a platform admin a salon; unbind is refused once history
      exists; a transfer needs the acknowledged balance - the REAL one - leaves the wallet
      behind, and ends the customer's sessions; an ordinary operator can neither look a number
      up nor unbind nor transfer; every lookup is audited, found or not, without the full number
- [ ] **OTP test** — no salon context means no send; a code is checked only against the challenge
      the server issued; five attempts; one verification yields at most one session; the session
      identity carries no plaintext phone; only accounts the server created are ever adopted
- [ ] **Pepper test** — `app.phone_hash` works with **no session GUC set**, proving the pepper is
      configured in Vault rather than supplied by the test. Every other test sets the GUC, so all
      of them passed against a database that could not have provisioned a single salon
- [ ] **Admin plane test** — no `app_admin` function is reachable by a tenant role; every mutating
      one writes `audit_log` in the same transaction (§6.5); provisioning is atomic (§6.2);
      `activate_salon` is the only door to `active` (§6.3); nothing reads a credential back
- [ ] **Negative controls** — an unprotected tenant table makes the leak test go red; an
      `app_admin` function that mutates without auditing, and an owner-callable function that
      changes a payment key (8.12), each make the admin-plane gate go red
      (`node scripts/db/negative-control.mjs`). A gate only ever seen passing is not a gate
- [ ] Migrations apply from zero onto an empty database in CI (`node scripts/db/run.mjs migrate`
      against a fresh container — never `db reset`, which would wipe the shared dev project)
- [ ] CI steps run under `pipefail` (GATE-6). Without it, `cmd | tee log` takes `tee`'s exit code
      and every piped gate reports success regardless of result
- [ ] Secret scan clean, including the APK and the Vercel client bundle
- [ ] Lints: domain purity, no `.from(` outside `data/remote/`, no raw `Color(0x…)`
- [ ] **The App Link fingerprint file is real or absent (GATE-8).**
      `join/public/.well-known/assetlinks.json` is generated at deploy from the certificate the
      release APK is actually signed with, and is never committed. A placeholder fails Android's
      verification **silently**: every customer's QR quietly opens the website instead of the app,
      with nothing in any log to say why

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
