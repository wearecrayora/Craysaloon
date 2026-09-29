# Release audit — PRD §20, item by item

M13's done-when is "every box in PRD §20 is ticked". A box is ticked only with **evidence**: a CI
gate that asserts it (and, for the load-bearing ones, a negative control proving the gate can go
red), or a recorded manual run. "The code looks right" is not evidence.

Legend: ✅ proven by a gate · 🔧 gap - to build · 👤 needs a person to do it once, recorded here ·
⚖️ needs legal/CA sign-off · ➖ does not apply as built, with the reason

*Audited 29 Sep 2026 against 582 passing pgTAP assertions, 197 app tests and 13 console tests.*

## Isolation & binding

| Item | Status | Evidence / what remains |
|---|---|---|
| Cross-tenant isolation passes (automated, catalogue-driven) | ✅ | `rls/leak_test.sql` + its negative control (an unprotected table must turn it red) |
| A phone bound to Salon A cannot bind to Salon B | ✅ | `rls/binding_test.sql`, `rls/bind_flow_test.sql` ("already bound") |
| No customer-facing salon-switch or salon-add path | ✅ | No such route or RPC exists; binding changes only via `app_admin.unbind/transfer` (admin-plane gate) |
| "Already registered" never names the other salon | ✅ | `bind_flow_test`: the refusal carries no salon; app copy `joinAlreadyBound` |
| Transfer moves binding, leaves wallet/history, records acknowledged balance | ✅ | `bind_flow_test` (10 transfer assertions) |

## Money

| Item | Status | Evidence / what remains |
|---|---|---|
| No wallet-adjustment control or endpoint for owner/manager | ✅ | `money/ledger_test` (only five ledger callers, none owner-callable) + negative control; O5 test asserts the control is *absent* |
| Add Money shows bonus, bonus expiry, "paid never expires", "this salon only", "no cash withdrawal" before payment | ✅ | `app/test/wallet_test.dart` "the disclosure block is ABOVE the pay button" |
| No setting, column or code path can expire paid credit | ✅ | `wallet_lots_paid_never_expires` constraint; `ledger_test` refuses expiring a paid lot |
| **A top-up produces a receipt, not a tax invoice; GST appears on the service invoice** | 🔧 ⚖️ | **Not built. There is no invoices or receipts table.** Build: a top-up receipt, a per-salon per-financial-year numbered service invoice at settlement, GST shown only for a GST-registered salon. ⚖️ CA confirms format, rate and the unregistered-salon case |
| Suspend/purge offers export, requires credit settled, purges personal, retains financial | ✅ | `privacy/offboarding_test.sql` (32) + two negative controls |
| Concurrent wallet debits cannot overdraw | ✅ | `ledger_test` "concurrent spending cannot overdraw (the row lock decides)" |
| Bonus spent before paid | ✅ | `ledger_test` bonus-first assertion; `start_and_pay_test` "both lots were spent" |
| Expiry posts a ledger entry; owner expiry changes do not alter issued credit | ✅ | `ledger_test` expiry assertions (bonus expiry captured onto each lot at issue) |
| No refund-to-bank and no cash-out path | ✅ | No such caller exists (the five ledger callers); `ledger_test` |
| Failed payment handled; cancelled service returns value into the wallet | ✅ / ➖ | Failed: `payments_test` (a wrong amount is refused, the payment left untouched); the app says "Nothing was charged". **Cancelled service ➖:** nothing is paid before a visit - payment follows completion - so there is no prepaid service to return. When prepaid bookings or packages exist, this becomes a 🔧 |
| Dashboard totals match completed transactions | ✅ | `metrics/dashboard_test` + negative control (drift is reported, never healed) |

## Booking & loop

| Item | Status | Evidence / what remains |
|---|---|---|
| Duplicate booking / full slot rejected by a database constraint | ✅ | `booking_test` + negative control (the exclusion constraint dropped must turn it red); `in_progress` covered since 0084 |
| Add-ons never pre-selected | ✅ | App: add-ons render unticked (walk-in and booking); `booking_test` |
| Self-referral rejected; cancelled referral releases nothing | ✅ | `growth/referral_test` + negative control |
| Reminder opt-out honoured; exactly one per cycle | ✅ | `messaging/reminder_test` + negative control (index dropped) |
| Offline mark-complete syncs; rejections reach "Needs attention" | ✅ | `app/test/outbox_test.dart`, `day_screen_test.dart` |
| Owner logs in with the registered number and runs the day unaided | 👤 | A real owner, a real phone, a full day: book, start, complete, take payment, walk-in. Record who and when below |

