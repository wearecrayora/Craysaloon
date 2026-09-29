# Offboarding a salon

PRD 16A.6: personal data is purged; financial records are kept, anonymised, for the statutory
books-of-account period (**⚖️ a CA confirms the period**). The database enforces the order.

## When

Purge is **due** 90 days after suspension (see [billing-lapse.md](billing-lapse.md)). A salon
that asks to leave: stop billing; the dates carry it to purge-due.

## Steps - console → salon → Billing → Offboarding (super-admin only)

1. **Offer the owner their data.** *Download the salon's export (JSON)*, send it to the owner,
   then *Record export offered* with how and when.
2. **Settle the customers' credit.** The page shows what customers still hold. A salon cannot
   keep money for services it will never provide. The salon refunds them (cash at the counter,
   UPI back); record *how*, with evidence. The ledger is **not** changed - the balances stay in
   the books beside your note.
3. **Purge.** Reason, and the salon's display name typed back.

## What the purge does

| Goes | Stays |
|---|---|
| Customers' names, numbers, birthdays, login links | Every payment, visit, wallet and loyalty ledger row |
| Customers' bindings (released - each can join another salon) | The salted phone hash on the anonymised record |
| Device tokens, notifications and deliveries, reminders, join codes in flight | Consents (a record of what was agreed) |
| Staff names, numbers, logins | Bookings (notes cleared) |
| The salon's provider credentials (Vault secrets deleted) | The salon's legal name and GST number |

Afterwards nobody - no customer, no staff member - can log in to that salon. Its books are
reachable only by super-admins, through the console. **A purged salon can never be activated,
reactivated or have its status changed.**

## Never

- Purge before the owner was offered the export.
- Delete a row from `payments`, `wallet_transactions`, `wallet_lots` or `loyalty_ledger` - the
  triggers refuse, and the law requires them.
