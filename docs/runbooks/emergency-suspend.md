# Emergency suspend

## When

Fraud, abuse, a legal order, a salon misusing customer data - a decision **about the salon**.
Not for non-payment: the billing dates already make a lapsed salon read-only
([billing-lapse.md](billing-lapse.md)).

## Do

Console → Salons → **Manage** → *Move to*:

- **Grace** - read-only; the salon can still be seen.
- **Suspended** - the salon stops operating.

A reason is required and goes in the audit log.

## Effect

No writes, no new customers. Reads, consent withdrawal and captured Razorpay payments continue.
Customers can still see their wallet balance - money the salon owes them.

## Lifting it

Console → Salons → **Manage** → *Lift the suspension* → **Reactivate** (super-admin, reason).
Refused for a purged salon, and for one whose subscription has lapsed - record the payment first.

## Never

- Suspend and forget. Put the review date in the reason, and diary it.
- Tell customers why. The salon is the Data Fiduciary and the relationship is theirs.
