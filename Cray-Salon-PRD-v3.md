> ## ⚠ SUPERSEDED — do not build from this document
>
> The current PRD is **`Cray-Salon-PRD-v4.md`**. This v3 is kept only as history.
>
> It predates two decisions that changed the product's shape:
>
> - **The business model.** v3 assumes owners self-onboard. They do not: Crayora sells and
>   provisions each salon from the super-admin console, and activation is a deliberate human
>   action (ARCHITECTURE ADR-17, ADR-26).
> - **The login order.** v3 authenticates first. The salon code now comes **before** login, so
>   the OTP can be sent from the salon's own Message Central account (ADR-28, ADR-32).
>
> Anything in here that contradicts v4, `RULES.md` or `ARCHITECTURE.md` is wrong by definition.

# Cray Salon — Complete PRD & Build Brief (v3, superseded)

**A multi-tenant SaaS retention platform for local salons — full feature set, built to be implemented by Claude Code**

| | |
|---|---|
| **Product** | Cray Salon |
| **Company** | Crayora |
| **Document type** | PRD + implementation brief for Claude Code |
| **Version** | 3.0 (complete feature set; gaps closed) |
| **Status** | Ready to build |
| **Platform** | Android (install-first), Flutter |
| **Prepared** | September 2026 |

> **What changed from v2:** added the full advanced-feature roadmap (push notifications, customer memberships/packages, gift cards, waitlist & queue, lifecycle automation, loyalty tiers, feedback/NPS, review routing, staff management & commission, photo gallery, GST invoicing, home service, deep analytics), added the **Crayora super-admin console**, and closed every open gap — subscription tiers, trial behaviour, offline handling, observability, rate limiting, backups, localization, and DPDP data-deletion.

---

## 0. How to build this with Claude Code

This document is written to be handed directly to **Claude Code** — Anthropic's agentic coding tool that reads your codebase, edits files, runs commands, and works across your whole project from the terminal, IDE, desktop app, or web. You (Jyotiranjan) direct; Claude Code writes the code; you review and steer.

**Access:** Claude Code runs with a Claude Pro/Max subscription or an Anthropic Console account. Install/sign-in steps change over time — follow the current official guide at `https://docs.claude.com/en/docs/claude-code/overview` rather than any memorised command.

**How to drive the build:**
1. Create the repo, add **`CLAUDE.md`** at the root (Appendix A). Claude Code reads it every session — it's how you stop the agent drifting off-stack.
2. Build in the **milestone order (§17)**, one milestone per session. Never ask for the whole app at once.
3. Feed it the relevant section as the spec: *"Implement the wallet ledger per §9.1 and §8.4; acceptance criteria are in that section."* Each feature has an **Acceptance criteria** block = definition of done.
4. Make it write the **cross-tenant leak test** (§7) — mandatory.
5. Use **MCP** to let Claude Code read this PRD from Google Drive/Notion, or update tickets as it works.

**The instruction to repeat constantly:** *every table has a `salon_id`, every query is tenant-scoped, RLS is enforced in the database — never write a query that can return another salon's data.*

---

## 1. What we are building

Cray Salon turns a local salon's one-time walk-in customers into repeat customers. It is **not a booking app** — it is a connected retention loop: record the customer → give a reason to return (prepaid credit + loyalty) → remind at the right time → raise the bill transparently (add-ons, packages) → earn referrals → show the owner what worked. It ships as **multi-tenant SaaS**: one codebase, one database, many salons, each fully isolated. **Any salon owner can install the app and set up their own salon end-to-end with zero help from Crayora** (§6 — a hard requirement).

**Core transformation:** walk-in → saved customer → prepaid balance → timely reminder → repeat booking → add-on/package sale → referral → measurable revenue.

---

## 2. Problem

Local salons have hidden revenue leaks: no customer record after a visit; no timely reminder; add-ons never shown at booking; no cheap acquisition channel; no simple view of what's working. Cray Salon closes all of these and layers on loyalty, packages, and lifecycle marketing.

---

## 3. Goals & success metrics