## Provisioning & branding

| Item | Status | Evidence / what remains |
|---|---|---|
| A non-engineer provisions a salon in the console, no SQL | 👤 | Console built for it (M2). Record a non-engineer doing it on the live console |
| Switching a salon on is a deliberate manual action | ✅ | `admin_plane_test` (activate_salon is the only door; setup fee required since 0087) |
| Branding published in the console reaches the app on next open | ✅ | Built 30 Sep 2026: `my_branding()` (0093) read on every open and every resume; `app/test/branding_refresh_test.dart` (6: worn and stored, resume, privacy contact, offline keeps the cache, nothing rewritten if unchanged, another salon's answer never worn); `leak_test` (my_branding names only the caller's salon) |
| Contrast check blocks an unreadable palette at publish | ✅ | `write_scope_test` "nor publish branding that never passed the contrast gate"; design-tokens tests |

## Messaging

| Item | Status | Evidence / what remains |
|---|---|---|
| Push acknowledged; WhatsApp only after an unacked window or opt-in | ✅ | `reminder_test` + negative control (a sweep that ignores the ack) |
| Messages send from the salon's own accounts and carry the salon's name | ✅ | `messaging_access_test`, `reminder_test` ("every message is branded") |
| Unapproved templates: the ladder skips WhatsApp cleanly | ✅ | `reminder_test` "with no approved templates … falls to SMS - and WORKS" |
| App branded as the salon before the phone-number screen | ✅ | `join_flow_test.dart` (U3 wears the brand) |
| First OTP from the salon's account; no salon context refused; hook rejects unsigned | ✅ / ➖ | `otp_test` "NO salon context is refused". **Hook ➖:** there is no Send SMS Hook (ADR-36); the claims hook is a database function, not an HTTP endpoint |
| No code templates, brands or validates the OTP message | ✅ | By construction (VerifyNow owns it); lint gate |
| Screen while waiting for the OTP is salon-branded | ✅ | U5 wears the brand (join flow test) |
| Every push carries the salon's name, logo and colour | ✅ / 👤 | Built 30 Sep 2026: title = salon name, the salon's primary on its own `cray_salon` channel, the logo as the notification image (Android and iOS); `salon_push_brand()` (0093, service_role only - `leak_test`); `_shared/push_message.test.ts` (5). **👤 The logo needs the console's logo upload**, not built yet: until a salon has an https logo the push carries name and colour only |
| WhatsApp template per key and locale, matching variables | 👤 | Operator task in Message Central / Meta per salon, before that salon's WhatsApp rung goes live |
| OTP rate-limited per phone, IP, device and per salon per day | ✅ | `start_join` limits (phone 5/h, caller 20/h, salon 500/day); `otp_test` |
| Broken salon Message Central account falls back and alerts | ✅ | `otp_test` fallback assertions; Edge alert to Sentry |

## Security & compliance

| Item | Status | Evidence / what remains |
|---|---|---|
| No secret keys in the APK or console client bundle | ✅ / 👤 | `secret-scan.sh` over the console bundle (clean); **the release APK must be built and scanned** - part of the Play build |
| Per-salon secrets unreadable after save | ✅ | `admin_plane_test` (exactly one decrypting reader) + negative control |
| WhatsApp templates Meta-approved before that salon's WhatsApp rung | 👤 | As above |
| DPDP export and anonymise work; anonymise preserves ledger and binding | ✅ | `data_rights_test` (25), `offboarding_test` + negative controls |
| Every super-admin access audit-logged | ✅ | `admin_plane_test` + negative control (an unaudited mutating function) |
| Backup restore rehearsed | 👤 | Drill built (`restore-drill.yml`); **first run owed** - needs two repository secrets and a push |

## Summary

- ✅ proven: 35 · 🔧 to build: **1** (receipts and invoices; branding refresh and push branding built 30 Sep 2026) ·
  👤 once, by a person: 6 · ⚖️ CA: invoice format · ➖ two, with reasons
- Build order: branding refresh and push branding first (small, customer-visible); invoices next
  (the largest, and the CA's answer shapes it).

## Manual runs (fill in)

| Item | Who | Date | Result |
|---|---|---|---|
| Owner runs a full day unaided | | | |
| Non-engineer provisions a salon on the live console | | | |
| Restore drill first run | | | |
| Release APK built and secret-scanned | | | |
