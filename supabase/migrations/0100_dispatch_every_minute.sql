-- 0100 The dispatcher runs every minute, from Cloudflare - and a claim is a lease.
--
-- Found 13 Oct 2026: GitHub's "every five minutes" dispatch actually fired every
-- four to six HOURS (its scheduled runs are best-effort, and on a quiet repo they
-- are mostly skipped). A booking confirmation or a "your appointment is in two
-- hours" reminder arriving four hours late is not a delay; it is a broken product.
-- The dispatcher now runs from a Cloudflare Worker cron trigger, every minute
-- (cron/, ARCHITECTURE 11), with the service key in that Worker's secrets - still
-- OUTSIDE the database, so schedule.sql stays secret-free (RULES 8.12).
--
-- 1. THE LEASE. claim_notification_batch handed back every queued, unsent
--    delivery, every time it was called. GitHub's concurrency group was the only
--    thing stopping two runs sending the same message twice. A minute cron has
--    no such group: a slow tick overlaps the next. So claiming now STAMPS the
--    rows it hands out (claimed_at), skips rows another caller holds, and a row
--    is only handed out again after five minutes - long enough for any tick to
--    finish, short enough that a dispatcher that crashed mid-send is retried.
--    `for update skip locked` makes two simultaneous claims split the work
--    rather than both taking it.
--
-- 2. THE WATCHDOG. A Worker cron that stops firing is silent. public.dispatch_backlog()
--    counts what is LATE - claimable work more than ten minutes old - using the
--    claim's own rule for what is claimable, so a customer with no device and a
--    salon with no paid channel (which the claim deliberately never picks up)
--    is not an alarm. .github/workflows/dispatch.yml calls it and goes red.

alter table public.notification_deliveries
  add column if not exists claimed_at timestamptz;

comment on column public.notification_deliveries.claimed_at is
  'When a dispatcher last took this row to send. A queued row is not handed out again for five minutes, so overlapping dispatchers never send it twice (0100).';

create or replace function app.claim_notification_batch(p_salon_id uuid, p_limit integer default 50)
returns table(delivery_id uuid, notification_id uuid, channel public.message_channel,
              customer_id uuid, token text, platform text, body text, purpose text)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
  -- A pending notification with no delivery yet gets its first rung: push, if
  -- the customer has a live token. No token means push is skipped entirely and
  -- the ladder starts lower - waiting out a window for a device that cannot
  -- receive is the mistake token hygiene exists to prevent (12.3).
  insert into public.notification_deliveries (salon_id, notification_id, channel, provider_status)
  select n.salon_id, n.id,
         case when t.token is not null then 'push'::public.message_channel
              else app.next_channel(n.salon_id, n.category, '{push}') end,
         'queued'
    from public.notifications n
    left join lateral (
      select nt.token from public.notification_tokens nt
       where nt.customer_id = n.customer_id and nt.dead_at is null
       order by nt.updated_at desc limit 1
    ) t on true
   where n.salon_id = p_salon_id
     and n.status = 'pending'
     and not exists (
       select 1 from public.notification_deliveries d where d.notification_id = n.id)
     and (t.token is not null
          -- Push-only purposes (window NULL, 0086) never open a paid rung.
          or (app.escalation_window(n.purpose) is not null
              and app.next_channel(n.salon_id, n.category, '{push}') is not null))
   limit greatest(coalesce(p_limit, 50), 1);

  -- Everything queued for this salon that nobody holds, with what it takes to
  -- send it - and the hand-out is STAMPED (0100). Claiming is the row that
  -- already exists, so a crash mid-send leaves "we tried"; the lease means a
  -- second dispatcher running at the same moment gets nothing rather than the
  -- same message to send again.
  return query
    with picked as (
      select d.id
        from public.notification_deliveries d
       where d.salon_id = p_salon_id
         and d.provider_status = 'queued'
         and d.sent_at is null
         and (d.claimed_at is null or d.claimed_at < now() - interval '5 minutes')
       order by d.created_at
       limit greatest(coalesce(p_limit, 50), 1)
       for update skip locked
    ), claimed as (
      update public.notification_deliveries d
         set claimed_at = now()
        from picked p
       where d.id = p.id
      returning d.id, d.notification_id, d.channel, d.created_at
    )
    select c.id, c.notification_id, c.channel, n.customer_id,
           t.token, t.platform,
           app.render_template(n.salon_id, n.template_key, n.locale, c.channel, n.params),
           n.purpose
      from claimed c
      join public.notifications n on n.id = c.notification_id
      left join lateral (
        select nt.token, nt.platform from public.notification_tokens nt
         where nt.customer_id = n.customer_id and nt.dead_at is null
         order by nt.updated_at desc limit 1
      ) t on true
     order by c.created_at;
end;
$function$;

revoke all on function app.claim_notification_batch(uuid, integer) from public, anon, authenticated;

create or replace function public.dispatch_backlog()
returns table(late integer, oldest timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  with due as (
    -- Queued and never sent: the dispatcher had it and did not finish, or never ran.
    select d.created_at
      from public.notification_deliveries d
      join public.salons s on s.id = d.salon_id and s.status = 'active'
     where d.provider_status = 'queued'
       and d.sent_at is null
       and d.created_at < now() - interval '10 minutes'
    union all
    -- Pending with no delivery yet, and claimable by the claim's own rule: the
    -- dispatcher would have opened a rung for it if it had run.
    select n.created_at
      from public.notifications n
      join public.salons s on s.id = n.salon_id and s.status = 'active'
     where n.status = 'pending'
       and n.created_at < now() - interval '10 minutes'
       and not exists (
         select 1 from public.notification_deliveries d where d.notification_id = n.id)
       and (exists (select 1 from public.notification_tokens nt
                     where nt.customer_id = n.customer_id and nt.dead_at is null)
            or (app.escalation_window(n.purpose) is not null
                and app.next_channel(n.salon_id, n.category, '{push}') is not null))
  )
  select count(*)::integer, min(created_at) from due
$$;

comment on function public.dispatch_backlog() is
  'The dispatcher watchdog: messages it should have sent more than ten minutes ago, by the claim''s own rule. Non-zero means the dispatcher is not running. Called by .github/workflows/dispatch.yml (0100). service_role only.';

revoke all on function public.dispatch_backlog() from public, anon, authenticated;
grant execute on function public.dispatch_backlog() to service_role;