### Goals
1. Increase repeat-visit rate.
2. Increase average bill value (add-ons, packages, memberships).
3. Generate trackable referrals.
4. Give owners simple daily-decision numbers.
5. **Let any owner self-onboard with zero Crayora involvement.**
6. Keep per-salon messaging cost low by preferring free push over paid WhatsApp.

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
| NPS / CSAT | post-visit feedback score |

### Crayora business metrics
Self-serve activation rate; time-to-first-value; paying-salon retention (30/90d); MRR; churn; messaging cost per salon; push-vs-WhatsApp send ratio (higher push = better margin).

---

## 4. Users & roles

| Role | MVP? | Capabilities |
|---|---|---|
| **Customer** | ✅ | OTP login; wallet, bookings, offers, referral, packages, loyalty; one-tap booking; feedback |
| **Owner** | ✅ | Full salon management, dashboard, adjustments (audited), self-onboarding, billing |
| **Manager** | ✅ (role) | Owner capabilities minus billing/settings, per granular permissions |
| **Staff/Barber** | Phase 2 app | Own schedule; mark complete; add-on/bill updates; tips; commission view |
| **Crayora super-admin** | ✅ (internal) | Cross-tenant health, support, suspend/reactivate, billing status — **never sees customer PII beyond what support needs** |

Granular permissions are stored per user so owners can decide what managers/staff may do.

> **Critical dependency:** every automation triggers off "visit marked complete." MVP owner logs completions → mark-complete MUST be one tap on the day view, and must work offline (§15).

---

## 5. Feature roadmap (everything, tiered)

Keep the MVP lean; ship advanced features only after the loop proves itself.

### Tier 1 — MVP (the loop)
Zero-touch onboarding · OTP login · customer profiles + visit history · service catalogue · booking + slots · add-ons (never pre-selected) · salon-credit wallet ledger · service-based reminders · referral link/code + reward states · owner dashboard + cohort retention · owner adjustments with immutable audit · **push notifications (FCM)** · subscription/billing · multi-language (EN/HI/Hinglish) · offline mark-complete.

### Tier 2 — Phase 2 (deepen retention & revenue)
Customer **memberships & prepaid packages** · **loyalty points/tiers** · **waitlist & walk-in queue/token** · **lifecycle automation** (birthday, anniversary, win-back, lapsed) · **feedback/NPS + review routing** · **staff/barber app** + schedules + **commission** · **GST invoicing / digital receipts** · **photo gallery** (before/after, styles, with consent) · advanced analytics · manager/staff granular permissions · **home-service booking**.

### Tier 3 — Phase 3 (scale & network)
Multi-**branch** (one owner, many locations) · **gift cards** (closed-loop, legal review required) · inventory & retail product sales · dynamic/off-peak pricing · marketing campaign builder · **referral leaderboard** · Crayora-wide customer network features · white-label individual apps (premium tier) · AI hairstyle recommendations · WhatsApp two-way chatbot booking.

---

## 6. ⭐ Zero-touch self-serve onboarding (hard requirement)

**If Crayora ever has to touch a database or run a script to activate a salon, this requirement has FAILED.**

### Owner-facing flow
1. Download Cray Salon → tap **"Set up my salon."**
2. Phone → OTP → verify. Creates the **owner user**.
3. Salon basics: name, logo (→ Cloudflare R2), address, working hours, language.
4. **Backend auto-creates the tenant** — fresh `salon_id`; all future records scoped to it.
5. **Guided wizard** with sensible pre-filled defaults (owner mostly taps *Accept*):
   - 3–5 services (name/price/duration/cycle) — defaults offered.
   - Self (+ optional staff) as barbers.
   - Wallet bonus rule (default ₹500→+₹50).
   - Default reminder cycle (default 30d).
   - Preferred notification channel (push primary, WhatsApp opt-in).
6. On finish: auto-generate the salon's **QR code / customer join link**, land on a working dashboard (clearable sample data), start the **14-day free trial** clock.

### Non-negotiable rules
No human in the loop · sensible defaults everywhere · progressive (start with 3 services) · everything editable later · tenant provisioning + trial start in one step.

### Acceptance criteria
- [ ] New owner: Play Store → working dashboard (bookable service, wallet rule, shareable link) with **zero Crayora involvement**, under 10 minutes.
- [ ] New salon fully RLS-isolated from the moment the tenant is created.
- [ ] Two owners onboarding simultaneously get different `salon_id`s and cannot see each other's data.
- [ ] All onboarding values editable afterward.

