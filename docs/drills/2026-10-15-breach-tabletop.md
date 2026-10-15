# Breach tabletop - 15 October 2026

**The first rehearsal of `RUNBOOK-BREACH.md`.** A desk exercise: one scenario, the runbook followed
in order, and every investigation step **actually run, read-only, against the live system** - so the
record says what works, not what the runbook assumes. No production data was changed during the
exercise; the fixes it led to were made afterwards, through the normal path (migrations, CI).

- **Scenario** (the runbook's own suggestion): *"A researcher emails at 21:40 on a Saturday saying
  they can see another salon's customer list."*
- **Run by:** Claude (Crayora's engineering assistant), on Jyotiranjan's instruction.
- **Clocks, simulated from 21:40:** CERT-In by 03:40; the Board "without delay"; the Board's full
  report by 21:40 on Tuesday.

## Walk-through

| Sim. time | Runbook step | What was done, for real | Result |
|---|---|---|---|
| 21:40 | 2.1 Awareness | Time written down | Works - nothing to need |
| 21:42 | 2.2 Incident note | Opened a note (this file) | Works |
| 21:45 | 2.3 Preserve evidence | Checked `ops.ict_logs`: API, PostgREST, function, auth and database security logs, copied from Supabase into Mumbai, 180-day retention | **Works**, with two limits - see findings 2 and 3 |
| 21:50 | 1 "A cross-tenant gate red?" | Ran the full gate suite on the live database | **742 assertions, 11 seconds, all green** - isolation holds as built. Fast enough to run before replying to the researcher |
| 21:55 | 2.5 Size it | Queried the retained API logs for table reads by path, status, IP and time | **Works in ~1 s.** But the logs carry no caller identity and no row count - finding 2 |
| 22:05 | 3 Contain - salon | `app_admin.set_salon_status(..., 'suspended', reason)`: exists, in the console (salon row) | Works |
| 22:05 | 3 Contain - customer session | `app_admin.unbind_customer`: exists, console binding desk | Works - but it also ends the binding; there is no "sign out only" - finding 6 |
| 22:10 | 3 Contain - operator | Runbook: "deactivate the row in `platform_admins`" | **Broke: no function, no console action - it would have been hand-written SQL on production.** Fixed (finding 1) |
| 22:20 | 2.6 Tell the salon | Salon's owner and privacy contact are in `salons` | Works - but there was no text to send. Fixed (finding 4) |
| 02:40 | 4 CERT-In | Email + phone in the runbook | **No report draft existed.** Fixed (finding 4) |
| 02:45 | 5 Board | "Per the prescribed channel - check before you need it" | **Nobody has checked.** Open (finding 5) |
| 02:50 | 5 Customers | Notice from the salon, individually, in their language | No text existed (fixed, finding 4). Delivery: push only, SMS off; the owner sees numbers and can call - finding 7 |
| - | 8 Contacts | Incident owner phone/email, a second contact | **Still `[PHONE]`, `[EMAIL]`, `[NAME]`.** Open (finding 5) |

## Findings

1. **No way to switch off a Crayora operator** without SQL. **Fixed same day:** migration 0115,
   `app_admin.set_operator_active` (super-admin, reason, audited, ends their sessions at once, never
   yourself, never the last super-admin) and the console's **Operators** page. Gate:
   `admin/operators_test.sql` (6).
2. **The retained logs say what was read and from where, not by whom, nor how many rows.** API log
   rows hold path, status, IP and time; no user, no salon, and the row count is `*/*`. **Mitigation
   (in the runbook now):** size exposure by *reproducing* the leak in the gate suite, then bound who
   by IP and time against the sign-in records in the same store (`auth_logs`).
3. **The log copy runs about every 4 hours, not hourly** (GitHub's schedule, the same unreliability
   that moved dispatch to a Worker). Inside the 23-hour window it copies from, so nothing has been
   lost - but it is not what the runbook claims. Recorded; worth moving to the cron Worker.
   **No sign-in has happened since the copy started (12 Oct)**, so `auth_logs` holds no rows yet:
   check it after the next real sign-in.
4. **No notice drafts.** **Fixed:** `docs/runbooks/breach-notices.md` - CERT-In, the Board
   (intimation and 72-hour report), the salon, and the customer notice in English and Hindi.
5. **Contacts and the Board's channel are blank.** The incident owner's phone and email, a second
   person who knows this runbook, and the Board's prescribed channel - **for Jyotiranjan to fill in**;
   they cannot be guessed.
6. **No "sign this customer out" without unbinding them.** Unbinding works but also releases the
   number. Minor; open.
7. **Customer notices travel by push only** while SMS and WhatsApp are off. The salon owner sees
   each customer's number and can call. Acceptable for a small salon; a bulk notice tool is open if
   it is ever needed.

## Verdict

The runbook works for its central case: in under half an hour, with real queries, isolation was
proven to hold and the scenario could be answered honestly. It had one step that could not be done
without raw SQL (fixed), no words ready for any of the four notices (fixed), and blank contacts
(open, owner's to fill). Next rehearsal: a different scenario - *"an `sb_secret_` key is found in a
screenshot posted publicly"* - which exercises rotation (`docs/runbooks/credential-rotation.md`).
