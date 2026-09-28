# Runbook — personal data breach

**Written for: whoever is holding this when it happens.** Follow it in order. It assumes you are
tired, it is late, and you are not sure yet whether this is real.

**Owner: Jyotiranjan (Crayora).** One named human, deliberately — not "the team". If that changes,
change it here in the same week, and tell every salon whose agreement names a contact.

> **Status: NEVER REHEARSED.** See §9. A runbook that has only ever been read is a belief, not a
> capability. The first rehearsal is owed before the first real salon.

---

## 0. The clocks

All three start **when you become aware** — not when you finish investigating, not when you are
certain, not when you have a fix.

| Clock | To whom | Deadline | Authority |
|---|---|---|---|
| **6 hours** | CERT-In | From noticing | CERT-In Directions, 28 Apr 2022, §(ii) + Annexure I |
| **Without delay** | Data Protection Board, and the affected customers | Immediately, with what you know | DPDP Act s.8(6); DPDP Rules 2025 r.7 |
| **72 hours** | Data Protection Board — the full report | From awareness | DPDP Rules 2025 r.7 |

**Never wait for certainty before notifying.** The Rules expect an initial intimation and then an
update. A late complete report is a breach of the Rules; an early incomplete one is what they ask
for.

---

## 1. Is this a breach?

A personal data breach is any **unauthorised processing, accidental disclosure, acquisition,
sharing, use, alteration, destruction or loss of access** to personal data that compromises its
confidentiality, integrity or availability. Note the last one: **losing access to data counts**, so
a destructive outage or a botched migration is in scope, not only an attacker.

Treat each of these as a breach until proven otherwise:

- A customer, salon or researcher reports seeing **someone else's data** — another salon's
  customers, or another customer's rows.
- A **cross-tenant or customer-scope gate goes red on `main`**, or a policy change shipped without
  one. Assume it was reachable; prove it was not.
- A **`sb_secret_…` key, a Supabase database password, a Razorpay key or a Message Central token**
  is exposed — committed, pasted, screenshotted, logged, or on a lost laptop.
- **Console access by someone who should not have it**: a shared login, an MFA bypass, a stolen
  phone with a live session, a departed operator still in `platform_admins`.
- **R2 objects readable without a signed URL**, or a signed URL with an absurd lifetime.
- A **Supabase, Cloudflare, Razorpay, Message Central or Sentry** incident notice that touches our
  data.
- **OTPs delivered to the wrong number**, or a binding attached to the wrong customer.
- Data **destroyed or unrecoverable** — a bad migration, a dropped table, an unrestorable backup.

Ambiguous? Treat it as a breach and start the clock. Standing it down later costs an email; starting
it late cannot be undone.

---

## 2. First 60 minutes

Do these in order. Write the time next to each as you go — that log becomes the report.

1. **Write down when you became aware, and how.** Exact clock time. Everything else is measured
   from it.
2. **Open an incident note** (a file, a doc, anything durable). One place, timestamped entries,
   including the things you tried that did not work.
3. **Do not delete anything.** Not logs, not the branch, not the bad migration, not the Sentry
   event. Preserving evidence is an obligation, and deleted evidence looks like a cover-up even
   when it is panic. **Logs are retained 180 days, in India** (CERT-In).
4. **Contain** — §3.
5. **Size it**: which salons, how many customers, which fields. Phone numbers? Names? Visit
   history? Money? Photos? **Write down what you do not yet know**, as a list of open questions.
6. **Tell the affected salon(s).** They are the Data Fiduciary — the obligation and the penalty are
   theirs, and they cannot meet either if we sit on it. Plain language, what is known, what is not,
   what we are doing, when they will hear next.
7. **Report to CERT-In** — §4. Inside 6 hours. Do not wait for step 5 to be complete.
8. **Intimate the Board, and the customers** — §5.

---

## 3. Containment, by what leaked

**Session and account compromise**

- Revoke the customer's or operator's sessions. `app_admin.unbind_customer` ends a customer
  binding and its sessions (audited). For an operator, deactivate the row in `platform_admins`
  first, then rotate their credentials.
- Never "wait and watch" a live session to gather evidence. Cut it.

**A key or token**

- Rotate at the provider first, install second — a rotated-but-still-valid key is not rotated.
- `sb_secret_…`: rotate in the Supabase dashboard, update every Edge Function secret and
  `console/.env.local`, redeploy. The publishable key is public and is not a breach on its own.
