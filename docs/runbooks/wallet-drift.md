# Wallet or dashboard drift

## Two different things

**A dashboard number** (the owner's revenue or bookings card) disagrees with the visits. The
nightly reconciliation compares the stored numbers with the source; on a mismatch it raises
**one alert per salon-day** and **leaves the stored number wrong**, and the owner's dashboard says
so. It is never healed silently - healing hides the cause (PRD 9.5).

**A wallet balance** disagrees with its ledger. This should be impossible: every balance change
goes through one function, in the same transaction as its ledger row.

## Check

```sql
-- Any balance that is not its ledger (expect zero rows):
select w.customer_id, w.balance_paise,
       coalesce((select sum(t.amount_paise) from public.wallet_transactions t
                  where t.customer_id = w.customer_id), 0) as ledger
  from public.wallet_accounts w
 where w.balance_paise <> coalesce((select sum(t.amount_paise) from public.wallet_transactions t
                                     where t.customer_id = w.customer_id), 0);

-- Recent dashboard drift alerts:
select occurred_at, salon_id, payload from public.domain_events
 where type = 'metrics.drift' order by occurred_at desc limit 20;
```

## Do

- **Dashboard drift:** find the cause (usually a write path that skipped the metric). Fix the code.
  The next nightly run records the corrected day.
- **Wallet drift:** stop and treat it as an incident - it means money moved outside the one path
  allowed to move it. Find the writer. Only then, and only for a proven error, **Wallet
  correction** in the console (a new ledger row with a reason - the only human path to a balance).

## Never

- `update public.wallet_accounts set balance_paise = …`. Ever.
- Delete or edit a ledger row. Corrections are new rows.