---

## 7. Multi-tenancy (foundation — Day 1)

**Tenant** = one paying salon (Day 1). **Branch** = one owner, many locations (Phase 3). Keep separate.

**Approach:** shared database, shared schema, row-level — every table carries `salon_id`.

**Two required defenses:** (1) **Postgres RLS** policies so the DB itself refuses out-of-tenant rows even if app code has a bug; (2) a **tenant-scoped data-access layer** so no raw query reaches the DB unscoped.

**Resolution:** owner's `salon_id` on their `users` row, mirrored into the Supabase Auth JWT; RLS reads `auth.uid()` → `salon_id` → filters every table. A customer may belong to multiple salons (separate links); wallet/history/loyalty are per-salon.

```sql
alter table customers enable row level security;
create policy tenant_isolation_customers on customers
  using (salon_id = (auth.jwt() ->> 'salon_id')::uuid)
  with check (salon_id = (auth.jwt() ->> 'salon_id')::uuid);
```
> Generate an equivalent policy for **every** tenant table, and a test that logs in as Salon A and asserts **zero** Salon B rows returned.

---

## 8. Data model

### 8.1 SaaS / tenancy
- **`salons`** — id, name, logo_url, address, phone, working_hours jsonb, wallet_rule jsonb, reward_rule jsonb, loyalty_rule jsonb, default_reminder_cycle, cancellation_policy, gst_number?, languages text[], notification_prefs jsonb, status (active/suspended/trial), created_at.
- **`users`** — id (= Auth uid), salon_id, role (owner/manager/staff), permissions jsonb, name, phone, active.
- **`subscriptions`** — id, salon_id, plan, status (trialing/active/past_due/cancelled), trial_ends_at, renews_at, message_allowance, messages_used_this_cycle.
- **`platform_admins`** — Crayora super-admin accounts (separate from tenant users).

### 8.2 Core product (each has `salon_id`)
| Table | Fields |
|---|---|
| `customers` | name, phone, consent jsonb (per-purpose), birthday?, anniversary?, created_at, last_visit, loyalty_points, tier, language |
| `services` | name, category, price, duration, repeat_cycle_days, active, image_url? |
| `add_ons` | name, price, extra_duration, relevant_service_ids, active, staff_availability |
| `staff` | name, working_hours jsonb, skills text[], commission_rule jsonb, active |
| `bookings` | customer_id, service_ids, addon_ids, staff_id, datetime, status, total, source (walk-in/app/reminder/referral/waitlist) |
| `visits` | booking_id, completed_services, final_amount, payment_status, tip, completed_at |
| `wallet_transactions` | customer_id, paid_credit, bonus_credit, debit, refund, reason, source, balance_after, created_at |
| `referrals` | referrer_id, referred_customer_id, code, status, reward, completed_visit_id |
| `reminders` | customer_id, service_id, type (service_due/birthday/winback/…), scheduled_time, channel, delivery_status, booking_created |

### 8.3 Advanced-feature tables (Phase 2/3; each has `salon_id`)
| Table | Purpose |
|---|---|
| `packages` | prepaid service bundles / memberships: name, included_services, quantity or unlimited, price, validity_days, active |
| `customer_packages` | customer_id, package_id, remaining, expires_at, status |
| `loyalty_ledger` | append-only points earn/redeem entries, reason, balance_after |
| `waitlist` | customer_id, service_id, requested_window, status, notified_at |
| `feedback` | visit_id, customer_id, rating, nps, comment, routed_to_review bool |
| `invoices` | visit_id, gst_breakup jsonb, invoice_no, pdf_url |
| `photos` | customer_id?, staff_id?, before_url, after_url, consent bool, tags |
| `gift_cards` | code, purchaser_phone, recipient_phone, value, redeemed, status *(legal review — closed-loop, non-cash)* |
| `campaigns` | owner-built segment + message + schedule (Phase 3) |
| `audit_log` | actor_user_id, action, entity, before/after jsonb, created_at |
| `notification_tokens` | customer/user device FCM tokens for push |

