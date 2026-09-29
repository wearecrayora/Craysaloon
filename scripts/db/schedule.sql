-- The schedule. Applied to the hosted project, deliberately NOT a migration.
--
--   node scripts/db/run.mjs file scripts/db/schedule.sql
--
-- Why not a migration: pg_cron needs `shared_preload_libraries`, which the
-- hosted project has and a plain Postgres container in CI does not. A migration
-- that only applies on one of the two databases is a migration that makes
-- "migrations apply from zero" untrue, and that property is worth more than the
-- convenience. Re-running this file is safe.
--
-- **What is scheduled here needs no secret.** That is the design constraint,
-- not an accident: sending a message requires the salon's provider credentials
-- and Crayora's service key, and neither may sit in a `cron.job` command string
-- where any superuser session can read it back (RULES 8.12 - a credential is
-- never readable, by anyone, through anything). So cron runs only the DATABASE
-- half - the escalation sweep, bonus expiry and the expiry warning - and the
-- dispatcher that actually spends money is called from outside, with its
-- credentials held outside.

create extension if not exists pg_cron;

-- Unschedule first so this file is idempotent and the cadence can be changed by
-- editing one line rather than by remembering what is already there.
select cron.unschedule(jobid)
  from cron.job where jobname in ('cray-automations', 'cray-nightly');

-- Every minute (ARCHITECTURE 12.3: the escalation sweep runs every minute, and
-- a booking confirmation's window is five). Bonus expiry and the expiry warning
-- ride along: both are idempotent and both are cheap, and a separate nightly
-- schedule would be a second thing to get wrong for no benefit.
select cron.schedule(
  'cray-automations',
  '* * * * *',
  $$select app.run_due_automations()$$
);

-- Automation E and the cohort refresh. 19:15 UTC is 00:45 IST: after midnight
-- in the salons' own day, so "yesterday" has closed, and early enough that the
-- owner opening the app with their morning tea sees last night's numbers.
-- Each salon's work fails alone (app.run_nightly), and the reconciliation is
-- idempotent - one drift alert per salon-day however often this fires.
select cron.schedule(
  'cray-nightly',
  '15 19 * * *',
  $$select app.run_nightly()$$
);

select jobname, schedule, active from cron.job order by jobname;
