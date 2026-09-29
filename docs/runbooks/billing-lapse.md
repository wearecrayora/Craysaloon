# Billing lapse

## What you will notice

- Console → salon → **Billing** shows *GRACE*, *SUSPENDED* or *PURGE DUE* in red.
- The **Notices** list on that page gains a row when each notice falls due: grace started,
  suspended, day 60, day 80, purge due.
- The owner's app shows **"Read-only for now"** on the day view.

## What it means

The state is computed from the date the paid period ends (`renews_at`). Nobody flips it:

| From the due date | State | The salon |
|---|---|---|
| day 0 | grace | Read-only. Staff and customers log in and read; nothing new is recorded; nobody new joins |
| day 7 | suspended | Same, and counted as churn |
| day 97 (suspended + 90) | purge due | Same. **Nothing is deleted** until someone runs the purge ([offboarding.md](offboarding.md)) |

Still open while lapsed, on purpose: reading, consent withdrawal, Razorpay captures (the money
already moved), and login for people the salon already has.

## What to do

1. **Each notice is a call to make.** There is no automatic message to the owner yet. Call; note
   the outcome in your CRM.
2. When money arrives: Billing → **Record a payment** - amount, months, **reference** (UTR / UPI
   ref). The period runs on from the old due date, so a late payer pays for the time they had.
   The salon is writable the moment it is saved.
3. Goodwill or an outage on our side: **Extend (comp)**, with a reason.

## How you know it worked

The banner on the Billing page turns to *Paid up*; the owner pulls down on the day view and the
read-only banner is gone.

## Never

- Suspend a salon by hand for non-payment - the dates already do it, and a manual suspension
  does not lift when they pay.
- Record a payment twice. There is no reversal yet; check the amount and months before saving.
