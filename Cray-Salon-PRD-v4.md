# Cray Salon — Complete PRD & Build Brief (v4)

**A multi-tenant, per-salon white-labelled SaaS retention platform for local salons — sold and provisioned by Crayora, built to be implemented by Claude Code**

| | |
|---|---|
| **Product** | Cray Salon |
| **Company** | Crayora |
| **Document type** | PRD + implementation brief for Claude Code |
| **Version** | 4.7 (business model corrected; v3 gaps closed; join flow salon-code-first; decisions closed and legally reviewed — §16A; no DLT anywhere; message-control tiers — §12.1a; **RCS added to the channel ladder — §12.1b**) |
| **Status** | Ready to build |
| **Platform** | Flutter — **Android at launch, iOS-ready from day one** (install-first) + Next.js admin console on Vercel |
| **Prepared** | September 2026 |
| **Companions** | `ARCHITECTURE.md` — the *how* · `DESIGN.md` — visual rules · `PHASES.md` — build order · `IMPLEMENTATION.md` — screens & API · **`RULES.md` — binding, read every session** |

---

## What changed from v3 — read this first

v3 assumed a **self-serve, product-led** business: the owner downloads the app and provisions his
own salon with zero Crayora involvement. **That is no longer the model.** v4 replaces it with a
**sales-led, Crayora-operated** model, and adds per-salon white-labelling.

| Area | v3 | v4 |
|---|---|---|
| **Acquisition** | Owner finds app, self-onboards | Owner sees an ad → contacts Crayora → **one-time setup fee (₹10,000–₹20,000)** → Crayora provisions |
| **Provisioning** | In-app wizard, no human | **Crayora super-admin console** (Next.js on Vercel), operated by a Crayora person |
| **Super-admin console** | Internal support tool, Milestone 11 | **The primary provisioning surface — Milestone 3, a prerequisite for any salon existing** |
| **Customer joins** | Salon join link | Scans the salon's **unique QR / enters the salon code**, binding is **permanent** |
| **Customer ↔ salon** | May belong to many salons | **Exactly one salon, for life.** One phone number binds to one salon and can never be re-bound |
| **Branding** | One Cray Salon app for everyone | **App fully white-labels to the salon** after binding — logo, colours, fonts, app name, message sender |
| **Per-salon config** | Platform-wide keys | Console holds **per-salon** API keys, secrets, branding assets, catalogue, rules |
| **Billing** | Subscription only | **Setup fee + subscription** |
| **Gaps** | 11 under-specified areas | All closed — see *"Gaps closed in v4"* below |

**Gaps closed in v4** (each was found by reading v3 against the blueprint; the mechanism for each
lives in `ARCHITECTURE.md`): payments table for the package→wallet→UPI waterfall (§8.2, §14),
slot double-booking (§9.3), wallet bonus/paid split with expiry (§9.1), FCM delivery cannot be
trusted (§12), offline capture vs. server-only ledger (§15), historical price drift (§8.2),
dashboard totals reconciliation (§9.5), erasure vs. immutable ledger (§16), read-only grace
enforcement (§14), tenancy claim model (§7), and per-salon secret storage (§16).

---

## Decisions locked in v4.1

Every open question from v4.0 has been answered. These are now requirements, not proposals.

| Decision | Ruling | Consequence |
|---|---|---|
| **Join flow order (v4.2)** | **Salon code first, then login.** The customer identifies the salon *before* entering their phone number | §6.4 — makes salon-sent OTP possible, brands the login screen, and closes the generic OTP-flood surface |
| **OTP delivery** | Message Central works via Supabase's **Send SMS Hook** — confirmed. An Edge Function receives `{ sms, user }` and forwards `sms.metadata.token` to Message Central | §12.1 |
| **OTP sender (v4.2)** | **The salon's own Message Central account, including the very first OTP.** Crayora's platform account is a logged, alerted fallback only | §12.1 — resolution order: pending join → existing binding → owner/staff record → **refuse** |
| **Salon transfer** | The emergency unbind stays, **and** a customer may request a salon change **through Crayora customer support**. Still no self-service path in the app | §6.5 rewritten: "one *active* binding", support-mediated transfer, wallet does **not** move |
| **Razorpay** | Each salon uses **its own Razorpay account**. The console stores that salon's key id, key secret and webhook secret | §11, §14 |
| **Wallet top-ups** | **Non-refundable on request** — no refund to bank, no cash-out. But the salon **must settle outstanding credit** if it closes, is suspended, or the customer transfers away | §8.5, §16A.2 |
| **Wallet expiry** | **Bonus** credit only, set by the salon owner in the app. **Paid credit never expires** and no setting can make it | §9.1, §16A.2 |
| **Spend order** | **Bonus credit first**, then paid credit | §8.5 |
| **Manual wallet adjustment** | **Removed entirely.** Neither owner nor manager can change a balance by hand | §9.5 — the one-tap "adjust wallet" action is deleted |
| **Owner login** | The owner logs into **the same Android app** with the mobile number registered in the console. No self-signup | §4, §6.2 |
| **Setup fee** | Collected **manually, offline**. The console records it and the operator switches the salon on | §11, §14 |
| **Messaging identity** | Every message sends from the salon's own Message Central and WhatsApp Business accounts, from day one. **No DLT registration is needed anywhere** — Message Central is top-up-and-send | §12.1a — but the **OTP template is Message Central's and cannot be branded**; push and WhatsApp can |
| **Fonts** | Curated Google Fonts allow-list | §6.2 |
| **Data retention** | Operational and personal data purged 90 days after suspension, notices at day 60 and 80. **Financial records archived and anonymised for the statutory period, not deleted** | §14, §16A.6 |
| **Regulatory posture** | Crayora is **not** a payment aggregator and **not** a PPI issuer; the salon is the **Data Fiduciary** and Crayora the **Data Processor** | §16A |
| **Tier 3 white-label APK** | Deferred. Built manually and separately if and when a salon needs one | §10.11 |

> **Three consequences worth reading before §14.** First: because each salon pays for its own
> WhatsApp, SMS **and OTP**, messaging cost leaves Crayora's books almost entirely — only the
> fallback remains. The per-plan "WhatsApp messages included" allowance no longer represents
> anything Crayora pays for (§14, §21 Q-A). Second: push (FCM) stays free and platform-level, so
> *push-first now saves the salon owner money*, which is a stronger sales argument than it was
> when Crayora absorbed the cost. Third: **the salon's Message Central account is now on the
> critical path for customers joining at all**, so the console must test it before activation
> and the platform fallback must exist (§12.1, §21 Q-E).

---

## 0. How to build this with Claude Code

This document is handed directly to **Claude Code**. You (Jyotiranjan) direct; Claude Code
writes the code; you review and steer.

**How to drive the build:**

1. Create the repo, add **`CLAUDE.md`** at the root (Appendix A) and **`ARCHITECTURE.md`**
   alongside it. Claude Code reads both every session — that is how you stop the agent drifting.
2. Build in the **milestone order (§17)**, one milestone per session. Never ask for the whole app.
3. Feed it the relevant section as the spec: *"Implement the wallet ledger per §9.1 and
   ARCHITECTURE §6.4; acceptance criteria are in that section."* Each feature has an
   **Acceptance criteria** block = definition of done.
4. Make it write the **cross-tenant leak test** (§7) — mandatory, and a release gate.
5. When this PRD and `ARCHITECTURE.md` disagree on *mechanism*, `ARCHITECTURE.md` wins. When
   they disagree on *scope or intent*, this document wins. Fix the loser in the same session.

**The instruction to repeat constantly:** *every table has a `salon_id`, every query is
tenant-scoped, RLS is enforced in the database — never write a query that can return another
salon's data.*

---

## 1. What we are building

Cray Salon turns a local salon's one-time walk-in customers into repeat customers. It is **not a
booking app** — it is a connected retention loop: record the customer → give a reason to return
(prepaid credit + loyalty) → remind at the right time → raise the bill transparently (add-ons,
packages) → earn referrals → show the owner what worked.

It ships as **multi-tenant SaaS with per-salon white-labelling**: one codebase, one database,
many salons, each fully isolated — and to the customer, it looks and feels like **their salon's
own app**. Crayora sells it, charges a setup fee, and provisions each salon from an internal
console. The salon owner never sees a database, and neither does a Crayora operator.

**Core transformation:** walk-in → saved customer → prepaid balance → timely reminder → repeat
booking → add-on/package sale → referral → measurable revenue.

---

## 2. Problem

Local salons have hidden revenue leaks: no customer record after a visit; no timely reminder;
add-ons never shown at booking; no cheap acquisition channel; no simple view of what's working.
Cray Salon closes all of these and layers on loyalty, packages, and lifecycle marketing — under
the salon's own brand, so the customer's loyalty attaches to the salon, not to Crayora.

---

## 3. Goals & success metrics

### Goals

1. Increase repeat-visit rate.
2. Increase average bill value (add-ons, packages, memberships).
3. Generate trackable referrals.
4. Give owners simple daily-decision numbers.
5. **Make every salon feel like it owns the app** — white-label branding end to end.
6. **Make Crayora's setup operation fast and repeatable** — a non-engineer provisions a salon in
   under 30 minutes without touching a database.
7. Keep per-salon messaging cost low by preferring free push over paid WhatsApp.

### Success metrics (per salon)

| Metric | Formula |
|---|---|
| Repeat customer rate | returning ÷ total (by cohort) |
| Wallet repeat lift | repeat rate of wallet users vs non-wallet |
| Reminder conversion | bookings from reminders ÷ reminders delivered |
| Average bill value | completed revenue ÷ completed bills |
| Add-on acceptance | bookings with add-on ÷ bookings |
| Referral conversion | referred first-paid-visits ÷ valid sign-ups |
| Membership/package uptake | active packages ÷ active customers |
| No-show rate | no-shows ÷ confirmed bookings |
| **Customer bind rate** | customers bound to the salon ÷ walk-ins seen (measures QR handover discipline) |
| NPS / CSAT | post-visit feedback score |

### Crayora business metrics

Setup fee revenue; **time-to-provision** (console open → QR handed over); **time-to-first-bind**
(salon activated → first customer bound); paying-salon retention (30/90d); MRR; churn; messaging
cost per salon; **push-vs-WhatsApp send ratio** (higher push = better margin).

> Note: v3's *self-serve activation rate* is retired. Activation is now an operational metric of
> Crayora's own setup team, not a product funnel.

---

## 4. Users & roles

| Role | MVP? | Capabilities |
|---|---|---|
| **Customer** | ✅ | OTP login; **binds to exactly one salon, permanently**; wallet, bookings, offers, referral, packages, loyalty; one-tap booking; feedback. Sees the app fully branded as that salon |
| **Owner** | ✅ | Logs into **the same Android app** with the mobile number Crayora registered in the console. Full salon management, dashboard, catalogue, wallet **rules and expiry**. **Cannot change any customer's balance by hand (§9.5).** **Does not provision** — Crayora does. No self-signup |
| **Manager** | ✅ (role) | Owner capabilities minus billing/settings, per granular permissions. Also cannot change a balance by hand |
| **Staff/Barber** | Phase 2 | Own schedule; mark complete; add-on/bill updates; tips; commission view |
| **Crayora operator** | ✅ (internal) | **Provisions salons** in the console: branding, catalogue, rules, keys; generates the QR + salon code; invites the owner |
| **Crayora super-admin** | ✅ (internal) | Everything an operator can do, plus billing, suspend/reactivate, feature flags, platform metrics, credential management |

Granular permissions are stored per user so owners can decide what managers/staff may do.

