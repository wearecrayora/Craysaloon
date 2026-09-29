# Stuck dispatch

## What you will notice

Reminders or "your bill is ready" pushes not arriving; notifications piling up as `pending`.

## How sending works

- **Inside the database**, `pg_cron` runs `app.run_due_automations()` every minute (schedules
  reminders, queues notices) and `app.run_nightly()` at 19:15 UTC (reconciliation, cohorts,
  billing notices). Set by `scripts/db/schedule.sql`, which is not a migration.
- **Sending** is the `dispatch-notifications` Edge Function, called every 5 minutes by the GitHub
  Actions workflow **Dispatch notifications**, because sending needs a key that must not live in
  the database.

## Check, in order

1. GitHub → Actions → **Dispatch notifications**: is it running every 5 minutes, and green? In a
   public repository GitHub disables scheduled workflows after 60 days with no activity - re-enable
   it on the workflow's page.
2. Its secrets: `SUPABASE_URL`, `CRAY_SECRET_KEY`, `DISPATCH_SALON_IDS` (every live salon's id -
   a salon missing from it is never dispatched).
3. The database cron:
   ```sql
   select jobname, schedule, active from cron.job;
   select jobid, status, return_message, start_time
     from cron.job_run_details order by start_time desc limit 10;
   ```
4. Failures recorded by the jobs themselves:
   ```sql
   select occurred_at, payload from public.domain_events
    where type = 'automation.failed' order by occurred_at desc limit 20;
   ```

## Do

Fix the cause, then run the dispatch workflow by hand (*Run workflow*). Pending notifications go
out on the next run; nothing needs re-queuing.

## Never

- Put the service key into a `cron.job` command or Vault to "simplify" this.