### 8.4 Status enums (never delete — use statuses)
Booking: Pending/Confirmed/Completed/Cancelled/No-show · Referral: Invited/Registered/Pending visit/Rewarded/Rejected · Wallet: Payment pending/Credited/Debited/Refunded/Reversed · Reminder: Scheduled/Sent/Delivered/Failed/Converted/Opted out · Package: Active/Exhausted/Expired · Subscription: Trialing/Active/Past due/Cancelled.

### 8.5 Ledger integrity (wallet + loyalty)
Append-only; refunds/reversals are new rows, never edits/deletes; paid vs bonus stored separately; balance changes only on confirmed payment or reasoned owner adjustment; **store credit and loyalty points are non-withdrawable as cash** (keeps the product outside RBI PPI licensing — closed-loop).

---

## 9. Core feature specs (Tier 1)

Each has **Acceptance criteria** = definition of done.

### 9.1 My Salon Wallet
Store-credit ledger (not cash), non-withdrawable. Customer sees credit, name+mobile, last visit/service, Add Money, Use at Checkout, history, Book Next Visit, offer + terms. Example: ₹500 → +₹50 → ₹550. Bonus/min-top-up/expiry configurable; paid vs bonus separate; refund = new ledger entry; expiry rule shown before payment.
**AC:** [ ] top-up creates two rows (paid+bonus) + updates balance_after · [ ] history immutable · [ ] no balance change without confirmed payment/reasoned adjustment · [ ] no cash withdrawal path anywhere.

### 9.2 Smart Reminder & Quick Booking
Expected service-due reminder, not spam. Customer sees last service, suggested date, slots, preferred barber, Book Now, reschedule/cancel, permission toggle. Cycles owner-editable (Haircut 25–35d, Beard 10–15d, Colour 25–45d, Facial 30–45d). **Enhancement:** after 2+ visits, learn the customer's actual interval. Prefer **push** (free); WhatsApp only if push undeliverable or customer opted into WhatsApp.
**AC:** [ ] mark-complete schedules exactly one reminder · [ ] booking stops duplicate reminders for that cycle · [ ] opt-out honoured · [ ] push tried before paid WhatsApp.

### 9.3 Booking Add-ons
Relevant, transparent add-ons at booking time. Never pre-selected; total+duration update instantly; only relevant suggestions; owner can toggle/price/limit by staff; unavailable items disappear.
**AC:** [ ] nothing checked by default · [ ] instant total/duration update · [ ] only relevant add-ons shown.

### 9.4 Refer & Earn
Unique link/code; WhatsApp share; pending/successful; earned reward; clear rules. Reward stays Pending until friend completes a **paid** first visit. No self-referral; one referrer per new customer; cancelled/refunded don't qualify; owner monthly cap.
**AC:** [ ] reward releases only after paid completed first visit · [ ] cancelled/refunded releases nothing · [ ] self-referral rejected.

### 9.5 Owner Dashboard
Cards: today's revenue, today's bookings, avg bill, repeat/new this month, wallet collected, outstanding credit, reminder-generated bookings. Plus barber revenue, top-20 customers, due-for-visit, popular services/add-ons, referrals, cancelled/missed, wallet adjustments/refunds. One-tap: add customer, walk-in booking, **mark complete**, send reminder, adjust wallet (reason mandatory), refund/cancel, export. **Cohort retention view** (30/60/90-day return %, wallet vs non-wallet) ships in MVP.
**AC:** [ ] card totals match completed transactions exactly · [ ] mark-complete one tap from day view · [ ] wallet adjustment impossible without reason.

---

## 10. Advanced features (Tier 2/3 specs)

### 10.1 Push notifications (Tier 1 infra, powers everything)
**FCM (Firebase Cloud Messaging)** for Android push — free, native, install-first's biggest advantage. Push is the **primary** channel for booking confirmations, reminders, wallet receipts, referral news; WhatsApp/SMS are fallback (push undeliverable) or explicit marketing opt-in. This directly lowers per-salon messaging cost. Store device tokens in `notification_tokens`; send from Edge Functions.
**AC:** [ ] push delivered for confirmations/reminders/receipts · [ ] WhatsApp only when push fails or opted-in · [ ] token refresh handled.