> **Critical dependency (unchanged):** every automation triggers off "visit marked complete."
> MVP owner logs completions → mark-complete MUST be one tap on the day view, and must work
> offline (§15).
>
> **Critical dependency (new):** the loop only starts when a customer **binds**. The QR handover
> in the chair is the single most important human step in the product. The app, the printed
> collateral, and the owner training all exist to make that handover reliable — and *bind rate*
> is tracked as a first-class metric.

---

## 5. Feature roadmap (everything, tiered)

### Tier 1 — MVP (the loop)

Crayora-operated provisioning console · **per-salon white-label branding (logo, colours, fonts,
app display name, message sender)** · **salon code + QR generation** · **customer binding
(scan/enter code, permanent, exclusive)** · OTP login · customer profiles + visit history ·
service catalogue · booking + slots · add-ons (never pre-selected) · salon-credit wallet ledger ·
service-based reminders · referral link/code + reward states · **owner login in the same app** ·
owner dashboard + cohort retention · **immutable wallet & loyalty ledgers with no manual
adjustment path** · **push notifications (FCM) with delivery ack** · **per-salon messaging
identity (own WhatsApp Business + Message Central account)** · setup-fee recording +
subscription billing · multi-language (EN/HI/Hinglish) · offline mark-complete.

### Tier 2 — Phase 2 (deepen retention & revenue)

Customer **memberships & prepaid packages** · **loyalty points/tiers** · **waitlist & walk-in
queue/token** · **lifecycle automation** (birthday, anniversary, win-back, lapsed) ·
**feedback/NPS + review routing** · **staff/barber app** + schedules + **commission** · **GST
invoicing / digital receipts** · **photo gallery** (before/after, with consent) · advanced
analytics · manager/staff granular permissions · **home-service booking**.

### Tier 3 — Phase 3 (scale & network)

Multi-**branch** (one owner, many locations) · **per-salon signed white-label APK with its own
launcher icon and Play listing (premium tier — see §6.6)** · **gift cards** (closed-loop, legal
review required) · inventory & retail product sales · dynamic/off-peak pricing · marketing
campaign builder · **referral leaderboard** · AI hairstyle recommendations · WhatsApp two-way
chatbot booking.

---

## 6. ⭐ Crayora-operated onboarding, salon codes & white-labelling (replaces v3 §6)

This section replaces v3's "zero-touch self-serve onboarding" in full. The **spirit** of the old
requirement survives and is still a hard rule:

> **If activating a salon ever requires touching a database, running a SQL script, or a code
> deploy, this requirement has FAILED.** Everything is done through the console UI.

What changed is *who* does it: a Crayora operator, not the owner.

### 6.1 The commercial flow

1. Salon owner sees a Crayora ad and makes contact.
2. Crayora sells: **one-time setup fee ₹10,000–₹20,000** + a monthly subscription (§14).
3. Crayora collects the owner's details, branding assets, service list and prices — the
   **owner discovery checklist (§19)** is the intake form.
4. A Crayora operator provisions the salon in the console (§6.2).
5. Crayora hands over: the **salon code**, a **printable QR pack**, owner login, and training.

### 6.2 Provisioning in the super-admin console (Next.js on Vercel)

The operator fills one guided, multi-step form. Everything is editable afterwards.

| Step | What the operator enters |
|---|---|
| **Identity** | Legal name, **display name** (used in every message and in the app), address, phone, email, GST number (optional), timezone, languages |
| **Branding** | Logo (square, ≥1024px), wordmark, splash image, **primary / secondary / accent colours** (light and dark), **heading + body font from a curated Google Fonts allow-list**, corner radius, notification large-icon |
| **Catalogue** | Services (name, price, duration, repeat cycle), add-ons (price, extra duration, relevance), staff (name, hours, skills) |
| **Rules** | Wallet rule (e.g. ₹500 → +₹50), bonus expiry, reward rule, loyalty rule, default reminder cycle, cancellation policy |
| **Integrations** | **The salon's own Razorpay** key id, key secret and webhook secret · **the salon's own Message Central** account credentials (top-up-and-send; no DLT) · **the salon's own WhatsApp Business** sender, with templates authored in the Message Central dashboard and submitted for Meta approval · **the salon's own RCS agent, verified with Google and the carriers** · Google review link |
| **Commercials** | Plan, **setup fee amount + the note/reference for the offline payment** (cash or bank transfer, collected outside the system), billing start date |
| **Owner account** | Owner name + phone → creates the owner user and sends an SMS invite |

On **Activate**, the console (never the operator, never SQL):

- creates the tenant with a fresh `salon_id`, fully RLS-isolated from that instant;
- generates a **unique salon code** and its **QR**;
- renders a **printable QR pack** (counter card A5, mirror sticker, reception poster) as a
  downloadable PDF;
- creates the owner user — the owner then logs into **the same Android app** with that mobile
  number, by OTP, and lands in the owner shell;
- starts the subscription and records the setup fee as **manually collected**.

**Setup fee and switch-on.** The fee is collected offline — cash or bank transfer — outside the
system. The operator records the amount, date and reference in the console and marks it paid.
**Switching the salon on is a deliberate manual action by the operator**, not an automatic
consequence of anything. The console warns if the fee is unrecorded but does not block the
operator, who may have a reason.

**Messaging readiness.** A salon is not live on WhatsApp until its own templates have been
authored in the Message Central dashboard and approved by Meta (§16A.5). The console tracks that
as a per-salon status, and until it is green the channel ladder simply skips the WhatsApp rung.
**It blocks nothing that matters:** login works from day one, push carries every notification, and
the salon can bind customers immediately.

**Credential handling:** API keys and secrets entered here are **encrypted at rest** and are
never readable again in the UI — the console shows only the last four characters and a
*"Test connection"* button. Rotation replaces; it never reveals. See §16.

### 6.3 The salon code and QR

- **Salon code** — short, human-typable, case-insensitive, from an unambiguous alphabet (no
  `0/O`, `1/I/L`). Example shape: `CRAY-7K4M2`. Globally unique. Printed large on collateral so
  a customer with a cracked camera can still type it.
- **QR** — encodes a deep link (`https://join.craysalon.in/s/<code>`) that opens the app if
  installed, otherwise the Play Store listing, carrying the code through install so the customer
  lands on the join screen with the code pre-filled.
- Codes are **not guessable** and are rate-limited on lookup (§16). A code resolves publicly to
  the salon's **display name and branding** — logo, colours, fonts — because the app must theme
  itself before login (§6.4). It resolves to **nothing else**: no customer data, no counts, no
  contact details, and nothing for a salon that is not active. Enumerating codes would therefore
  yield a directory of salon logos and nothing of value, and the rate limit makes even that
  impractical (§21 Q-F).

### 6.4 The customer join flow

> **Order changed in v4.2 — salon code first, then login.** The customer identifies the salon
> *before* authenticating. This is what makes it possible to send even the very first OTP from
> the salon's own Message Central account (§12.1), and it means the app is already wearing the
> salon's branding on the login screen.

1. Customer visits the salon. The owner or barber asks them to scan the QR at the counter.
2. Play Store → install → open.
3. **Salon first.** The app prompts: **scan the salon QR** or **enter the salon code**. (If they
   arrived via the deep link, the code is already filled in and this step is a confirmation.)
4. The app resolves the code and **immediately re-themes to that salon** (§6.6) — logo, colours,
   fonts, name. From this point on the customer is looking at their salon's app, not Crayora's.
5. Confirmation: *"You're joining **&lt;Salon display name&gt;**."*
6. **Then login.** The customer enters their mobile number and receives an OTP **sent from that
   salon's own Message Central account**, so the sender the customer sees is their salon.
7. On successful verification, the account is created **and bound to that salon in the same
   step** (§6.5). There is no window in which a logged-in customer has no salon.
8. The app offers to add a home-screen icon carrying the salon's logo and name.

**Why this order is better than the v4.1 order (login → code):**

| | Login first (v4.1) | **Salon first (v4.2)** |
|---|---|---|
| Who sends the first OTP | Crayora — the salon isn't known yet | **The salon** |
| Branding on the login screen | Generic Crayora | **The salon's** |
| Who can request an OTP | Anyone with the app | **Only someone holding a valid salon code, or an already-known number** |
| "Logged in but not bound" state | Normal, must be handled everywhere | Transient edge case only |

The third row is the one that matters most for security: because an OTP can now only be
requested by someone who presented a real salon code or is already known to the system, the
generic OTP-flood attack surface is closed off at the door rather than rate-limited after the
fact.

**Acceptance criteria**

- [ ] A customer can identify the salon by scanning the QR **or** by typing the code — both work.
- [ ] The app is fully branded as the salon **before** the phone-number screen.
- [ ] The first OTP is sent from **the salon's** Message Central account, not Crayora's.
- [ ] An OTP request carrying no valid salon code and no already-known number is **refused**.
- [ ] Login and binding complete together; the app never lands a customer in a logged-in,
      unbound state in the normal path.
- [ ] An invalid, unactivated or suspended-salon code is rejected with a clear message.
- [ ] Code lookup is rate-limited, and per-salon OTP volume is capped so a leaked code cannot
      run up that salon's SMS bill.
- [ ] If the salon's Message Central account is unreachable, the customer is not locked out
      (§12.1 fallback) and the failure is raised in the console.

### 6.5 Exclusive binding, and the support-only transfer path (hard rule)

> **A phone number is bound to exactly one salon at a time. The customer can never change salons
> from inside the app. A change happens only when Crayora customer support performs it.**

**In the app — nothing.**

- Enforced by a **global uniqueness constraint** on the phone identity across all tenants — not
  by UI, and not by application logic alone.
- There is **no "switch salon" screen, no "join another salon" action, and no such API**. A
  customer who tries to bind an already-bound number is refused with *"This number is already
  registered with a salon"* — and the message **never names which salon** (that would be a
  cross-tenant leak dressed as an error).

**Through Crayora support — two distinct actions, both audited.**

| Action | When it is used | Effect |
|---|---|---|
| **Unbind (correction)** | The customer scanned the wrong QR and has done nothing since | The binding is removed; the customer can bind again normally |
| **Transfer** | The customer genuinely wants to move to a different salon | The binding moves to the new salon; the old salon's records stay with the old salon |

Both require a Crayora super-admin, a typed reason, and are fully recorded in the audit log.
Neither is reachable by a salon owner, a manager, or the customer.

**What a transfer does *not* carry across.** This is the part to be careful about, because
customers will assume otherwise:

- **Wallet balance stays with the old salon.** It cannot move. The customer's ₹550 was paid to
  Salon A's own Razorpay account and landed in Salon A's bank — Crayora never held it and cannot
  move it to Salon B. Since top-ups are non-refundable (§8.5), any remaining balance is
  **forfeited unless the old salon chooses to settle it with the customer in person**.
- **Visit history, loyalty points, tier, packages and referrals stay with the old salon.** They
  are that salon's business records.
- The customer starts at the new salon **with a clean slate** — new record, zero balance, zero
  points.

Support **must** state the remaining balance and get the customer's explicit acknowledgement
before performing a transfer, and that acknowledgement is recorded on the audit entry. A
customer who loses ₹800 of credit they did not know about is a complaint, a bad review, and
possibly a refund argument you cannot win.

**Acceptance criteria**

- [ ] A phone number bound to Salon A cannot bind to Salon B — verified by an automated test.
- [ ] No customer-facing route, button, or endpoint permits changing or adding a salon.
- [ ] The refusal message never names the other salon.
- [ ] Support transfer and unbind are super-admin only, reason-required, and audit-logged with
      actor, before/after, and the acknowledged remaining balance.
