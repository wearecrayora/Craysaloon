# Cray Salon — regulatory position

**Written for: Jyotiranjan (Crayora), and whoever you hand this to for legal or CA review.**

This is an engineering assessment of what the system does against what the law requires. It is
not legal advice, and two things in it need a professional's signature rather than mine: the
**retention periods** under tax and company law, and the **contracts** between Crayora, each
salon, and our sub-processors. Everything else is mechanical, and where it is mechanical it is
either built and tested, or listed below as a gap with the milestone that closes it.

Last reviewed: **28 September 2026**, against the DPDP Rules as notified on 14 November 2025.

---

## 1. Who is who — this decides everything else

| Party | Role under DPDP | Why |
|---|---|---|
| **The salon** | **Data Fiduciary** | It decides the purpose: it runs the salon, holds the customer relationship, sends the reminders, keeps the money |
| **Crayora** | **Data Processor** | It processes on the salon's instructions. It sells software; it does not decide why a customer's number is held |
| **The customer** | Data Principal | |
| Supabase, Cloudflare R2, Razorpay, Message Central, Sentry, Google (FCM) | Sub-processors | Engaged by Crayora, used on the salon's behalf |

This is already stated in `RULES.md` 11.7 and the app is built around it: the grievance contact a
customer sees must be **the salon's**, not only Crayora's.

**The consequence people get wrong:** the penalties under the Act (up to ₹250 crore for a security
failure) land on the **Data Fiduciary** — the salon. Crayora's exposure is contractual and
reputational, and its obligation is to give every salon a product that lets them comply. That is
the standard this document measures against.

---

## 2. The clock