### 10.2 Memberships & prepaid packages (Tier 2)
Owner defines bundles ("4 haircuts / month", "unlimited beard trim / ₹999") stored in `packages`. Customer buys → `customer_packages` tracks remaining/expiry. At checkout, package auto-applies before wallet/UPI. Big lever for locked-in repeat revenue.
**AC:** [ ] package decrements on redemption · [ ] expiry enforced · [ ] checkout applies package → wallet → UPI in order.

### 10.3 Loyalty points & tiers (Tier 2)
Earn points per ₹ spent (append-only `loyalty_ledger`); tiers (Silver/Gold/…) unlock perks (bonus %, priority slots). Non-withdrawable. Owner configures earn rate + tier thresholds.
**AC:** [ ] points immutable ledger · [ ] tier recalculated on spend · [ ] redemption creates debit entry, never cash-out.

### 10.4 Waitlist & walk-in queue (Tier 2)
When a slot is full, customer joins `waitlist`; auto-notify (push) on opening. In-salon **token/queue** for walk-ins with live "your turn in ~N mins".
**AC:** [ ] waitlist notifies on cancellation/opening · [ ] queue token updates live.

### 10.5 Lifecycle automation (Tier 2)
Automated, permissioned messages: **birthday** offer, **anniversary** (first-visit date), **win-back** for lapsed customers (no visit in 2× their cycle), **package-expiry** nudge, **post-visit thank-you + feedback**. All respect consent + opt-out, prefer push.
**AC:** [ ] each trigger fires once per event · [ ] all respect opt-out · [ ] lapsed detection uses per-customer cycle.

### 10.6 Feedback / NPS + review routing (Tier 2)
Post-visit push asks for a rating. High rating → prompt to leave a Google/Play review (deep link). Low rating → private feedback to owner (service recovery, not public). Stored in `feedback`.
**AC:** [ ] rating captured post-visit · [ ] happy → public review prompt, unhappy → private owner alert · [ ] never auto-posts on behalf of customer.

### 10.7 Staff/barber app + commission (Tier 2)
Separate lightweight app/view: own schedule, assigned bookings, one-tap mark-complete, tips, commission earned. Owner sets `commission_rule` (flat/%/per-service). Solves the MVP capture bottleneck by putting mark-complete in the barber's hand.
**AC:** [ ] staff sees only own schedule (RLS + role) · [ ] commission computed from completed visits · [ ] mark-complete syncs to owner dashboard.

### 10.8 GST invoicing / digital receipts (Tier 2)
Generate GST-compliant invoices (`invoices`, PDF → R2) when the salon has a GST number; plain receipts otherwise. Sent via push/WhatsApp.
**AC:** [ ] correct GST breakup when gst_number set · [ ] sequential invoice numbers · [ ] PDF stored + linked.

### 10.9 Photo gallery (Tier 2)
Before/after and style photos in `photos`, **explicit consent required**, stored in R2 with signed URLs. Owner showcases work; customer keeps a visual history.
**AC:** [ ] no photo stored/shown without consent flag · [ ] private via signed URLs · [ ] customer can delete their photos.

### 10.10 Home-service booking (Tier 2)
Toggle services as home-eligible; capture address + travel fee; route to available staff. Reuses booking flow with a location field.

### 10.11 Gift cards (Tier 3 — legal review first)
Closed-loop, salon-specific, **non-cash, non-refundable-to-cash** store credit gifted to another phone number. ⚠️ Third-party-purchased redeemable value edges toward semi-closed PPI territory — **legal review required before launch**; keep strictly closed-loop.

### 10.12 Campaign builder & referral leaderboard (Tier 3)
Owner builds a segment (e.g. "lapsed colour customers"), composes a message, schedules a send (respecting consent/allowance). Referral leaderboard gamifies top referrers.

### 10.13 Dynamic / off-peak pricing (Tier 3)
Owner sets discounted off-peak slots to fill quiet hours; shown transparently at booking.

### 10.14 WhatsApp two-way booking chatbot (Tier 3)
Via Message Central BSP — customers book by replying in WhatsApp; bot writes into the same bookings table.

---

## 11. Crayora super-admin console (internal, MVP-light)

