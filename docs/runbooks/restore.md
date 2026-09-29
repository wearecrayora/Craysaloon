# Restore

**An untested backup is not a backup.** The drill below runs monthly and before every release.

## The monthly drill (rehearsal)

GitHub → Actions → **Restore drill** → *Run workflow*. It:

1. snapshots the hosted database's row counts and protections;
2. takes a logical backup exactly as Supabase documents it (roles, schema, data);
3. starts a **brand-new, empty** Supabase stack on the runner and restores into it;
4. **re-seeds the phone-hash pepper** into the copy's Vault (step 4 below - the one people forget);
5. verifies the copy: every table, RLS enabled *and forced*, money and identity tables row-exact,
   every wallet balance equal to its ledger, and phone numbers hashing to the same value as the
   source (`scripts/ops/restore-verify.mjs`);
6. runs **every release gate** against the copy;
7. deletes the backup, even if a step failed.

Needs two repository secrets: `RESTORE_DRILL_DB_URL` (direct connection, port 5432) and
`RESTORE_DRILL_PEPPER` (the value of `PHONE_HASH_PEPPER`). A red run is a production defect:
the backup you would need tomorrow does not work today.

Record each run in the table at the bottom.

## A real restore

**Prefer restoring in place.** A point-in-time or daily restore *into the same project*
(Supabase dashboard → Database → Backups; needs a paid plan) keeps the project URL, the API keys
and the Vault key. Everything below the line "only for a new project" is then unnecessary.
Check what the current plan includes **before** it is needed.

### Only when restoring into a new project

1. **Stop writes.** Suspend nothing - put the console in a known state and tell salons the app is
   read-only for the restore window.
2. Create the project: **Postgres 17**, region **Mumbai (ap-south-1)** - data stays in India.
3. Restore, from a dump or the dashboard's backup file:
   ```
   psql --single-transaction -v ON_ERROR_STOP=1 -f roles.sql -f schema.sql \
        -c 'SET session_replication_role = replica' -f data.sql -d "$NEW_DB_URL"
   ```
4. **Re-seed the pepper - with the SAME value.** Vault is encrypted per project: the restored
   secrets are unreadable. Without the same pepper every stored phone hash is unmatchable and
   **nobody can ever log in again**. Keep `PHONE_HASH_PEPPER` offline, in two places.
   ```sql
   delete from vault.secrets where name = 'phone_hash_pepper';
   select vault.create_secret('<the same pepper>', 'phone_hash_pepper');
   ```
5. **Re-enter every salon's credentials** in the console (Credentials page) - Message Central,
   Razorpay, WhatsApp, RCS. They were in Vault too. Test each.
6. **Every salon's Razorpay webhook URL changes** with the project URL. Update each one in that
   salon's Razorpay dashboard, or top-ups will capture and never credit.
7. Edge Functions: `supabase functions deploy` each; set their secrets again
   (`FCM_SERVICE_ACCOUNT`, `SENTRY_DSN`, …).
8. Cron: run `scripts/db/schedule.sql` (it is not a migration).
9. **The app has the old project URL and publishable key compiled in.** A new project means a new
   app build and a forced update - or a custom domain that was set up before the incident.
10. Point the console (Vercel env `ADMIN_DATABASE_URL`, Supabase keys) and GitHub secrets at it.
11. Verify: `SOURCE_DB_URL=<old, if reachable> node scripts/ops/restore-verify.mjs snapshot`,
    then `TARGET_DB_URL=<new> node scripts/ops/restore-verify.mjs verify`, then
    `DATABASE_URL=<new> node scripts/db/run.mjs test`.
12. **Reconcile money.** Payments captured by Razorpay between the backup and the restore exist in
    each salon's Razorpay dashboard but not in the database. Compare, and credit through the
    webhook replay - never by hand.

## Never

- `db reset`, on any hosted project, ever.
- Restore over the live project without a fresh backup of what is there now.
- Generate a new pepper "because the old one is lost". It cannot be recovered from the data. Find
  the offline copy.

## Drill log

| Date | Who | Result | Notes |
|---|---|---|---|
| | | | First run owed: add the two secrets, then run the workflow |