The DPDP Rules, 2025 were notified on **14 November 2025** with phased commencement. The
substantive operating obligations — notice, consent, data-principal rights, breach reporting,
security safeguards — become enforceable at the end of the **18-month** window, i.e. around
**13 May 2027**. Some provisions (the Board's constitution, definitions) took effect immediately.

We are therefore inside the runway, not past a deadline — but the runway ends before this product
will have any meaningful number of salons on it, so nothing below should be treated as "later".

---

## 3. DPDP Act 2023 + Rules 2025 — obligation by obligation

Legend: **Built** = implemented and covered by a CI gate · **Partial** = mechanism exists, surface
missing · **Gap** = not built · **Decision** = needs a business/legal answer, not code.

### 3.1 Notice and consent (ss. 5, 6)

| Requirement | Status | Where |
|---|---|---|
| Consent is free, specific, informed, unambiguous, by clear affirmative action | **Built** | Marketing consent is opt-in and starts **unticked**; `join_flow_test`, `bind_flow_test` assert defaults at binding |
| Consent limited to the purpose stated | **Built** | Purposes are separate rows: `service_communication`, `promotional`, `whatsapp`, `photos` |
| **Itemised notice before/with the consent request** — what data, what purpose, how to withdraw, how to complain to the Board | **Gap** | The app shows a one-line service note and two tick-boxes. There is no itemised notice. **This is the single largest compliance gap in the product.** Closing it: §7 item 1 |
| Notice available in English or any Eighth Schedule language, at the principal's option | **Built** | `en` / `hi` / `hi_Latn` from day one; Hindi is Eighth Schedule. The notice text (once written) must ship in all three |
| **Withdrawal as easy as giving** (s.6(4)) | **Built (server)** / **Gap (screen)** | `public.set_consent` + `public.my_consents` (migration 0051), gated by `privacy/data_rights_test.sql`. The customer-facing screen is §7 item 2 |
| Consent ledger, not a boolean — history survives | **Built** | Append-only `consents`; withdrawal is a new row; the gate asserts the original row is still readable afterwards |
| Processing stops within a reasonable time of withdrawal | **Partial** | The state flips immediately; the messaging ladder that must read it arrives at M8 and will read `my_consents` |

A note on `service_communication`: it is granted at binding without a separate tick, on the basis
that booking confirmations and payment receipts **are the service the customer asked for**
(s.7(a) — voluntarily provided for that purpose). Marketing is never treated this way. If counsel
disagrees, the fix is small: add it as a fourth tick at binding.

### 3.2 Rights of the Data Principal (ss. 11–14)

| Right | Status | Where |
|---|---|---|
| **Access** — a copy of their data | **Built** | `request_data_right('access')` raises a tracked request with a 30-day due date; the console produces the copy by request id (`access_request_export`, 0091) and closes it with how it reached the person, which the customer sees. Gated in `data_rights_test` |
| **Correction** | **Partial** | A customer can edit their own profile (0041 own-rows writes). No dedicated screen yet |
| **Erasure** | **Built** | `app_admin.anonymise_customer` (0051): name, number, birthday and the login link go; the salted hash and every financial row stay. Gated |
| **Grievance redressal** | **Built (channel)** / **Decision (who answers)** | `request_data_right('grievance')`. The salon must name a contact — see §6 |
| **Nomination** (s.14) | **Gap** | Nobody can nominate someone to exercise their rights if they die or are incapacitated. Low volume, real obligation. §7 item 5 |
| Requests are answered, and a refusal is explained | **Built** | Every request carries `status` + `outcome`; erasure writes its outcome sentence automatically |

### 3.3 Children (s. 9)

| Requirement | Status | Notes |
|---|---|---|
| No account for under-18s without verifiable parental consent | **Built (by design)** | `RULES.md` 4.8: accounts are for the phone holder, who must be an adult |
| No tracking or targeted advertising directed at children | **Built (by absence)** | There is no behavioural tracking or ad targeting anywhere in the product |
| **A child's details kept as a note on an adult's record** | **Flag** | This is still a child's personal data, processed by the salon. A stylist writing "Aarav, 6, short back and sides" is processing under s.9. See §7 item 6 |

### 3.4 Security safeguards (s. 8(5), Rules)

| Safeguard | Status | Evidence |
|---|---|---|
| Access control | **Built** | Row-level security, enabled **and forced**, on every tenant table; the customer-scope and write-scope gates prove one customer cannot read or write another's data, and that a stylist cannot promote themselves |
| Encryption at rest / in transit | **Built** | Supabase (AES-256 at rest, TLS in transit); credentials in Vault; phone numbers stored as a **peppered HMAC** with the pepper outside the table |
| Secrets never readable back | **Built** | Exactly **one** function in the schema reads a decrypted credential; asserted by gate, with the pepper reader named alongside it |
| Logging and monitoring | **Partial** | `audit_log` covers every admin action; Sentry covers crashes with PII scrubbed (`sendDefaultPii = false` plus explicit scrubbers). **No access logging of ordinary reads** — see CERT-In in §4 |
| Data backup | **Assumed** | Supabase's automated backups. Retention and restore have never been tested. §7 item 8 |
| Breach detection and response | **Gap** | §7 item 3 |

### 3.5 Breach notification (s. 8(6), Rules 2025)

**Nothing exists for this today.** The obligation on becoming aware of a personal data breach:

1. notify **each affected Data Principal** without delay, in plain language: what happened, what
   data, what they can do, and whom to contact;
2. notify the **Data Protection Board** without delay, and a fuller report within **72 hours** —
   facts, circumstances, mitigation taken, and findings about who caused it.

Separately, CERT-In's 6-hour rule (§4) may apply to the same incident, on a much shorter clock.

This is **the most serious gap in the list**, because it is the one where being unprepared turns a
contained incident into a regulatory failure. §7 item 3.

### 3.6 Processors and contracts (s. 8(2))

| Requirement | Status |
|---|---|
| A Fiduciary may engage a Processor **only under a valid contract** | **Decision** — each salon needs a signed agreement appointing Crayora as Processor. There is no template in this repo |
| Crayora's own sub-processors must be under equivalent terms, with a published list | **Decision** — §6 |

### 3.7 Cross-border (s. 16)

| Where data lives | Status |
|---|---|
| **Database, auth, Edge Functions** — Supabase, `ap-south-1` (Mumbai) | **In India** ✓ |
| **Payments** — Razorpay | India ✓ |
| **OTP/SMS** — Message Central | India ✓ |
| **Files (QR packs, later logos/photos/invoices)** — Cloudflare R2, region `auto` | **Flag** — `auto` means Cloudflare chooses; the objects may sit outside India. Fixable at bucket creation with a location hint. §7 item 7 |
| **Crash reports** — Sentry | **Flag** — likely US/EU. PII is scrubbed, so the exposure is low, but it is a transfer and should be named in the notice and the sub-processor list |
| **Push** — Firebase Cloud Messaging | Global. Tokens only |

s.16 permits transfer except to countries the government restricts (none notified as of this
review). The work is disclosure and contracts, not blocking.

### 3.8 Significant Data Fiduciary

Unlikely to apply — SDF status is by government notification based on volume and sensitivity. If
any single salon or Crayora is ever notified, the extra obligations are a DPIA, an annual audit, an
India-resident Data Protection Officer and algorithmic due diligence. Worth re-checking yearly, not
now.

---

## 4. Other law that applies to this product

### CERT-In Directions, 2022 — **in force, and the shortest clock in this document**

| Requirement | Status |
|---|---|
| Report listed cyber incidents to CERT-In within **6 hours** of becoming aware | **Gap** — no process, no named person. §7 item 3 |
| Enable ICT logs, retain **180 days**, **within Indian jurisdiction** | **Partial** — Postgres and Edge Function logs are in `ap-south-1`; retention is Supabase's default, not 180 days by policy, and **Sentry's copy sits outside India** |
| Clocks synchronised to NIC/NPL NTP | **Assumed** (managed infrastructure) |

### RBI — why this wallet is not a PPI requiring authorisation

The wallet is a **closed-system** instrument: credit is issued by a salon, redeemable **only at
that salon**, with **no cash-out and no refund to bank**. Those properties are enforced in the
schema and gated — a transfer between salons moves the binding and explicitly **not** the money.
Keep it that way: making credit spendable at another salon, or refundable to a bank account, would
turn it into a semi-closed PPI and require RBI authorisation. `RULES.md` §2 already lists both as
capabilities that deliberately do not exist.

### Payment aggregator rules

Customer money settles into **the salon's own Razorpay account**. Crayora never holds funds, so it
is not acting as a payment aggregator. This is enforced in code: there is no platform Razorpay
account to fall back on, and a salon without its own keys simply cannot take top-ups.

### Consumer Protection Act 2019 + the CCPA dark-pattern guidelines (2023)

| Pattern | Our position |
|---|---|
| Basket sneaking | **Add-ons are never pre-selected** — a rule, and a test |
| Drip pricing | The quote states the bonus, its expiry and that top-ups are non-refundable **before** payment |
| Subscription trap | No consumer subscription exists |
| Forced action | Marketing consent is not required to use the app |
| Confirm-shaming | No such copy; the app says "Not now", not "No, I don't want offers" |

### TRAI / TCCCPA and the Telecommunications Act, 2023

OTPs go out under Message Central's own DLT-registered header, so no DLT registration is needed by
us. **Promotional** SMS is different: unsolicited commercial communication is regulated, and
consent has to be demonstrable and scrubbed against preferences. We hold per-purpose consent with
timestamps, which is the evidence side. **Decision:** confirm with Message Central who is the
registered Principal Entity for promotional traffic and whether their scrubbing covers us. Until
that is answered, prefer push and WhatsApp (which carry their own opt-in rules and we honour them).

### GST, Companies Act, books of account

Invoices, payments and ledgers are retained in anonymised form for the statutory period rather than
deleted. **The exact period needs a CA's answer** — it is already flagged in `ARCHITECTURE.md` §13.

### Google Play

A Data Safety declaration and a published privacy policy URL are required before the app can ship.
Neither exists yet. §7 item 9.

---

## 5. What changed today

Built and gated this session (migrations 0051–0052, `privacy/data_rights_test.sql`, 22 assertions):

- **Consent withdrawal by the customer themselves**, appended to the ledger, with the original
  consent still readable afterwards.
- **A salon cannot tick a consent box for a customer** — asserted; consent someone else gave is
  not consent.
- **Access, erasure and grievance requests**, raised against the salon with a 30-day due date and
  an outcome that must be filled in.
- **Erasure as anonymisation**: name, number, birthday and login link removed; the salted hash and
  every financial row retained, so the books survive and one-phone-one-salon stays enforceable.
- A bug the gate caught immediately: "latest consent wins" tied when two changes landed in the same
  transaction, and the tie resolved **in favour of still-consented** — the worst available answer.
  Fixed with a monotonic tiebreak (0052).

---

## 6. Decisions taken, 28 September 2026

These were open questions. They are answered now, and the answers are binding on the code — where
one has a mechanism, the mechanism is named.

| # | Question | Decision | Where it lives |
|---|---|---|---|
| 1 | Who is the grievance contact per salon? | **The salon answers; Crayora escalates.** A named person plus at least one reachable channel, captured before activation | `salons.grievance_name/email/phone`, `app_admin.set_grievance_contact` (0053); `activate_salon` **refuses** without one; published pre-login by `resolve_join_code` (0055); console page at `/salon/[id]/privacy` |
| 2 | Crayora's own contact, and a DPO? | **A named person, no DPO title.** We are not a Significant Data Fiduciary and inventing the title would claim a status we do not hold | Privacy policy, contact block |
| 3 | A published privacy policy | **Written**: `join/public/privacy.html`, served at `join.craysalon.in/privacy` | Linked from `/`, `/s/<code>`, the in-app notice and the Play listing. Placeholders + lawyer review are the two open items — see `join/README.md` |
| 4 | Retention of financial records | **8 years** from the end of the financial year, **to be confirmed with a CA**. Applied as the stated period now, so the promise and the behaviour match | Privacy policy. The offboarding purge (0089) removes personal data and keeps these records, anonymised. Deleting them when the period ends is not built - no record is old enough yet |
| 5 | Contracts | **Data-processing terms inside the salon agreement**, plus a published sub-processor list | Sub-processor table is in the privacy policy; the salon agreement is a lawyer's document |
| 6 | Message Central's DLT position for promotional SMS | **No promotional SMS until Message Central confirms in writing** that its registration covers salon marketing content. Transactional/service SMS and the OTP are unaffected — those go under Message Central's own registration | New entry in `RULES.md` §2: promotional SMS is a capability that deliberately does not exist yet |
| 7 | Sentry region, and file location | **Pin files to India/Asia-Pacific, keep Sentry where it is, and disclose both.** Crash reports are technical, not customer records; moving them would buy little and cost a working error pipeline | Privacy policy names both, and says plainly which two sub-processors are outside India. R2 bucket location is a deployment instruction, still open (work queue #7) |

**What decision 6 means in practice:** we can send an OTP and a booking confirmation today. We
cannot send "20% off this Friday" by SMS until that confirmation exists. Push notification and
WhatsApp are unaffected — and push is the preferred channel anyway (RULES 12).

---

## 7. The work queue, in priority order

| # | Item | Why it ranks here | Milestone |
|---|---|---|---|
| 1 | ~~**Itemised consent notice** in the join flow~~ | **Done.** `ConsentNotice`, shown above the number field on U4 and again on "Your data", in `en`/`hi`/`hi_Latn`. Carries the salon's own privacy contact | Done |
| 2 | ~~**"Your data" screen**~~ | **Done.** `/your-data`, one tap from the customer's home. 13 widget tests assert the entitlements, including that a failed read is never shown as "consent off" | Done |
| 3 | **Breach runbook** | **Written** (`RUNBOOK-BREACH.md`): three clocks, containment by what leaked, who says what to whom, named owner. **Not yet rehearsed** - that is the remaining half, and it is what turns it from a document into a capability | Rehearsal owed |
| 4 | ~~**Grievance contact per salon**~~ | **Done** (0053/0055 + console). The *app* half — showing it — is part of item 1 | Done |
| 5 | Nomination (s.14) | Statutory, low volume | M12 |
| 6 | Children's-details rule: no DOB or photos for a minor, and a consent purpose if notes are kept | s.9 applies to a note as much as to a profile | M12 |
| 7 | R2 bucket pinned to India/APAC at creation | The sub-processor list is published now; the bucket location is a deployment instruction nobody has executed | Before first real salon |
| 7b | Fill the privacy policy's placeholders, and have a lawyer read it | A published policy naming nobody is evidence the obligation was noticed and skipped | Before first real salon |
| 7c | Hindi and Hinglish translations of the policy | The app ships three languages; the notice behind it must too | M13 |
| 8 | Test a backup restore | An untested backup is a belief, not a safeguard. **Built** (M12): `restore-drill.yml` restores into an empty stack, re-seeds the pepper, verifies and runs every gate. **First run owed** - needs `RESTORE_DRILL_DB_URL` and `RESTORE_DRILL_PEPPER` as repository secrets | Before first real salon |
| 9 | Play Data Safety declaration + privacy policy URL | Blocks release | M13 |
| 10 | Access-log retention aligned to 180 days in India | CERT-In | Before first real salon |

---

## 8. What is genuinely strong already

Worth saying plainly, because most of this was built before the compliance question was asked:

- **Data minimisation**: the pre-auth surface is two functions; a salon code resolves to a name and
  a palette and nothing else; the customer list refuses partial phone-number search.
- **Purpose limitation**, enforced by database policy rather than by intention: a customer reads
  only their own rows; the catalogue is writable only by an owner or manager; visits and ledger
  rows are written only by server functions.
- **Phone numbers as peppered hashes**, with erasure designed around keeping the hash so exclusivity
  survives anonymisation.
- **Consent as an append-only ledger** from the first migration that touched it.
- **An audit trail that cannot be skipped**: every admin action writes `audit_log` in the same
  transaction as the change, asserted by a gate with a deliberate saboteur.

The gaps above are real, but they are gaps in *surfacing* obligations — notice, screens, runbooks —
rather than in the architecture that would be expensive to change.