A separate, secured surface (web) for Crayora — **not** a tenant. Purpose: run the SaaS without touching the DB.
- **Salon health:** list of tenants, status, plan, last-active, activation stage.
- **Support mode:** view a salon's operational state to help (scoped; log every access to `audit_log`; minimise customer PII exposure).
- **Billing:** subscription status, trial/past-due, manual comp/extend.
- **Suspend / reactivate** a tenant (e.g. non-payment) without deleting data.
- **Platform metrics:** MRR, churn, activation rate, push-vs-WhatsApp ratio, messaging cost.
- **Feature flags:** roll advanced features to selected salons.
**AC:** [ ] super-admin cannot be reached via tenant auth · [ ] every super-admin data access is audit-logged · [ ] suspend disables tenant access but retains data.

---

## 12. Messaging & notification strategy

**Channel priority (protects margin):** Push (FCM, free) → WhatsApp (Message Central BSP, paid, opt-in) → SMS (Message Central, DLT, fallback). OTP always via Message Central.

- **OTP:** VerifyNow; no DLT needed for OTP → fast go-live. **Rate-limit OTP requests** (per phone + per IP) to prevent abuse/cost.
- **Utility** (booking/wallet/receipt): push first; WhatsApp utility (~₹0.145) as fallback.
- **Marketing** (reminders, lifecycle, campaigns): push first; WhatsApp marketing (~₹1.09, Meta pass-through, approx — verify current rates) only with opt-in.
- **Compliance (launch blockers):** Meta template pre-approval; DLT registration for SMS; withdrawable opt-in (also DPDP).