- [ ] After a transfer, the customer sees a zero balance and empty history at the new salon, and
      the old salon's records are unchanged.
- [ ] A transferred-out customer row remains readable by the **old** salon and is invisible to
      the new one.

### 6.6 White-labelling: what actually changes, and what cannot

After binding, the app becomes the salon's app. Being precise here matters, because one part of
this is **not technically possible on stock Android** and must not be attempted.

**Fully dynamic — delivered in Tier 1:**

| Surface | Behaviour |
|---|---|
| Splash + onboarding | Salon logo and colours |
| App theme | Salon primary / secondary / accent, light and dark, corner radius |
| Typography | Salon heading + body fonts, downloaded and cached |
| In-app title / header | Salon display name and wordmark |
| **Home-screen icon** | A **pinned shortcut** carrying the salon's logo and name is offered right after binding — this is the icon the customer actually taps |
| Push notifications | Salon name as the title/sender, salon logo as the **large icon**, per-salon notification channel |
| WhatsApp / SMS | Salon display name in every template body |
| Invoices, receipts, share cards | Salon logo, name, GST details |

**Not possible dynamically — do not attempt:**

> Android's **launcher icon is fixed in the APK at build time.** It cannot be replaced with a
> logo downloaded from a server. The only stock mechanism (`activity-alias` component swapping)
> requires every salon's icon to be compiled into the APK in advance, which cannot work for a
> growing set of salons and misbehaves on several OEM launchers.

The Tier 1 answer is the **pinned home-screen shortcut** above: the customer ends up with a
salon-branded icon on their home screen, which is the outcome the requirement is really after.

**True per-salon launcher icon — Tier 3, premium tier:** the console triggers a CI build that
produces a **signed, per-salon APK/AAB** with that salon's own icon, app name and package id,
published to its own Play listing. This is a real product tier with real cost (Play review
latency, per-salon release management) and is priced accordingly. See §21 Q4.

**Acceptance criteria**

- [ ] Theme, fonts, logo and display name all come from the server and are cached for offline use.
- [ ] A branding change made in the console reaches installed apps within one app open.
- [ ] The app renders correctly with a neutral default theme if branding cannot be fetched.
- [ ] The pinned-shortcut prompt appears once after binding and can be re-triggered from settings.
- [ ] Every push notification shows the salon's name and logo, never "Cray Salon".

---

## 7. Multi-tenancy (foundation — Day 1)

**Tenant** = one paying salon (Day 1). **Branch** = one owner, many locations (Tier 3). Keep
these separate — branch is a sub-dimension *inside* a tenant, never a replacement for it.

**Approach:** shared database, shared schema, row-level — every table carries `salon_id`.

**Two required defenses:** (1) **Postgres RLS** policies so the DB itself refuses out-of-tenant
rows even if app code has a bug; (2) a **tenant-scoped data-access layer** so no raw query
reaches the DB unscoped.

**Resolution (simplified in v4).** Because a customer now belongs to exactly one salon (§6.5),
**every** principal — owner, manager, staff and customer — carries a single `salon_id` claim in
their Supabase Auth JWT, and RLS filters on it uniformly. v3's contradiction (a `salon_id` claim
that could not represent a multi-salon customer) is gone.

```sql
alter table customers enable row level security;
alter table customers force  row level security;
create policy tenant_isolation_customers on customers
  using      (salon_id = (auth.jwt() ->> 'salon_id')::uuid)
  with check (salon_id = (auth.jwt() ->> 'salon_id')::uuid);
```

> Generate an equivalent policy for **every** tenant table. The cross-tenant leak test is
> generated from the database catalogue, so a table added tomorrow is covered tomorrow — see
> `ARCHITECTURE.md` §5.7. It is a **release gate**.

**Claims are a cache, not the truth.** Suspension, role and permission changes are re-checked
against the database on every write, so a stale token cannot outlive a revocation (§14).

---

## 8. Data model

### 8.1 SaaS / tenancy

- **`salons`** — id, legal_name, **display_name**, **join_code (globally unique)**, logo_url,
  address, phone, timezone, working_hours jsonb, wallet_rule jsonb, reward_rule jsonb,
  loyalty_rule jsonb, default_reminder_cycle, cancellation_policy, gst_number?, languages text[],
  notification_prefs jsonb, status (active/suspended/setup), created_at.
- **`salon_branding`** — salon_id, colours jsonb (light+dark), fonts jsonb, logo/wordmark/splash/
  notification-icon URLs, radius, version. *Bumping `version` is what pushes a re-theme to apps.*
- **`salon_integrations`** — salon_id, provider (`razorpay` | `message_central` | `whatsapp`),
  **encrypted credential references** (never plaintext, never readable by any tenant role),
  sender metadata, `whatsapp_template_status`, last_tested_at, status. *No DLT field and no
  per-salon SMS header — Message Central owns the OTP sender and template (§12.1a).*
- **`users`** — id (= Auth uid), salon_id, role (owner/manager/staff), permissions jsonb, name,
  phone, active.
- **`customer_identities`** — **global, cross-tenant**: phone_hash (unique), salon_id,
  customer_id, bound_at. *This one table is what makes binding exclusive (§6.5) — one row per
  phone means one active binding per phone.*
- **`binding_events`** — append-only history of every bind, unbind and transfer: phone_hash,
  from_salon_id?, to_salon_id?, actor, reason, acknowledged_balance_paise?, occurred_at.
- **`subscriptions`** — salon_id, plan, status (active/past_due/cancelled), **setup_fee_paise,
  setup_fee_status, setup_fee_reference** (offline payment note), **activated_by, activated_at**,
  renews_at.
- **`platform_admins`** — Crayora operator / super-admin accounts (separate from tenant users).
- **`feature_flags`** — per-salon rollout of Tier 2/3 capabilities.

### 8.2 Core product (each has `salon_id`)

