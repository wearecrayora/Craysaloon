-- 0052 "Latest consent wins" needs a tiebreak that cannot tie
--
-- 0051 read the current consent state with
--   distinct on (purpose) ... order by purpose, occurred_at desc
-- and `occurred_at` defaults to now(), which in PostgreSQL is the TRANSACTION's
-- start time. Two changes to the same purpose in one transaction therefore carry
-- the identical timestamp, and `distinct on` then picks whichever row the plan
-- happened to produce first.
--
-- The gate caught it immediately: a withdrawal made in the same transaction as
-- the consent still read as granted. In production that is the reasonably
-- foreseeable case of a customer tapping a toggle twice, or any batch that
-- writes two rows at once - and the failure mode is the worst available one,
-- marketing continuing after someone asked it to stop.
--
-- `id` is a monotonically increasing bigint, so it orders the ledger exactly and
-- can never tie.

create or replace function public.my_consents()
returns table (purpose text, granted boolean, occurred_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (c.purpose)
         c.purpose::text, c.granted, c.occurred_at
    from public.consents c
   where c.customer_id = app.current_customer_id()
     and c.salon_id = app.current_salon_id()
   order by c.purpose, c.occurred_at desc, c.id desc
$$;

comment on function public.my_consents is
  'The current state of each purpose: the LAST row of the consent ledger. Ordered by occurred_at AND id, because occurred_at is the transaction time and two changes in one transaction would otherwise tie - with the wrong answer being "still consented" (0052).';

revoke all on function public.my_consents() from public, anon;
grant execute on function public.my_consents() to authenticated;