- Razorpay / Message Central / WhatsApp / RCS: rotate in the **salon's own** provider dashboard
  (they own the account), then re-enter it in the console. It is write-only here; there is nothing
  to read back, which is why this step is short.
- Database password: rotate, then re-issue to anything holding it.

**A policy or query leak**

- Revert the change. A forward-only migration that restores the policy beats a clever fix.
- Then reproduce it in the gate suite **before** claiming it is fixed. If no gate would have caught
  it, write that gate in the same session — that is how 0038 and 0055 were closed.

**A salon that must stop taking traffic**

- `app_admin.set_salon_status(..., 'suspended', reason)`. Never delete anything to stop it.

**Files**

- Signed URLs expire; an exposed object does not. Replace the object key, invalidate, and treat
  every URL already issued as public forever.

---

## 4. CERT-In — 6 hours

**Email:** incident@cert-in.org.in **Phone:** 1800-11-4949

Use CERT-In's Annexure I format. Send what you have at the 5-hour mark even if half of it says
"under investigation". Include:

- Time of occurrence, and time of detection (they differ; say both).
- Type of incident: data breach / unauthorised access / compromise of systems.
- Affected systems: which service (Supabase Postgres, Edge Functions, console, R2), region.
- What data, and roughly how many people.
- What has been done so far, and what is planned.
- Crayora's contact: name, phone, email, and the address.

Keep the sent copy. It is evidence that the clock was met.

---

## 5. The Board, and the customers

**The Board** (Data Protection Board of India), via the prescribed channel: an intimation
**without delay** with the nature, extent, timing and likely consequences as far as known, and
within **72 hours** the full report — the broader facts and circumstances, the mitigation measures,
the findings about who caused it, remedial measures to prevent recurrence, and a copy of the
intimations given to affected Data Principals.

**The customers.** The salon is the Data Fiduciary, so the notice goes out **from the salon** —
Crayora drafts it, provides the facts, and makes sure it goes. In their own language, in plain
words, and to each affected person individually. It must say:

- what happened, in one sentence a person can repeat;
- what data of **theirs** was involved — not a list of everything the system holds;
- what it could mean for them;
- what has been done, and by when;
- what they should do, if anything (and if nothing, say that plainly rather than padding);
- the salon's privacy contact, by name, and how to reach the Board.

**Do not** put customer data into the notification itself, do not email a spreadsheet of affected
people to anyone, and do not let "we take your privacy seriously" appear anywhere in it.

---

## 6. What not to do

- Do not tell a salon "nothing was accessed" before you have checked the logs. You will have to
  take it back, and that is the sentence they will remember.
- Do not quietly fix and move on. An unreported breach that surfaces later is a different and much
  worse conversation, with the salon and with the Board.
- Do not narrow a gate to make CI green during an incident. The gate is the evidence.
- Do not rotate a credential into a chat window, a ticket or a commit.
- Do not start the write-up by deciding whose fault it was.

---

## 7. After

Within **two weeks**, write a post-incident note covering: what happened, the timeline including
the three clocks and whether each was met, what made it possible, what made it hard to detect, and
the **gate or control that now exists** so the same thing fails loudly next time. A fix with no gate
is a promise; a gate is a fact.

File it next to this runbook, and add the gate to `CLAUDE.md`'s hard-gate list if it is one.

---

## 8. Contacts

| Who | Detail |
|---|---|
| Incident owner | Jyotiranjan (Crayora) — [PHONE], [EMAIL] |
| Second contact | [NAME], [PHONE] — required: one person cannot be the only one who knows |
| CERT-In | incident@cert-in.org.in · 1800-11-4949 |
| Data Protection Board | Per the prescribed channel at the time — check before you need it |
| Supabase support | Project dashboard → Support (paid plan required for a fast path) |
| Razorpay / Message Central | The **salon's** account contacts, held per salon in the console |
| Salon privacy contacts | `salons.grievance_name/email/phone`, per salon (0053) |

---

## 9. Rehearsal log

A runbook nobody has walked through has unknown steps in it: a login nobody has, a format nobody
has seen, a phone number that rings nowhere. Rehearse it as a tabletop — 45 minutes, one scenario,
no production changes — and record it here honestly.

| Date | Scenario | Who | What broke in the runbook |
|---|---|---|---|
| — | *Never rehearsed* | — | — |

Suggested first scenario: **"A researcher emails at 21:40 on a Saturday saying they can see another
salon's customer list."** It exercises all three clocks, the salon relationship, and the one failure
this system is built to prevent.
