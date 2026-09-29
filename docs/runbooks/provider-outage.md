# Provider outage

## Message Central (login codes)

**Notice:** customers say the code never arrives; the console's salon row shows OTP
**fallbacks** this week.

- If the **salon's** account fails, the code goes from **Crayora's** account instead - logged and
  alerted, and paid by us. Fix the salon's account (balance, credentials) under Credentials.
- If Message Central itself is down, nobody new can log in. People already logged in are
  unaffected (sessions are Supabase's). Tell salons; there is no second OTP provider.

## Razorpay (UPI top-ups and bill payments)

**Notice:** customers see "That payment did not go through"; top-ups stay at "sent".

- **Pay at the counter still works** - staff take cash or card, and the bill settles.
- A payment Razorpay captured during the outage credits when its webhook arrives; Razorpay
  retries. Nothing to do by hand.
- After the outage, compare the salon's Razorpay dashboard with the console for any capture that
  never arrived, and have Razorpay resend the webhook. **Never credit a wallet by hand** for it.

## FCM (push)

**Notice:** reminders and "bill ready" pushes not arriving.

- Reminders escalate to WhatsApp/SMS only when a push is not **acknowledged** - so an FCM outage
  costs the salon paid messages. Watch the push-to-paid ratio on **Metrics**.
- "Bill ready" never escalates to a paid channel. The customer can pull to refresh on their home
  screen, or pay at the counter.

## Never

- Switch a salon to Crayora's Message Central account "for now" without recording it as a trial or
  grace with an end date.