| Table | Fields |
|---|---|
| `customers` | name, phone (the salon's own copy, for contacting them), phone_hash (peppered HMAC, the key to the global binding), auth_user_id, birthday?, anniversary?, created_at, last_visit, loyalty_points, tier, language. **Consent is not a column here** — see `consents` below |
| `services` | name, category, price, duration, repeat_cycle_days, active, image_url? |
| `add_ons` | name, price, extra_duration, relevant_service_ids, active, staff_availability |
| `staff` | name, working_hours jsonb, skills text[], commission_rule jsonb, active |
| `bookings` | customer_id, staff_id, starts_at, ends_at, status, total, source (walk-in/app/reminder/referral/waitlist) |
| **`booking_items`** | **NEW —** booking_id, kind (service/add-on), ref_id, **price_paise and duration snapshotted at booking time** |
| `visits` | booking_id, completed_services, final_amount, payment_status, tip, completed_at |
| **`payments`** | **NEW —** visit_id, method (package/wallet/upi/card/cash), amount_paise, status, razorpay_payment_id?, idempotency_key |
| **`payment_allocations`** | **NEW —** payment_id, wallet_lot_id?, customer_package_id?, amount_paise |
| **`wallet_lots`** | **NEW —** customer_id, kind (paid/bonus), amount_paise, remaining_paise, expires_at? |
| `wallet_transactions` | customer_id, paid_credit, bonus_credit, debit, refund, reason, source, balance_after, created_at *(append-only)* |
| `referrals` | referrer_id, referred_customer_id, code, status, reward, completed_visit_id |
| `reminders` | customer_id, service_id, type, scheduled_time, channel, delivery_status, booking_created, **cycle_key** |
| **`notifications` / `notification_deliveries`** | **NEW —** intent vs. per-channel attempt, with **`acked_at`** (§12) |

**Supporting tables, also Tier 1 — created in M1.** These were implied by the specs above rather
than listed, and are recorded here so the PRD matches the schema:

| Table | Why it exists |
|---|---|
| `consents` | **Append-only per-purpose consent events**; current state is the latest row per purpose. A `jsonb` column on `customers` cannot be append-only, and DPDP requires consent to be per-purpose and withdrawable with a provable history (RULES 11.6) |
| `wallet_accounts` | Per-customer balance **cache** of the ledger, written only by `app.wallet_post` under a row lock. The ledger remains the source of truth; this exists so a balance read is not a full ledger sum |
| `service_addons` | Join table replacing `add_ons.relevant_service_ids`. An array cannot carry a foreign key, so it cannot stop an add-on pointing at a deleted or cross-tenant service |
| `staff_schedules` / `staff_time_off` | `staff.working_hours jsonb` cannot be checked by the database. The no-double-booking exclusion constraint needs real rows to exclude against |
| `message_templates` | Per-salon message bodies with a Crayora default (`salon_id is null`). Push bodies live here; WhatsApp and RCS text lives at the provider, so only the provider template id is stored |
| `customer_service_intervals` | Median days between visits per customer per service, with a sample size. This is what makes a reminder due-date personal rather than a fixed cycle |

> **Why `booking_items` matters:** a booking must remember what it cost *at the time*. Without
> snapshotting, editing a service price silently rewrites past revenue and breaks every
> dashboard number.

### 8.3 Advanced-feature tables (Tier 2/3; each has `salon_id`)

`packages`, `customer_packages`, `package_redemptions`, `loyalty_ledger` (append-only),
`waitlist`, `feedback`, `invoices`, `photos`, `gift_cards` *(legal review — closed-loop,
non-cash)*, `campaigns`, `branches`, `audit_log`, `notification_tokens`.

Machinery tables (see `ARCHITECTURE.md` §6.2, §9): `domain_events`, `jobs`, `idempotency_keys`,
`webhook_events`, `rate_limit_counters`, `daily_salon_metrics`, `retention_cohorts`.

> **Built in M1, despite being listed here.** Tier is a **feature** ordering, not a schema
> ordering, and four of these are Tier 1 infrastructure that later features sit on top of:
> `audit_log` (ADR-18 requires the audit row to be written in the same transaction as every admin
> mutation, from the console's first day), `loyalty_ledger` (append-only from the start —
> retrofitting immutability onto a table that already has history is not possible),
> `notification_tokens` (push is Tier 1 infra per §10.1), and every machinery table.
>
> Creating them in M1 costs nothing — an empty table with forced RLS and no policies is
> unreachable — and it means the leak test, the money test and the grant model cover them from
> the day they exist rather than the day they are first used. The remaining §8.3 tables
> (`packages`, `customer_packages`, `package_redemptions`, `waitlist`, `feedback`, `invoices`,
> `photos`, `gift_cards`, `campaigns`, `branches`) are **not** created.

### 8.4 Status enums (never delete — use statuses)

Booking: Pending/Confirmed/Completed/Cancelled/No-show · Referral:
Invited/Registered/Pending visit/Rewarded/Rejected · Wallet:
Payment pending/Credited/Debited/Refunded/Reversed · Reminder:
Scheduled/Sent/Delivered/Failed/Converted/Opted out · Package: Active/Exhausted/Expired ·
Subscription: Active/Past due/Cancelled · Salon: Setup/Active/Suspended.

### 8.5 Ledger integrity (wallet + loyalty)

Append-only; reversals are new rows, never edits or deletes; **paid vs bonus stored as separate
lots with independent expiry**; **store credit and loyalty points are non-withdrawable as cash**
(keeps the product outside RBI PPI licensing — closed-loop).

**Top-ups are non-refundable — with the limits law requires (v4.3).** Money added to a salon
wallet does not return to the customer's bank or to cash on request. There is no
refund-to-source path and no cash-out path in the product.

That rule holds **only while the salon can still serve the customer.** An unqualified
"non-refundable" is an unfair contract term under the Consumer Protection Act, 2019, so three
carve-outs are part of the design, not exceptions to it (§16A.2):

- **Paid credit never expires.** No setting can make it expire.
- **A cancelled service returns value into the wallet** as a new credit entry — the customer is
  made whole in credit.
- **If the salon closes, is suspended, or the customer transfers away, the salon must settle the
  outstanding balance** in service value or money. This is a contractual obligation on the salon
  in the Crayora agreement, and it is surfaced in the offboarding and transfer flows.

The customer must see the whole picture — bonus amount, bonus expiry, that paid credit does not
expire, that credit works only at this salon, and that it is not withdrawable as cash — **on the
Add Money screen, before they pay.**

**Only these things change a balance** — the list is deliberately short and complete:

1. A **captured** Razorpay payment (top-up or package purchase).
2. A spend at checkout.
3. Expiry of a credit lot.
4. A referral reward released by the system after a paid first visit.
5. A **Crayora super-admin correction**, reason-required and audit-logged, for genuine system
   errors only.

**Neither the owner nor the manager can change a customer's balance by hand.** There is no such
screen, no such button, and no such API (§9.5). This is the strongest guarantee in the product:
a salon owner cannot quietly add credit to a friend's account or take it from a customer's.

**Spend order:** package → wallet → gateway; and within wallet, **bonus lots first, then paid
lots, both FIFO by expiry**. Bonus expires, so spending it first means the customer loses the
least.

---

## 9. Core feature specs (Tier 1)

### 9.1 My Salon Wallet

Store-credit ledger (not cash), non-withdrawable, **non-refundable**. Customer sees credit,
name+mobile, last visit/service, Add Money, Use at Checkout, history, Book Next Visit, offer +
terms. Example: ₹500 → +₹50 → ₹550. Paid vs bonus tracked as separate lots.

**Who configures what (v4.1):**

| Setting | Set by | Where |
|---|---|---|
| Bonus rule (e.g. ₹500 → +₹50), minimum top-up | Crayora operator at setup, **owner thereafter** | Console at setup; **owner app** afterwards |
| **Bonus** credit expiry | **The salon owner** | **Owner dashboard in the app** |
| **Paid** credit expiry | **Nobody — it never expires** | No such control exists (§16A.2) |
| Whether a balance can be changed by hand | **Nobody** | No such control exists |

Bonus credit expires by default after **180 days**; the owner may change that number. **Paid
credit never expires, and there is no setting that can make it expire** — expiring money a
customer actually handed over is an unfair contract term under the Consumer Protection Act, and
it also weakens the closed-loop position that keeps this product outside PPI licensing. As with
manual adjustment, the capability is *absent* rather than defaulted off.

**Every expiry and non-refundability term is shown on the Add Money screen, before the customer
pays.** Not in a terms page, not afterwards — on the screen where they decide.

**AC:** [ ] top-up creates a paid lot + a bonus lot and two ledger rows with `balance_after` ·
[ ] history immutable (UPDATE/DELETE blocked at the database, not just in code) ·
[ ] balance changes only via the five paths in §8.5 · [ ] **no owner or manager control exists
that changes a balance** · [ ] two concurrent debits cannot overdraw · [ ] bonus is spent before
paid credit · [ ] expiry posts a debit entry, never a silent edit · [ ] **no refund-to-bank and
no cash withdrawal path anywhere** · [ ] non-refundability and expiry shown before payment ·
[ ] owner can change the expiry rule from the app, and the change never alters credit already
issued under the old rule.

### 9.2 Smart Reminder & Quick Booking

Expected service-due reminder, not spam. Customer sees last service, suggested date, slots,
preferred barber, Book Now, reschedule/cancel, permission toggle. Cycles owner-editable (Haircut
25–35d, Beard 10–15d, Colour 25–45d, Facial 30–45d). **Enhancement:** after 2+ visits, use the
customer's own **median** interval, clamped to the owner's range. Prefer **push** (free);
WhatsApp only if push is unacknowledged or the customer opted into WhatsApp.

**AC:** [ ] mark-complete schedules exactly one reminder, enforced by a database uniqueness
constraint on `(salon_id, customer_id, service_id, cycle_key)` · [ ] booking stops duplicate
reminders for that cycle · [ ] opt-out honoured · [ ] push tried and **its acknowledgement
awaited** before any paid WhatsApp (§12).

### 9.3 Booking Add-ons

Relevant, transparent add-ons at booking time. **Never pre-selected**; total and duration update
instantly; only relevant suggestions; owner can toggle/price/limit by staff; unavailable items
disappear.

**AC:** [ ] nothing checked by default · [ ] instant total/duration update · [ ] only relevant
add-ons shown · [ ] **two customers cannot book the same barber for overlapping times** — a
database constraint, not an application check.

### 9.4 Refer & Earn

Unique link/code; WhatsApp share; pending/successful; earned reward; clear rules. Reward stays
Pending until the friend completes a **paid** first visit. No self-referral; one referrer per new
customer; cancelled/refunded don't qualify; owner monthly cap. Referrals are **within the salon**
— a referred friend binds to the same salon (§6.5).

**AC:** [ ] reward releases only after a paid completed first visit · [ ] cancelled/refunded
releases nothing · [ ] self-referral rejected · [ ] one referrer per referred customer, enforced
by constraint.

### 9.5 Owner Dashboard

Cards: today's revenue, today's bookings, avg bill, repeat/new this month, wallet collected,
outstanding credit, reminder-generated bookings. Plus barber revenue, top-20 customers,
due-for-visit, popular services/add-ons, referrals, cancelled/missed, **customer bind rate**.
One-tap: add customer, walk-in booking, **mark complete**, send reminder, cancel booking, export.
**Messaging spend is shown beside reminder conversion** — cost per channel this month, and the
bookings those reminders produced. Neither number is shown without the other: cost alone invites
switching off reminders, conversion alone invites spending Rs 1.28 a message without noticing.
**Cohort retention view** (30/60/90-day return %, wallet vs non-wallet) ships in MVP. Settings
the owner controls here: catalogue, staff, cycles, wallet bonus rule and **credit expiry**.

> **Removed in v4.1: the "adjust wallet" action.** Neither owner nor manager can change a
> customer's balance by hand — there is no control, no API, and no permission that grants it.
> The dashboard shows balances; it cannot move them. Genuine system errors are corrected by
> Crayora super-admin only, with a reason, in the audit log (§8.5).

**AC:** [ ] card totals match completed transactions exactly, verified by a nightly
reconciliation that **alerts on mismatch rather than silently correcting** · [ ] mark-complete
one tap from day view · [ ] **no wallet-adjustment control exists anywhere in the owner or
manager UI, and no endpoint would accept one** · [ ] the owner can change the credit expiry rule
and it applies only to credit issued afterwards.

---

## 10. Advanced features (Tier 2/3 specs)

### 10.1 Push notifications (Tier 1 infra, powers everything)

**FCM** for Android push — free, native, install-first's biggest advantage. Push is the
**primary** channel for booking confirmations, reminders, wallet receipts, referral news;
WhatsApp/SMS are fallback or explicit marketing opt-in. Notifications carry the **salon's** name
and logo (§6.6), never Crayora's.

**Gap closed — FCM does not prove delivery.** FCM confirms *acceptance by Google*, not delivery
to the device. Escalating on FCM's response alone would either never escalate or always
escalate, and the whole margin thesis depends on measuring this correctly. Therefore every push
carries a `delivery_id`, the app **acknowledges receipt**, and escalation happens only if no ack
arrives within a purpose-specific window (booking confirmation 5 min · receipt 15 min · reminder
6 h · billing 1 h).

**AC:** [ ] push delivered for confirmations/reminders/receipts · [ ] app acknowledges every
received push · [ ] WhatsApp sent only after an unacknowledged window or explicit opt-in ·
[ ] dead tokens marked immediately on `UNREGISTERED` · [ ] push:WhatsApp ratio reported per salon.

### 10.2 Memberships & prepaid packages (Tier 2)

Owner defines bundles ("4 haircuts / month", "unlimited beard trim / ₹999"). Customer buys →
`customer_packages` tracks remaining/expiry. At checkout, package auto-applies before wallet/UPI.

**AC:** [ ] package decrements on redemption · [ ] expiry enforced · [ ] checkout applies
package → wallet → UPI in that order, recorded in `payment_allocations`.

### 10.3 Loyalty points & tiers (Tier 2)

Earn points per ₹ spent (append-only `loyalty_ledger`); tiers unlock perks. Non-withdrawable.

**AC:** [ ] points immutable ledger · [ ] tier recalculated on spend · [ ] redemption creates a
debit entry, never a cash-out.

### 10.4 Waitlist & walk-in queue (Tier 2)

Join `waitlist` when full; auto-notify (push) on an opening. In-salon token/queue for walk-ins.
**AC:** [ ] waitlist notifies on cancellation/opening · [ ] queue token updates live.

### 10.5 Lifecycle automation (Tier 2)

Birthday, anniversary, win-back (no visit in 2× their cycle), package-expiry nudge, post-visit
thank-you. All respect consent + opt-out, prefer push.
**AC:** [ ] each trigger fires once per event, enforced by constraint · [ ] all respect opt-out ·
[ ] lapsed detection uses the per-customer learned cycle.

### 10.6 Feedback / NPS + review routing (Tier 2)

Post-visit push asks for a rating. High → prompt for a Google/Play review (the salon's own link,
from the console). Low → private feedback to the owner.
**AC:** [ ] rating captured post-visit · [ ] happy → public review prompt, unhappy → private
owner alert · [ ] never auto-posts on the customer's behalf.

### 10.7 Staff/barber app + commission (Tier 2)

Own schedule, assigned bookings, one-tap mark-complete, tips, commission. Ships in the **same
APK** as a role-gated shell, not a separate binary.
**AC:** [ ] staff sees only own schedule (RLS + role) · [ ] commission computed from completed
visits · [ ] mark-complete syncs to owner dashboard.

### 10.8 GST invoicing / digital receipts (Tier 2)

GST-compliant invoices when the salon has a GST number; plain receipts otherwise. Branded with
the salon's logo. **AC:** [ ] correct GST breakup · [ ] sequential invoice numbers per salon ·
[ ] PDF stored in R2 and linked via a signed URL.

### 10.9 Photo gallery (Tier 2)

Before/after and style photos, **explicit consent required**, private signed URLs.
**AC:** [ ] no photo stored or shown without a consent flag · [ ] customer can delete their own.

### 10.10 Home-service booking (Tier 2)

Toggle services as home-eligible; capture address + travel fee; route to available staff.

### 10.11 Per-salon white-label APK (Tier 3, premium)

The console triggers a CI build producing a signed, per-salon APK/AAB with its **own launcher
icon, app name and package id**, published to the salon's own Play listing. This is the only way
to get a true launcher icon (§6.6). Priced as a premium add-on; requires per-salon release
management and Play review lead time.

### 10.12 Gift cards (Tier 3 — legal review first)

Closed-loop, salon-specific, **non-cash, non-refundable-to-cash**. ⚠️ Third-party-purchased
redeemable value edges toward semi-closed PPI territory — **legal review required before
launch**.

### 10.13 Campaign builder, leaderboard, dynamic pricing, WhatsApp chatbot (Tier 3)

As per v3 §10.12–10.14.

---

## 11. Crayora super-admin console (Next.js on **Vercel**) — now Tier 1, Milestone 3

**This is no longer an internal support tool. It is the only way a salon comes into existence,
so it must be built before any salon can exist.** It is a separate web application, on its own
domain, with its own authentication — **never reachable with a tenant login**.

### Capabilities

| Area | What it does |
|---|---|
| **Provision** | The guided salon-creation flow of §6.2, ending in tenant + code + QR pack + owner invite |
| **Branding studio** | Live preview of the customer app while editing colours, fonts, logo, radius; publish bumps `salon_branding.version` and re-themes installed apps |
| **Catalogue & rules** | Services, add-ons, staff, wallet/reward/loyalty rules, reminder cycles |
| **Credentials** | The salon's own **Razorpay**, **Message Central** and **WhatsApp Business** credentials plus review link — **write-only**, encrypted at rest, with *Test connection* and rotation |
| **Messaging readiness** | Per-salon **WhatsApp template status** and **RCS agent status**; until each is green the ladder skips that rung. Neither affects login or push |
| **QR pack** | Regenerate and re-download printable collateral at any time |
| **Salon health** | Status, plan, last-active, **bind rate**, activation stage, message spend |
| **Support mode** | Time-boxed, reason-required, PII-minimised view of a salon's operational state; every access audit-logged |
| **Billing** | **Record the offline setup fee** (amount, date, reference) and **manually switch the salon on**; subscription state, dunning, comp/extend |
| **Suspend / reactivate** | Status change only — data is always retained, never deleted |
| **Customer binding** | **Unbind** (correction) and **Transfer to another salon** (§6.5) — super-admin only, reason-required, remaining balance acknowledged and recorded |
| **Wallet correction** | The **only** place a balance can be corrected by a human, for genuine system errors, reason-required and audit-logged (§8.5) |
| **Platform metrics** | MRR, setup-fee revenue, churn, time-to-provision, time-to-first-bind, push-vs-WhatsApp ratio, messaging cost |
| **Feature flags** | Roll Tier 2/3 features to selected salons |

**AC:** [ ] super-admin cannot be reached via tenant auth · [ ] every super-admin data access is
audit-logged · [ ] suspend disables tenant writes but retains all data · [ ] a secret, once
saved, can never be read back through the UI or the API · [ ] a non-engineer can provision a
salon end to end in under 30 minutes · [ ] **no provisioning step requires SQL or a deploy** ·
[ ] **switching a salon on is a deliberate manual action, never automatic** · [ ] a transfer
records the acknowledged remaining balance · [ ] wallet correction is reachable only here, only
by a super-admin, and only with a reason.

---

## 12. Messaging & notification strategy

**Channel priority is category-aware**, because WhatsApp's own pricing is. Push is always first
and free; every paid rung is billed to the salon.

| Category | Order | Cost per message |
|---|---|---|
| **Utility** — confirmations, receipts, referral | push → **WhatsApp Utility** → SMS | Rs 0 → Rs 0.17 → Rs 0.22 |
| **Marketing** — reminders, lifecycle, campaigns | push → **SMS** → WhatsApp Marketing *(owner opt-in)* | Rs 0 → Rs 0.22 → Rs 1.28 |
| **OTP** | WhatsApp Auth → SMS | Rs 0.17 → Rs 0.30 |

**WhatsApp Utility is cheaper than SMS** (Rs 0.17 vs Rs 0.22), so for confirmations and receipts
it wins on cost *and* richness *and* branding. **WhatsApp Marketing costs 6x SMS** (Rs 1.28 vs
Rs 0.22), and marketing is the high-volume category — for 300 customers on a monthly reminder, the
difference is Rs 384/month against Rs 65, which is most of a Starter subscription.

So **marketing escalation defaults to SMS**, with WhatsApp Marketing as an owner setting. A rich
WhatsApp reminder may convert better, and Rs 1.28 to drive a Rs 400 haircut is fine ROI *if it
converts* — so the owner dashboard shows **messaging cost beside reminder conversion rate** and
lets them decide from their own numbers (§9.5).

### 12.1b RCS — rich, branded, and cheaper (v4.7)

**RCS** delivers a branded message with images, carousels and buttons **into the phone's default
Messages app** — nothing to install. Message Central's *RCS Now* carries it on the salon's own
account, and the RCS agent shows the salon's **verified name and logo**, so even the sender chrome
is the salon's. That is a better white-label result than SMS can ever give.

It sits **above WhatsApp** because it is cheaper and better branded. But unlike WhatsApp its reach
is **conditional** — it needs a supporting carrier, a supporting device, and Google Messages as
the default SMS app. So the ladder checks whether a number can receive RCS *before* spending a
send, and falls through to WhatsApp when it cannot (ARCHITECTURE §12.2a).

**RCS agent verification is per salon** — Crayora arranges it during setup, like the WhatsApp
templates. It is a **third** per-salon onboarding item, not a replacement for the second, and like
the others it **blocks nothing**: until the agent is verified the ladder simply skips the rung, and
login and push are unaffected.

**Three things to confirm with Message Central before M8** (§21 Q-G): whether they expose a
capability check, whether they already do automatic SMS fallback — if they do, RCS and SMS collapse
into one rung and we must not double-send — and what RCS costs against WhatsApp and SMS.

### 12.1 Every message comes from the salon (v4.2)

Because the salon code is now entered **before** login (§6.4), the system knows which salon is
involved at the moment the very first OTP is requested. So there is no longer a category of
message that has to come from Crayora.

| Message | Sender account | Who pays |
|---|---|---|
| **First OTP (joining)** | **The salon's** Message Central | The salon |
| Later OTPs (returning customer) | **The salon's** Message Central | The salon |
| Owner / staff login OTP | The salon's Message Central | The salon |
| Confirmations, reminders, receipts, referrals, lifecycle | **The salon's** Message Central / WhatsApp Business | The salon |

**How the system knows which salon to send from,** in this order:

1. A **pending join** for that phone number — created when the customer entered the salon code,
   short-lived. This is what routes the *first* OTP.
2. An existing **customer binding** for that number — routes every later OTP.
3. An existing **owner/staff record** for that number — routes salon-staff logins.
4. **None of the above → the OTP is refused.** A number with no salon context has no legitimate
   reason to request a code, and refusing costs an attacker everything.

**Salons send OTP from day one (§16A.5).** Message Central is a top-up-and-send arrangement with
no DLT registration required from Crayora or from the salon, so a salon can authenticate
customers immediately after activation. There is no waiting state and no staged switchover.

### 12.1a Who controls each message — three tiers

The three channels are not equally ours. Knowing which is which decides where salon branding can
be guaranteed and where it cannot.

| Channel | Who authors the message | Salon branding |
|---|---|---|
| **Push (FCM)** | **Us, entirely** — title, body, salon logo as large icon, salon colour, per-salon channel name | **Full.** Every element |
| **WhatsApp** | **Authored in the Message Central dashboard**, per salon account, during setup. Our code supplies the variables only | **Full**, once the operator writes the salon's name into the template at setup |
| **OTP SMS** | **Message Central. Fixed.** Neither the body nor the sender header is ours, and it cannot be changed by code | **None** |

**The OTP is the one message we cannot brand, and that is accepted.** Do not build code that
templates it, validates it, or injects a salon name into it — there is no such hook.

**The reordered join flow is what makes this a non-issue.** Because the customer enters the salon
code *before* logging in (§6.4), the screen they are staring at while the code arrives is already
fully the salon's — its logo, its colours, its name, *"Joining Studio Nine Salon"*. The context is
established by the app, not by the SMS. The SMS only has to carry six digits. Had we kept the
v4.1 order — login first, code second — the customer's very first impression would have been an
unbranded SMS from an unfamiliar sender with no context at all.

**Build consequences:**

- `message_templates` in our database governs **push** in full, and for **WhatsApp** stores only
  the template identifier and variable order — never the body text, which lives in Message
  Central.
- **Authoring each salon's WhatsApp templates in Message Central is a provisioning task** for the
  Crayora operator (§6.2), not a code or data task in this repo.
- Validation we *can* do: that a salon has a WhatsApp template registered for each key and locale
  it needs, and that our variable count matches. Validation we cannot do: anything about the
  wording.
- **This is a further argument for push-first.** Push is the only channel where Crayora controls
  the whole experience, and it is also the free one.

**The one fallback.** If a salon's Message Central credentials are missing, untested, or a send
fails, OTP goes out on **Crayora's account** instead, so a billing lapse or a misconfiguration
never locks customers out of a working salon. This is **never a normal state**, so every
occurrence is logged, counted and **alerted** in the console. Crayora bears that cost until the
salon's account is fixed.

**Abuse note.** Anyone holding a valid salon code can request OTPs, and those SMS are now billed
to that salon. Per-salon daily OTP caps and per-phone/IP/device limits are therefore mandatory
(§15), and the owner sees their OTP volume alongside their other messaging spend.

**Consequences of per-salon sending — plan for these at provisioning:**

- **WhatsApp template approval is per salon.** Each salon's own WhatsApp Business account needs
  its own templates approved by Meta. This is not one approval for the platform; it is one set
  per salon, and it is on the critical path for that salon's WhatsApp messaging.
- **A salon can go live before WhatsApp approval.** Push and the app work immediately; the
  channel ladder simply skips WhatsApp until the salon's `whatsapp_template_status` is approved.
  Template approval must never block a salon from binding customers.
- **The salon's Message Central account should work before customers join**, because it carries
  the OTP (§12.1) — and needs no registration to do so. The console **tests it before
  activation**, and the platform fallback exists so a later outage cannot lock anyone out.
- **All messaging cost — including OTP — is billed to the salon by their own providers**, not by
  Crayora (see §14).

### 12.2 Rules

- **OTP:** Message Central VerifyNow via Supabase's **Send SMS Hook** (§0 and ARCHITECTURE §5.2),
  routed to **the salon's** account by the resolution order in §12.1; no DLT needed, and the
  message body is Message Central's and unbrandable (§12.1a).
  **Rate-limit OTP requests** per phone, per IP, per device **and per salon per day** — every OTP
  is now a paid SMS on *the salon's* bill, so the cap protects the owner, not us.
- **Utility** (booking / wallet / receipt): push first, ack-gated (§10.1); the salon's WhatsApp
  utility template as fallback.
- **Marketing** (reminders, lifecycle, campaigns): push first; the salon's WhatsApp marketing
  template only with opt-in.
- **Every message carries the salon's display name and comes from the salon's own number.** To
  the customer it is their salon messaging them — Crayora is invisible. Templates are rendered
  server-side, so branding and locale are applied at send time.
- **Compliance, per salon:** Meta template pre-approval on that salon's WABA (needed for the
  WhatsApp rung, authored in the Message Central dashboard); withdrawable opt-in (also DPDP).
  **Neither blocks launch** — OTP and push are unaffected.

