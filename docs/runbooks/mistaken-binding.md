# Mistaken binding

## What you will notice

A customer says they joined the wrong salon, or a new salon's customer gets "This number is
already registered with a salon."

## Do - console → **Customer binding** (super-admin)

1. Look up by the customer's **exact, full** phone number, with a reason. There is no partial
   search, by design.
2. **Unbind** - offered only when the customer has no history at that salon. The number is free to
   join the right salon.
3. **Transfer** - when there is history. Needs the destination salon, a typed reason, the balance
   **as disclosed** to the customer (it must match what the system holds), and a tick that the
   customer was told. The wallet and history **stay with the old salon** - credit is redeemable
   only where it was issued. The old salon settles it with the customer.

## Never

- Name the other salon to the customer. "Already registered with a salon" is all they are told.
- Move a wallet balance between salons. There is no path, on purpose - it would make the credit
  semi-closed and licensable.