**Templates:**
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
```

---

## 13. Automations (Edge Functions)

| # | Trigger | Actions |
|---|---|---|
| A | Visit completed | update last-visit; add to history; compute next visit; schedule reminder; award loyalty points; decrement package; update staff commission + revenue metrics |
| B | Wallet top-up confirmed (Razorpay webhook) | record paid + bonus separately; recalc balance; send receipt |
| C | Booking confirmed | reserve slot; notify (push); stop duplicate reminder |
| D | Referral visit completed | validate; credit both rewards; notify both |
| E | Daily owner summary | revenue; completed/missed; new vs repeat; add-on + package revenue; wallet collected/used; tomorrow's count |
| F | Lifecycle scan (scheduled) | birthday/anniversary/win-back/package-expiry triggers |
| G | Waitlist opening | notify next waitlisted customer |
| H | Post-visit feedback | send rating request; route review vs private alert |
| I | Subscription lifecycle | trial-ending nudge; past-due dunning; suspend on non-payment |

---

## 14. Payments & billing

### Customer payments (Razorpay)
UPI/cards; explicit pending/failed/refunded states; **partial payment** (package → wallet → UPI); refund-to-source vs refund-to-wallet is an explicit logged choice; reconcile settlements against the ledger; never store raw credentials (tokenised).

### Crayora subscription billing (**gap closed — starting proposal**)
> These numbers are a proposal to validate in the pilot, **not** fixed. Verify Razorpay/Message Central costs before locking.

| Plan | Price (proposed) | Included | Messaging |
|---|---|---|---|
| **Starter** | ₹0 trial → ₹399/mo | 1 salon, core loop, push unlimited | 200 WhatsApp msgs/mo, then pass-through |
| **Growth** | ₹799/mo | + packages, loyalty, lifecycle, feedback | 750 WhatsApp msgs/mo |
| **Pro** | ₹1,499/mo | + staff app, commission, GST invoicing, campaigns, home-service | 2,000 WhatsApp msgs/mo |

- **Free trial:** 14 days, full Growth features, no card required.
- **Trial end:** → grace/read-only for 7 days (owner can view but not send/adjust) → suspended (data retained 90 days) → deleted after retention window with notice.
- **Overage:** WhatsApp beyond allowance billed pass-through (push stays free — nudges owners to prefer push).
- **Dunning:** Automation I sends reminders on past-due before suspend.

---

## 15. Non-functional requirements (gaps closed)

**Offline handling:** cache read data locally; **queue owner write-actions offline** (esp. mark-complete, walk-in booking) and sync on reconnect with conflict handling — salons often have patchy internet, and the loop dies if capture requires connectivity.

**Observability:** crash reporting (e.g. Sentry) in the Flutter app; structured logs + error alerts in Edge Functions; super-admin platform health (§11). Track push/WhatsApp delivery rates.

**Rate limiting & abuse:** OTP request limits (per phone + IP); referral-abuse caps; wallet-adjustment audit.

**Backups & recovery:** Supabase point-in-time recovery enabled; documented restore procedure; R2 versioning for critical assets.

**Localization (i18n from Day 1):** English + Hindi + Hinglish, architecture ready for regional languages (Odia, Telugu, Tamil, etc.); per-salon and per-customer language; all templates localizable. India-first, so this isn't optional polish.

**Accessibility:** large tap targets, high contrast, readable type, screen-reader labels.

**Performance:** dashboard cards load fast (pre-aggregated where needed); pagination on customer/booking lists; image compression for photos.

---

## 16. Security & compliance (gaps closed)

- **Isolation:** RLS on every table; scoped data layer; mandatory cross-tenant leak test.
- **Secrets:** Message Central, Razorpay, R2, FCM keys server-side only — never in the APK.
- **Financial integrity:** immutable ledgers; reversals not deletes; audit_log for every owner/admin adjustment.
- **DPDP Act (India):**
  - Per-purpose, withdrawable **consent ledger** (booking vs promotional vs photos) — not a single boolean.
  - Promotional consent separate from DLT/WhatsApp opt-in — capture both.
  - **Data-export** (customer can get their data) and **data-deletion request** flow (right to erasure, honoured within the ledger-integrity constraints — anonymise rather than break financial records).
  - Opt-out everywhere promo appears.
- **PPI avoidance:** wallet, loyalty, gift cards strictly closed-loop, non-cash.
- **Payment security:** Razorpay tokenisation; webhook signature verification.

---

## 17. Build milestones (one per Claude Code session)

| M | Milestone |
|---|---|
| **0** | Repo + `CLAUDE.md` + Flutter + Supabase + FCM wired; i18n scaffold |
| **1** | Full schema (§8) + RLS (§7) + **cross-tenant leak test** |
| **2** | Auth: Supabase phone-OTP via Message Central; OTP rate-limiting; owner + customer login |
| **3** | ⭐ Zero-touch onboarding (§6) — provisions tenant, no human in loop |
| **4** | Services, add-ons, staff, customer profiles, visit history, offline cache |
| **5** | Booking + slots + add-ons; offline queue for owner actions |
| **6** | Wallet ledger + Razorpay (simulated → live) + Automation B + push receipts |
| **7** | Reminders (push-first) + Automations A, C + learned-interval enhancement |
| **8** | Refer & Earn + Automation D |
| **9** | Owner dashboard + cohort view + Automation E |
| **10** | Subscriptions/billing + trial/dunning (Automation I) |
| **11** | Crayora super-admin console (§11) |
| **12** | Consent ledger, DPDP export/delete, opt-out, observability (Sentry), backups |
| **13** | Release states (empty/loading/error), test checklist (§20), Play Store build |
| **14+** | Tier 2: packages/memberships, loyalty, waitlist/queue, lifecycle, feedback/NPS, staff app + commission, GST invoicing, photo gallery, home-service |
| **15+** | Tier 3: multi-branch, gift cards (post legal review), inventory, campaigns, dynamic pricing, WhatsApp chatbot |

> Ship M0–M9 with **simulated payments** = the working prototype; wire real Razorpay + Message Central templates + DLT before public release.

---

## 18. 30-day pilot
Baseline first (avg bill, repeat gap, weekly customers, no-shows, referral method). W1 setup + train owner on one workflow. W2 wallet + reminders, daily payment/refund/balance checks. W3 add-ons + referrals for completed customers. W4 compare vs baseline. Continue only with features that produced real usage or saved owner time.

## 19. Owner discovery checklist
Ten common services + prices + durations · repeat services + cycles · how customers book today · barbers per shift · main cancellation cause · two best-margin add-ons · safe wallet amount + bonus · when referral reward becomes valid · which daily numbers the owner wants · who marks services complete · GST registered? · preferred languages.

## 20. Release test checklist
- [ ] Cross-tenant isolation (automated) · duplicate booking / full slot · failed payment + refund · expired credit shown before payment · self-referral rejected · cancelled referral releases nothing · reminder opt-out honoured · dashboard totals match transactions · owner runs daily workflow unaided · **zero-touch onboarding needs no Crayora action** · push delivered, WhatsApp fallback only when needed · offline mark-complete syncs · OTP rate-limited · Meta templates approved + DLT registered · **no secret keys in the build** · DPDP export/delete works · super-admin access audit-logged.

## 21. Risks & remaining open questions

| Risk | Mitigation |
|---|---|
| Manual visit-completion capture (MVP) | one-tap offline mark-complete; ship staff app (Tier 2) to move it to the barber |
| Install-first loses walk-ins | owner sets customer up + hands Play Store link in the chair; push keeps installed users engaged |
| Messaging cost erodes margin | push-first channel strategy; allowances + pass-through overage |
| Meta approval / DLT on critical path | draft + submit early |
| Gift-card PPI exposure | legal review before launch; strictly closed-loop, non-cash |
| Tenant-isolation bug | RLS + scoped layer + mandatory leak test |
| Feature bloat delaying launch | strict tiering — ship Tier 1 loop first |

**Open (business decisions, not blockers):** final subscription prices (validate in pilot); trademark/domain/Play-Store check for "Cray Salon"; regional-language launch order; whether to build the staff app in Tier 2a vs 2b.

---

## Appendix A — `CLAUDE.md` (paste into project root)

```markdown
# Cray Salon — Project Context for Claude Code