**Templates** (`{{salon}}` resolves to the salon's display name):

```
Reminder:  Hi {{name}}, your last {{service}} at {{salon}} was on {{last_visit}}.
           A slot is open {{suggested_date}}. Book: {{booking_link}}
Receipt:   ₹{{paid_credit}} received. ₹{{bonus_credit}} bonus added.
           {{salon}} credit: ₹{{balance}}. Details: {{wallet_link}}
Booking:   {{service}} booked {{date}} {{time}} with {{staff}}. Total ₹{{total}}.
           Manage: {{booking_link}}
Referral:  Your friend completed their first visit. ₹{{reward}} credit added.
           New balance: ₹{{balance}}.
Birthday:  Happy birthday {{name}}! A {{gift}} is waiting at {{salon}} this month.
Welcome:   Welcome to {{salon}}, {{name}}! Your account is now linked.
```

Locales: `en`, `hi`, and `hi_Latn` (Hinglish). Regional languages drop in as new template rows
with no code change.

---

## 13. Automations (Edge Functions)

| # | Trigger | Actions |
|---|---|---|
| A | Visit completed | update last-visit; add to history; compute next visit (learned interval); schedule exactly one reminder; award loyalty; decrement package; update staff commission + metrics |
| B | Wallet top-up confirmed (Razorpay webhook) | record paid + bonus lots separately; recalc balance; send receipt |
| C | Booking confirmed | reserve slot; push notify; stop duplicate reminder for that cycle |
| D | Referral visit completed | validate; credit both rewards; notify both |
| E | Daily owner summary | revenue; completed/missed; new vs repeat; add-on + package revenue; wallet collected/used; tomorrow's count |
| F | Lifecycle scan (scheduled) | birthday/anniversary/win-back/package-expiry |
| G | Waitlist opening | notify the next waitlisted customer |
| H | Post-visit feedback | send rating request; route review vs private alert |
| I | Subscription lifecycle | dunning; grace read-only; suspend on non-payment |
| **J** | **Customer bound (new)** | send branded welcome; seed consent defaults; notify owner; increment bind-rate metric |
| **K** | **Notification escalation sweep (new)** | promote unacknowledged pushes to WhatsApp/SMS per §10.1 windows |
| **L** | **Bonus-lot expiry (new)** | post expiry debit entries; nudge customers before expiry |

Every automation is guarded by a **database** uniqueness or state-transition constraint, so
retries, redeploys and offline replays are no-ops rather than duplicates.

---

## 14. Payments & billing

### Customer payments (Razorpay)

UPI/cards; explicit pending/failed states; **partial payment** across package → wallet → UPI,
recorded in `payments` + `payment_allocations`; never store raw credentials.

**Top-ups are non-refundable (§8.5).** There is no refund-to-source flow to build. A cancelled
service returns value **into the wallet** as a new credit entry; money never travels back to the
customer's bank.

**Per-salon Razorpay accounts (confirmed, v4.1).** Each salon's own key id, key secret and
webhook secret are entered in the console, so customer money settles **directly into the salon's
own bank account** — Crayora never holds customer funds. Consequences:

- Each salon gets its own **opaque webhook path**; the salon is identified from that path, never
  from the request body, which an attacker controls.
- Signatures are verified with **that salon's** webhook secret.
- Webhook amounts are re-verified against the order before any credit is posted.
- Crayora cannot see the salon's bank settlements, so reconciliation compares our `payments`
  rows against that salon's Razorpay payment list through their API, and flags mismatches in the
  console.

### Crayora revenue

| Component | Detail |
|---|---|
| **Setup fee** | **₹10,000–₹20,000 one-time, collected manually** — cash or bank transfer, outside the system. The console records amount, date and reference, and the operator then **switches the salon on by hand** (§6.2) |
| **Subscription** | Starter ₹399/mo · Growth ₹799/mo · Pro ₹1,499/mo *(proposals — validate in the pilot)* |
| **Messaging** | **Not a Crayora cost.** Push is free and platform-level; WhatsApp and SMS are billed to the salon by the salon's own Message Central and Meta accounts (§12.1) |
| **White-label APK** | Deferred (§10.11); built manually and quoted separately if a salon asks |

> **Open pricing consequence (§21 Q-A).** The v4.0 plan table differentiated tiers partly by
> "WhatsApp messages included." That no longer means anything, because Crayora does not pay for
> those messages. Plans should differentiate on **features** instead. Push-first is still worth
> selling hard — it now saves *the owner* money, which is an easier pitch than saving ours.

There is **no free trial** — the setup fee is the commitment. Plans start on the billing start
date set in the console.

**Non-payment:** past due → **7-day grace, read-only** → suspended → **90 days retained, with
notices to the owner at day 60 and day 80** → **operational and personal data purged**. Read-only
grace is **enforced in the database**, not by hiding buttons: a past-due tenant keeps `SELECT` and
loses `INSERT`/`UPDATE`. Salons often come back after a slow month, so the notices matter as much
as the purge does.

**But financial records are not purged (v4.3).** Invoices, payments and the wallet and loyalty
ledgers move to a **restricted archive** and are kept for the statutory books-of-account period,
with personal identifiers anonymised. Deleting them at 90 days would breach tax-record
requirements; keeping them identifiable would breach DPDP. Separating the two satisfies both
(§16A.6).

**Before any purge**, the owner is offered a full data export, and any **outstanding customer
credit must be settled by the salon** (§16A.2).

---

## 15. Non-functional requirements

**Offline handling:** cache read data locally; **queue owner write-actions offline** (above all
mark-complete and walk-in booking) and sync on reconnect. **Money never mutates offline** — an
offline completion records *intent*, and the wallet debit, loyalty award and package decrement
run server-side at sync time. Rejected offline actions surface in a **"Needs attention"** inbox
with a one-tap fix; they are never silently dropped. Salon branding is cached so the app stays
branded offline.

**Observability:** Sentry in the Flutter app and in Edge Functions sharing a trace id; structured
logs; push/WhatsApp delivery and **ack** rates; job queue depth and dead-letter alerts.

**Rate limiting & abuse:** OTP limits (phone + IP + device); **salon-code lookup limits**;
referral caps; wallet-adjustment audit.

**Backups & recovery:** Supabase PITR; **a documented and rehearsed restore procedure**; R2
versioning.

**Localization:** English + Hindi + Hinglish from Day 1, architecture ready for Odia, Telugu,
Tamil and others; per-salon and per-customer language; all templates localizable.

**Accessibility:** ≥48dp tap targets, ≥4.5:1 contrast, text scaling without clipping,
screen-reader labels.

**Performance:** dashboard cards from pre-aggregated metrics (<800ms p95); keyset pagination on
all lists; client-side image compression.

---

## 16. Security & compliance

- **Isolation:** RLS **enabled and forced** on every table; scoped data layer; the
  catalogue-driven cross-tenant leak test is a release gate.
- **Platform secrets:** Message Central, Razorpay, R2, FCM keys server-side only — never in the
  APK, never in the Vercel client bundle.
- **Per-salon secrets:** the salon's Razorpay, Message Central and WhatsApp credentials are
  stored encrypted at rest with a reference-only row in `salon_integrations`. Decryptable **only**
  inside Edge Functions with the service role. No tenant role can select them; the console shows
  last-4 and a *Test connection* result. Rotation replaces, never reveals. Never logged.
- **The OTP hook endpoint must authenticate its caller.** Supabase signs Send-SMS-Hook requests;
  the Edge Function **must verify that signature and reject anything else**. An unauthenticated
  hook URL is a free-SMS machine pointed at Crayora's Message Central bill. The OTP token is
  never written to a log.
- **Financial integrity:** immutable ledgers enforced by revoked grants *and* a blocking trigger;
  reversals are new rows, not deletes. **There is no manual balance-adjustment path for owners or
  managers at all**, so the largest internal-fraud surface in the product simply does not exist.
  Crayora super-admin corrections are reason-required and audit-logged.
- **Binding integrity:** one active phone→salon binding enforced by a global unique constraint;
  cross-tenant existence is never disclosed; unbind and transfer are super-admin-only and
  recorded in an append-only `binding_events` history.
- **DPDP Act (India):** per-purpose, withdrawable **consent ledger** (booking vs promotional vs
  photos vs WhatsApp) — not a single boolean; data export; **erasure by anonymisation** —
  identity fields are cleared and the phone is replaced by a salted hash while financial rows are
  retained, satisfying both erasure and ledger immutability; opt-out everywhere promo appears.
- **PPI and payment-aggregator avoidance:** wallet, loyalty and gift cards strictly closed-loop,
  non-cash, single-salon. **No cash-out code path and no Crayora-held float exists anywhere.**
  These are licensing boundaries, not preferences — see **§16A.1**.
- **Roles, retention, GST and messaging:** the full regulatory position, the sign-off checklist, and
  the items needing a lawyer or CA are in **§16A**.
- **Payment security:** tokenisation; per-salon webhook signature verification; amount
  re-verification.

---

## 16A. Legal & regulatory posture (India)

> **Not legal advice.** This section states the position the product is *built to*, and names
> what a lawyer and a chartered accountant must confirm before the first paying salon goes live.
> The engineering exists to make the compliant behaviour the *easy* behaviour; it does not
> replace professional sign-off. Items marked **⚖️** need that sign-off.

### 16A.1 Why Crayora is not a payment aggregator, and not a PPI issuer

Two structural choices carry most of the regulatory weight. Neither may be "simplified" later
without a fresh legal review.

| Choice | Regulatory effect |
|---|---|
| **Customer money settles into the salon's own Razorpay account** — Crayora never receives, holds, pools or disburses customer funds | Keeps Crayora outside the RBI Payment Aggregator authorisation regime. If Crayora ever collected into its own account and paid salons out, it would arguably be operating as a PA and would need RBI authorisation |
| **Wallet credit is closed-loop** — issued by one salon, redeemable only at that salon, never withdrawable as cash, never transferable between salons | Keeps the instrument outside the RBI PPI Master Direction. The exclusive one-phone-one-salon binding (§6.5) reinforces this: credit that could travel between salons would be *semi-closed* and would need authorisation |

**Therefore, three things are permanently prohibited in this codebase:** a Crayora-held float;
credit usable at any salon other than the issuer; and any cash-out path. These are not product
preferences — they are the boundary of the licensing exemption.

### 16A.2 Wallet credit and consumer protection ⚖️

The v4.1 rule "top-ups are non-refundable" is retained **with limits**, because an unqualified
version is an unfair contract term under the **Consumer Protection Act, 2019**.

| Situation | Rule |
|---|---|
| Customer simply wants their money back, service still available | **No refund.** Credit stays as credit. This is the commercially intended behaviour and is defensible |
| **Paid** credit expiring | **Never.** The capability does not exist (Q-C) |
| **Bonus** credit expiring | **Permitted** — it is a promotional incentive, not consideration paid. Default 180 days, owner-configurable, disclosed before payment |
| Salon cancels a paid service | Value returns **into the wallet** as a new credit entry |
| **Salon closes, is suspended, or stops serving the customer** | **The salon must settle outstanding credit** — service value or money. This is a contractual obligation on the salon in the Crayora agreement, and it is surfaced in the offboarding flow |
| Customer transfers to another salon | The old salon settles or honours the balance (Q-B) |

**Disclosure is a hard requirement, not a nicety.** The Add Money screen must show, before
payment: the bonus amount, the bonus expiry date, that paid credit does not expire, that credit
is usable only at this salon, and that it cannot be withdrawn as cash. A terms page elsewhere in
the app does not satisfy this.

### 16A.3 GST ⚖️

Salon credit is a general-purpose voucher, not a payment for an identified service, so the
architecture must keep two things separate:

| Event | Document | GST |
|---|---|---|
| Wallet top-up | **Receipt** — explicitly *not* a tax invoice | Generally **not** the taxable event; GST arises on redemption |
| Service delivered (paid by credit, package, UPI or any mix) | **Tax invoice** | GST on the service value |

Consequences the build must honour:

- A top-up receipt must never be labelled or numbered as a tax invoice.
- Because paid and bonus credit are tracked as **separate lots** (§8.5), the system can report
  the actual consideration received versus the discount given at redemption — which is what
  makes correct GST treatment of the bonus possible at all.
- Invoice numbering is **sequential per salon per financial year**.
- Crayora's own setup fee and subscription need a **GST tax invoice from Crayora to the salon**,
  so the console must capture the salon's **GSTIN and state** (place of supply determines
  IGST vs CGST/SGST).
