# Stuck dispatch

## What you will notice

Reminders or "your bill is ready" pushes not arriving; notifications piling up as `pending`; the
GitHub workflow **Dispatch watchdog** red ("message(s) should have been sent more than ten minutes
ago").

## How sending works

- **Inside the database**, `pg_cron` runs `app.run_due_automations()` every minute (schedules
  reminders, queues notices) and `app.run_nightly()` at 19:15 UTC (reconciliation, cohorts,
  billing notices). Set by `scripts/db/schedule.sql`, which is not a migration.
- **Sending** is the `dispatch-notifications` Edge Function, called **every minute** for every
  active salon by the Cloudflare Worker **`craysalon-cron`** (`cron/`, 0100). The service key it
  needs lives in that Worker's secrets, never in the database.
- **Watching** is the GitHub workflow **Dispatch watchdog**, about every 30 minutes (GitHub runs
  schedules late; that is fine for a watchdog). It calls `public.dispatch_backlog()` and goes red
  if anything claimable is more than ten minutes old.

GitHub used to do the sending. Its "every five minutes" fired every four to six hours (measured
13 Oct 2026), which is why the clock moved to Cloudflare.

## Check, in order

1. Cloudflare (Crayoratech account) → Workers → **craysalon-cron** → cron events / logs: is it
   firing every minute, and are the invocations succeeding? A thrown error names the salon and
   the HTTP status.
2. Its secret: `CRAY_SECRET_KEY` (`cd cron && npx wrangler secret list`). After rotating the
   Supabase secret key it must be set again, or every tick fails with 401.
3. The backlog itself, as the watchdog sees it:
   ```sql
   select * from public.dispatch_backlog();
   ```
4. The database cron:
   ```sql
   select jobname, schedule, active from cron.job;
   select jobid, status, return_message, start_time
     from cron.job_run_details order by start_time desc limit 10;
   ```
5. Failures recorded by the jobs themselves:
   ```sql
   select occurred_at, payload from public.domain_events
    where type = 'automation.failed' order by occurred_at desc limit 20;
   ```

## Do

Fix the cause. To send what is waiting meanwhile, run **Dispatch watchdog** by hand
(*Run workflow*): a manual run also dispatches every active salon once. That is safe beside the
Worker - a claim is a five-minute lease (0100), so nothing is sent twice. Nothing needs re-queuing.

## Never

- Put the service key into a `cron.job` command or Vault to "simplify" this.
- Move the sending back onto a GitHub schedule.