## What this is
Multi-tenant SaaS Android app for local salons. One codebase, one database,
many salons, fully isolated. Retention loop: wallet, reminders, add-ons,
packages, loyalty, referrals, owner dashboard. Owners self-onboard with zero
Crayora involvement.

## Stack (do not substitute without asking)
- App: Flutter / Dart (install-first Android; Play Store)
- Auth: Supabase Auth (phone OTP; free to 50K MAU)
- OTP delivery: Message Central (from Edge Functions only)
- DB + isolation: Supabase Postgres + Row-Level Security (RLS)
- Files: Cloudflare R2 (logos/photos/invoices) — signed URLs for private files
- Serverless + all messaging/payment calls: Supabase Edge Functions
- Payments: Razorpay (UPI/cards, webhooks, refunds)
- Messaging: Message Central (SMS + WhatsApp BSP + OTP)
- Push: Firebase Cloud Messaging (FCM) — primary channel, WhatsApp is fallback
- Crash reporting: Sentry
- i18n: English / Hindi / Hinglish from day one; architecture ready for regional

## Non-negotiable rules
1. Every table has `salon_id`. Every query tenant-scoped. RLS enforced in DB.
   NEVER write a query that can return another salon's data.
2. Secrets (Message Central, Razorpay, R2, FCM) live server-side only.
3. Call Message Central and Razorpay only from Edge Functions.
4. wallet_transactions and loyalty_ledger are append-only. Refunds/reversals are
   new rows, never edits/deletes.
5. Store credit, loyalty points, gift cards are non-withdrawable as cash (closed-loop).
6. Add-ons are never pre-selected.
7. Referral rewards release only after a completed PAID first visit.
8. Onboarding is zero-touch: finishing the wizard fully provisions a working,
   isolated tenant with no human approval.
9. Prefer push (free) over WhatsApp (paid) for every notification.
10. Owner write-actions (esp. mark-complete) must work offline and sync.
11. Consent is per-purpose and withdrawable (DPDP); support data export + delete.

## Definition of done
Each feature passes its PRD Acceptance criteria + the release test checklist (§20).
A cross-tenant data-leak test is mandatory.

## Build order
Follow PRD §17 milestones, one per session. Simulated payments first, then live.
Ship the Tier 1 loop before any Tier 2/3 feature.
```

---

*Cray Salon © Crayora. Feature depth adapted from the Roy Digital Salon App Blueprint v1.0; advanced features, multi-tenancy, zero-touch onboarding, super-admin, stack, and build-brief structure defined in product planning. Claude Code and messaging-provider details verified against sources, September 2026. Pricing and per-message figures are proposals/approximations to verify before launch.*