- **⚖️ A CA must confirm** the treatment of the bonus at redemption and of unredeemed credit.

### 16A.4 DPDP Act, 2023 — who is responsible for what ⚖️

This was undefined before v4.3 and it materially changes the contracts and the app.

- **The salon is the Data Fiduciary** for its customers' personal data — it decides the purpose
  (its customers, its marketing, its records).
- **Crayora is the Data Processor**, processing on the salon's documented instructions.
- **⚖️ A written Data Processing Agreement is mandatory** in the Crayora–salon contract. DPDP
  requires a Fiduciary to engage a processor only under a valid contract; without it the salon
  is non-compliant and Crayora is the reason.
- Crayora is a **Data Fiduciary in its own right** for salon-owner and staff account data.

What the app must therefore show and do:

- **Itemised notice at consent** — what is collected, why, how to withdraw, and how to complain.
  Not buried in a terms page.
- **A per-salon grievance contact** in the app. The customer's counterparty is the salon; a
  Crayora-only support address is not sufficient.
- **Withdrawal must be as easy as consent** — one screen, per purpose.
- Export and erasure requests are made to the salon and executed through Crayora's tooling.
- **Adults only.** Accounts are for the phone-number holder, who must be 18+. A child's details
  captured for a family booking are a note on the adult's record, never an account, because
  verifiable parental consent and the ban on tracking children would otherwise apply.
- **Breach notification** to the Data Protection Board and affected users is a documented
  runbook, not an improvisation.

### 16A.5 Commercial messaging compliance ⚖️

**Message Central requires no DLT registration from Crayora or from any salon.** It is a top-up
and send arrangement: the provider carries the regulatory registrations, and messages go out
under its own registered headers and templates. This is why a salon can authenticate customers
from its first day, and why DLT appears nowhere in the provisioning checklist.

Two consequences the build must respect:

- **The OTP template and sender are Message Central's and cannot be changed** (§12.1a). No code
  path attempts to brand, template, or validate the OTP message.
- **WhatsApp templates are configured per salon in the Message Central dashboard** and still
  require **Meta approval**. That is the one piece of per-salon messaging paperwork, it is done
  by the Crayora operator at setup, and it gates only the WhatsApp rung of the ladder — never
  login, never push, never onboarding.

Marketing consent obligations are unchanged and are ours regardless of who registers the sender:
promotional messages go only to customers who opted in, opt-out is honoured at the first step of
the channel ladder, and consent is recorded per purpose (§16A.4).

**⚖️ Confirm in the Message Central contract** that the provider's registrations and templates
cover the traffic Crayora sends on behalf of salons, so the compliance position is contractual
rather than assumed.

### 16A.6 Record retention versus erasure ⚖️

The v4.1 rule "data deleted 90 days after suspension" **conflicts with tax law** and is corrected
here. Financial records must survive far longer than the operational data.

| Data | On salon offboarding |
|---|---|
| Operational + personal data (customers, bookings, photos, tokens, messages) | **Purged at 90 days**, with owner notices at day 60 and day 80, after an export is offered |
| **Invoices, payments, wallet and loyalty ledgers** | **Retained in a restricted archive for the statutory period** (books of account must be preserved for years under GST and income-tax rules — **⚖️ confirm the exact period with a CA**). Access is super-admin only and audit-logged |
| Personal identifiers inside retained financial records | **Anonymised** — name cleared, phone replaced by a salted hash — so the financial record survives without the person's identity |

DPDP permits retention where another law requires it, so anonymised financial retention satisfies
both regimes. Erasure of identity and preservation of accounts are not in conflict once they are
separated this way.

### 16A.7 Legal sign-off checklist — before the first paying salon

- [ ] **⚖️** Crayora–salon agreement, including the **Data Processing Agreement**, the salon's
      obligation to settle outstanding credit on closure or transfer, and setup-fee terms
- [ ] **⚖️** Customer terms and privacy notice, per salon, naming the salon as Data Fiduciary
- [ ] **⚖️** Counsel confirms the closed-loop / non-PPI and non-payment-aggregator position
- [ ] **⚖️** CA confirms GST treatment of top-ups, bonus at redemption, and unredeemed credit
- [ ] **⚖️** CA confirms the statutory retention period for the financial archive
- [ ] WhatsApp templates authored in Message Central and Meta-approved, per salon
- [ ] Grievance officer named and contactable, per salon and for Crayora
- [ ] Breach-notification runbook written and rehearsed

---

## 17. Build milestones (one per Claude Code session)

> **The order changed in v4.** The console now precedes everything customer-facing, because no
> salon can exist without it.
>
> **`PHASES.md` expands this table** into phases with demo-able exit criteria, per-milestone
> instructions, the non-obvious dependencies, and the two non-code tracks (legal, accounts,
> Play Store, pilot) that are the real critical path. Work from that file, not this table.

| M | Milestone |
|---|---|
| **0** | Repo + `CLAUDE.md` + `ARCHITECTURE.md` + Flutter + Supabase + FCM wired; i18n scaffold |
| **1** | Full schema (§8) + RLS (§7) + **catalogue-driven cross-tenant leak test** |
| **2** | ⭐ **Super-admin console v1 on Vercel** — provision a salon, branding, credentials (encrypted), salon code + QR pack, owner invite (§6.2, §11). **Moved ahead of auth in v4.2:** login now needs salon codes and per-salon Message Central credentials to exist first |
| **3** | ⭐ **Salon-code-first auth** — resolve code → theme the app → OTP **from that salon's** Message Central via the Send SMS Hook → claims hook; per-phone/IP/device/salon rate limits; platform fallback (§6.4, §12.1) |
| **4** | ⭐ **Binding + white-label** — bind atomically at first login (§6.5), full theming, pinned shortcut (§6.6) |
| **5** | Services, add-ons, staff, customer profiles, visit history, offline cache |
| **6** | Booking + slots + add-ons; slot-conflict constraint; offline queue + "Needs attention" |
| **7** | Wallet lots + ledger + Razorpay (simulated → live, per-salon keys) + Automation B |
| **8** | Reminders (push-first, ack-gated) + Automations A, C, K + learned interval |
| **9** | Refer & Earn + Automation D |
| **10** | Owner dashboard + cohort view + Automation E + nightly reconciliation |
| **11** | Setup-fee + subscription billing, dunning, read-only grace (Automation I) + console billing |
| **12** | Consent ledger, DPDP export/anonymise, opt-out, observability (Sentry), backups + restore drill |
| **13** | Release states (empty/loading/error), test checklist (§20), Play Store build |
| **14+** | Tier 2: packages, loyalty, waitlist/queue, lifecycle, feedback/NPS, staff shell + commission, GST invoicing, photo gallery, home-service |
| **15+** | Tier 3: multi-branch, **per-salon white-label APK**, gift cards (post legal review), inventory, campaigns, dynamic pricing, WhatsApp chatbot |

> Ship M0–M10 with **simulated payments** = the working prototype; wire real Razorpay +
> Message Central credentials and Meta templates before onboarding a paying salon.

---

## 18. 30-day pilot

Baseline first (avg bill, repeat gap, weekly customers, no-shows, referral method). W1 setup +
train the owner on one workflow **and on the QR handover**. W2 wallet + reminders, daily
payment/refund/balance checks. W3 add-ons + referrals for completed customers. W4 compare vs
baseline. Continue only with features that produced real usage or saved owner time.

**Watch bind rate weekly.** If customers are not being asked to scan, nothing else in the product
can work.

---

## 19. Owner discovery checklist (now the sales intake form)

Ten common services + prices + durations · repeat services + cycles · how customers book today ·
barbers per shift · main cancellation cause · two best-margin add-ons · safe wallet amount +
bonus · bonus expiry · when a referral reward becomes valid · which daily numbers the owner
wants · who marks services complete · GST registered? · preferred languages · **brand assets
(logo, colours, fonts)** · **Razorpay account details** · **Google review link**.

---

## 20. Release test checklist

**Isolation & binding**

- [ ] Cross-tenant isolation passes (automated, catalogue-driven)
- [ ] A phone bound to Salon A cannot bind to Salon B
- [ ] No customer-facing salon-switch or salon-add path exists anywhere
- [ ] The "already registered" message never names the other salon
- [ ] Super-admin transfer moves the binding, leaves wallet and history with the old salon, and
      records the acknowledged balance

**Money**

- [ ] **No wallet-adjustment control exists for owner or manager, and no endpoint accepts one**
- [ ] Bonus amount, bonus expiry, "paid credit never expires", "this salon only" and "no cash
      withdrawal" are **all** shown on the Add Money screen, before payment
- [ ] **No setting, column or code path can expire paid credit**
- [ ] A top-up produces a receipt, not a tax invoice; GST appears on the service invoice
- [ ] Suspending and purging a salon offers an export, requires outstanding credit to be settled,
      purges personal data, and **retains anonymised financial records**
- [ ] Concurrent wallet debits cannot overdraw
- [ ] Bonus credit is spent before paid credit
- [ ] Expiry posts a ledger entry; owner expiry changes do not alter credit already issued
- [ ] No refund-to-bank and no cash-out path exists anywhere
- [ ] Failed payment handled; cancelled service returns value into the wallet
- [ ] Dashboard totals match completed transactions

**Booking & loop**

- [ ] Duplicate booking / full slot rejected by a database constraint
- [ ] Add-ons never pre-selected
- [ ] Self-referral rejected; cancelled referral releases nothing
- [ ] Reminder opt-out honoured; exactly one reminder per cycle
- [ ] Offline mark-complete syncs; rejected actions surface in "Needs attention"
- [ ] Owner logs into the app with the registered number and runs the daily workflow unaided

**Provisioning & branding**

- [ ] A non-engineer provisions a salon in the console with no SQL
- [ ] Switching a salon on is a deliberate manual action
- [ ] Branding published in the console reaches the app on next open
- [ ] Contrast check blocks an unreadable palette at publish time

**Messaging**

- [ ] Push acknowledged; WhatsApp only after an unacked window or explicit opt-in
- [ ] Messages send from **the salon's own** WhatsApp/Message Central account and carry the
      salon's name
- [ ] A salon with unapproved templates still works — the ladder skips WhatsApp cleanly
- [ ] The app is branded as the salon **before** the phone-number screen
- [ ] The first OTP sends from **the salon's** account; an OTP request with no salon context is
      refused; the hook endpoint **rejects unsigned requests**
- [ ] **No code attempts to template, brand or validate the OTP message** — it is Message
      Central's and fixed
- [ ] The screen shown while the customer waits for the OTP is fully salon-branded
- [ ] Every **push** notification carries the salon's name, logo and colour
- [ ] Each salon has a WhatsApp template registered per key and locale it needs, with matching
      variable counts
- [ ] OTP is rate-limited per phone, IP, device **and per salon per day**
- [ ] A broken salon Message Central account falls back to the platform and raises an alert

**Security & compliance**

- [ ] No secret keys in the APK or the Vercel client bundle
- [ ] Per-salon secrets unreadable after save
- [ ] Per-salon WhatsApp templates authored in Message Central and Meta-approved before that salon's WhatsApp rung goes live
- [ ] DPDP export and anonymise work; anonymise preserves ledger and binding integrity
- [ ] Every super-admin access is audit-logged
- [ ] Backup restore rehearsed

---

## 21. Risks & open questions

| Risk | Mitigation |
|---|---|
| **Bind rate is the whole funnel** — if the owner doesn't ask, nothing happens | Printed collateral, owner training, bind rate on the dashboard and in the console |
| **Wrong-salon binding** | Explicit confirmation screen naming the salon before binding; audited super-admin unbind and transfer through customer support (§6.5) |
| **A transferring customer loses their wallet balance** | Support must state the balance and record the customer's acknowledgement before transferring (§6.5) |
| **Per-salon WhatsApp approval delays a salon's messaging** | Salon goes live on push immediately; the ladder skips WhatsApp until that salon's templates are approved (§12.1) |
| Manual visit-completion capture (MVP) | One-tap offline mark-complete; staff shell (Tier 2) moves it to the barber |
| Setup fee raises the acquisition bar | Sales-led motion; setup fee funds the operator time it genuinely costs |
| Console becomes a bottleneck | Time-to-provision tracked; templates and defaults for common salon types |
| Per-salon secrets are a juicy target | Encrypted at rest, write-only UI, service-role-only decryption, never logged |
| Messaging cost erodes margin | Push-first with ack gating; allowances + pass-through overage |
| Meta template approval delays a salon's WhatsApp rung | Draft and submit early; the ladder skips WhatsApp meanwhile, and login and push are unaffected |
| Gift-card PPI exposure | Legal review before launch; strictly closed-loop |
| Tenant-isolation bug | RLS + forced RLS + scoped layer + catalogue-driven leak test as a release gate |
| Feature bloat delaying launch | Strict tiering — ship the Tier 1 loop first |

### Resolved in v4.1

Every question v4.0 left open has been answered — OTP delivery, salon transfer, Razorpay
accounts, wallet refundability, wallet expiry, manual wallet adjustment, owner login, setup-fee
collection, messaging identity, fonts, data retention, and the Tier 3 white-label APK. The
rulings are in *Decisions locked in v4.1* at the top of this document.

### Closed in v4.3 — best practice, adjusted for Indian law

| # | Question | **Ruling** | Legal driver |
|---|---|---|---|
| **Q-A** | Plan differentiation | **Features only.** Starter = core loop; Growth = packages, loyalty, lifecycle, feedback; Pro = staff app, commission, GST invoicing, home-service. The message-allowance column is removed | None — commercial only |
| **Q-B** | Leftover credit on transfer | **The old salon must settle or honour it.** Support offers the customer service-value or cash at the old salon; the transfer is recorded with the balance and the outcome. Silent forfeiture is not offered | Consumer Protection Act 2019 — keeping money for services never rendered is the textbook unfair-contract term |
| **Q-C** | Expiry on **paid** credit | **Not permitted. The capability is removed.** Bonus credit may expire; money the customer actually paid never does | Consumer Protection Act 2019; also protects the closed-loop/PPI-exempt position |
| **Q-D** | Who sets up the salon's messaging accounts | **Crayora, as part of the paid setup** — the Message Central account, the WhatsApp Business account and its templates, and **the salon's RCS agent verification** | Meta requires per-salon template approval; Google and the carriers require per-salon RCS agent verification; no DLT is involved |
| **Q-E** | OTP when a salon's account is unavailable | **Salons send OTP from their own account from day one.** Crayora's account is a **fault-only fallback** — credentials missing, untested, or a send failed — logged, counted and always alerted | No registration dependency; Message Central is top-up-and-send (§16A.5) |
| **Q-F** | Public branding by salon code | **Yes.** Logo, palette and fonts only, `active` salons only, rate-limited | None — no personal data involved |

### Open again in v4.7 — RCS

| # | Question | Why it matters | Assumption until answered | Needed by |
|---|---|---|---|---|
| **Q-G** | Does Message Central's RCS Now expose a **capability check**, does it perform **automatic SMS fallback**, and what does RCS **cost** versus WhatsApp and SMS? | Decides whether the RCS rung is gated or attempt-and-see, whether it replaces the SMS rung entirely (double-sending if we both implement fallback), and whether it belongs above WhatsApp at all | Capability check exists · no provider-side auto-fallback · cheaper than WhatsApp | **M8** |
| **Q-H** | How long does per-salon RCS agent verification take? | It is a third per-salon onboarding item. If slow, salons run on push + WhatsApp meanwhile — which the ladder already tolerates | Days to weeks, non-blocking | **M2** |

> **Correction, v4.6.** An earlier draft treated per-salon DLT registration as a prerequisite for
> OTP, which would have delayed every salon's launch by weeks. **No DLT registration is required
> anywhere** — Message Central is top-up-and-send. A second draft then assumed we could put the
> salon's name in the OTP body; we cannot, because that template belongs to Message Central. The
> app screen carries the branding instead (§12.1a).

---

## Appendix A — `CLAUDE.md` (paste into project root)

```markdown
# Cray Salon — Project Context for Claude Code

## What this is
Multi-tenant SaaS Android app for local salons, per-salon white-labelled. One codebase,
one database, many salons, fully isolated. Retention loop: wallet, reminders, add-ons,
packages, loyalty, referrals, owner dashboard. Crayora SELLS and PROVISIONS each salon
from a Next.js super-admin console on Vercel — owners do NOT self-onboard.

## Read these every session
- `RULES.md` — THE BINDING RULES. Read this first, every session, before any code.
- `Cray-Salon-PRD-v4.md` — scope, features, acceptance criteria
- `ARCHITECTURE.md` — mechanisms, invariants, ADRs. On mechanism, ARCHITECTURE wins.
- `DESIGN.md` — tokens, typography, layout, components, motion, chart rules.

RULES.md section 2 lists capabilities that DELIBERATELY DO NOT EXIST. Check it before
building anything that sounds reasonable but is absent.

## Stack (do not substitute without asking)
- App: Flutter / Dart, install-first. ANDROID SHIPS FIRST for cost reasons; the code
  stays iOS-compatible and app/ios must never rot (RULES 8.11)
- Admin console: Next.js on Vercel
- Auth: Supabase Auth (phone OTP)
- OTP delivery: Message Central via Supabase's Send SMS Hook, routed to THE SALON'S
  OWN account (salon code is entered BEFORE login, so the salon is always known).
  Crayora's platform account is a logged, alerted fallback only. Verify the hook
  signature; never log the token; refuse OTP for a number with no salon context.
- DB + isolation: Supabase Postgres + Row-Level Security (RLS)
- Files: Cloudflare R2 (logos, photos, invoices) — signed URLs for private files
- Serverless + all messaging/payment calls: Supabase Edge Functions
- Payments: Razorpay — EACH SALON'S OWN ACCOUNT (per-salon keys + webhook secret).
  No refunds: wallet top-ups are non-refundable.
- Messaging: EACH SALON'S OWN Message Central + WhatsApp Business account, from day
  one. NO DLT REGISTRATION ANYWHERE — Message Central is top-up-and-send.
  Message control has three tiers (PRD 12.1a):
    PUSH     -> ours entirely; full salon branding; the only channel we fully control
    WHATSAPP -> template authored in the MESSAGE CENTRAL DASHBOARD per salon at setup,
                Meta-approved; our code supplies VARIABLES ONLY, never body text
    OTP SMS  -> MESSAGE CENTRAL'S, FIXED, UNBRANDABLE. Never write code that templates,
                brands or validates it. Branding comes from the app screen instead.
- Push: Firebase Cloud Messaging (FCM) — primary channel, WhatsApp is fallback
- Crash reporting: Sentry
- i18n: en / hi / hi_Latn from day one

## Non-negotiable rules
1. Every table has `salon_id`. Every query tenant-scoped. RLS enabled AND forced.
   NEVER write a query that can return another salon's data.
2. One phone number has exactly ONE active salon binding. No switch path in the app,
   no such API. Unbind and transfer exist ONLY as audited Crayora super-admin actions.
2b. SALON CODE COMES FIRST, THEN LOGIN. The app themes itself to the salon before the
   phone-number screen, and the OTP is sent from that salon's account. Never build a
   flow that authenticates before the salon is known.
3. Secrets (platform and per-salon) live server-side only, encrypted at rest,
   never readable back through any UI or API.
4. Call Message Central and Razorpay only from Edge Functions.
5. wallet_transactions and loyalty_ledger are append-only. Reversals are new rows,
   never edits/deletes. Money never mutates offline.
6. Store credit and loyalty points are non-withdrawable as cash AND top-ups are
   NON-REFUNDABLE. There is no refund-to-bank and no cash-out path. A cancelled
   service returns value INTO the wallet as a new credit entry.
6b. NEITHER OWNER NOR MANAGER can change a customer's balance by hand. Do not build
   such a screen, endpoint, or permission. Corrections are Crayora super-admin only.
6c. BONUS credit expiry is configured by the SALON OWNER in the owner app. PAID CREDIT
   NEVER EXPIRES — there is no setting, no column, no code path that can expire it.
   Bonus is spent before paid credit. Bonus amount, bonus expiry, "paid credit never
   expires", "usable only at this salon" and "not withdrawable as cash" are ALL shown
   on the Add Money screen BEFORE the customer pays.
6d. LICENSING BOUNDARIES — never "simplify" these (PRD 16A.1):
   - Customer money settles into THE SALON'S OWN Razorpay account. Crayora never
     receives, holds, pools or disburses customer funds. No float, ever.
   - Credit is redeemable ONLY at the issuing salon. Never across salons.
   Breaking either turns Crayora into an unlicensed payment aggregator or PPI issuer.
6e. If a salon closes, is suspended, or a customer transfers away, outstanding credit
   MUST be settled by the salon. Build the flows that surface this; do not silently
   forfeit a balance.
7. Add-ons are never pre-selected.
8. Referral rewards release only after a completed PAID first visit.
9. Salons are provisioned ONLY through the console — never SQL, never a deploy.
   Switching a salon on is a deliberate manual operator action; the setup fee is
   collected offline and only RECORDED in the console.
9b. The owner logs into the SAME Android app with the mobile number registered in the
   console. There is no owner self-signup.
10. Prefer push (free, platform-level) over WhatsApp (paid, billed to the salon), and
   gate escalation on a delivery ACK. If a salon's WhatsApp templates are not yet
   approved, skip WhatsApp for that salon — never block the salon.
11. Owner write-actions (esp. mark-complete) work offline and sync idempotently.
12. Consent is per-purpose and withdrawable (DPDP); export + anonymise both work.
    The SALON is the Data Fiduciary, Crayora is the Data Processor — the app shows a
    PER-SALON grievance contact, not just a Crayora one.
12b. Purging a salon deletes OPERATIONAL + PERSONAL data only. Invoices, payments and
    ledgers move to a restricted, anonymised archive for the statutory period. Never
    hard-delete a financial record.
12c. A wallet top-up produces a RECEIPT, never a tax invoice. GST arises when the
    service is delivered, on the service invoice.
13. The launcher icon CANNOT be changed at runtime. In-app branding + pinned shortcut
    is the Tier 1 answer; a per-salon signed APK is the Tier 3 answer. Do not attempt
    runtime launcher-icon swapping.

## Definition of done
Each feature passes its PRD acceptance criteria + the release test checklist (§20).
The catalogue-driven cross-tenant leak test is a release gate and is never skipped.

## Build order
Follow PRD §17 milestones, one per session. The console (M3) and binding (M4) come
before the product surfaces. Simulated payments first, then live.
```

---

*Cray Salon © Crayora. v4 supersedes v3: business model corrected to sales-led with a setup fee,
Crayora-operated provisioning, per-salon white-labelling, and exclusive permanent customer
binding; all eleven v3 specification gaps closed. Pricing and per-message figures are proposals
to verify before launch.*
