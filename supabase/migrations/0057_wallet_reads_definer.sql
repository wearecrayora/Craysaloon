-- 0057 The wallet reads have to be DEFINER, for a reason worth writing down
--
-- 0056 made `my_wallet` and `my_wallet_history` SECURITY INVOKER, copying
-- `list_customers` (0040). The gate failed immediately: **permission denied for
-- schema app**.
--
-- `list_customers` gets away with it because it names no helper - it selects
-- from tables and lets RLS answer. These two call `app.current_customer_id()`,
-- and `authenticated` has no USAGE on the `app` schema on purpose (0025: a
-- grant like that is how the pre-auth surface leaked the first time).
--
-- The right answer is the one `my_consents` already uses: SECURITY DEFINER with
-- the customer named explicitly in the predicate. The rule is then visible in
-- the function rather than inherited from a policy the reader has to go and
-- look up - and for a function whose whole job is "my own money", saying whose
-- money it is out loud is the clearer of the two.

create or replace function public.my_wallet()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'balance_paise', coalesce(
      (select a.balance_paise from public.wallet_accounts a
        where a.customer_id = app.current_customer_id()), 0),
    'paid_paise', coalesce(
      (select sum(l.remaining_paise) from public.wallet_lots l
        where l.customer_id = app.current_customer_id()
          and l.kind = 'paid' and l.expired_at is null), 0),
    'bonus_paise', coalesce(
      (select sum(l.remaining_paise) from public.wallet_lots l
        where l.customer_id = app.current_customer_id()
          and l.kind = 'bonus' and l.expired_at is null), 0),
    'next_bonus_expiry', (
      select min(l.expires_at) from public.wallet_lots l
       where l.customer_id = app.current_customer_id()
         and l.kind = 'bonus' and l.expired_at is null
         and l.remaining_paise > 0 and l.expires_at is not null),
    'next_bonus_paise', coalesce((
      select l.remaining_paise from public.wallet_lots l
       where l.customer_id = app.current_customer_id()
         and l.kind = 'bonus' and l.expired_at is null
         and l.remaining_paise > 0 and l.expires_at is not null
       order by l.expires_at
       limit 1), 0)
  )
$$;

comment on function public.my_wallet is
  'Balance with paid and bonus shown SEPARATELY (DESIGN 6.2), read from the lots rather than the cached balance. SECURITY DEFINER keyed on app.current_customer_id(), like my_consents: a caller with no customer id sees zeros, never somebody else''s money (0057).';

revoke all on function public.my_wallet() from public, anon;
grant execute on function public.my_wallet() to authenticated;

create or replace function public.my_wallet_history(
  p_limit  integer default 20,
  p_before bigint default null
)
returns table (
  id            bigint,
  kind          text,
  amount_paise  bigint,
  balance_after bigint,
  reason        text,
  created_at    timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.kind::text, t.amount_paise, t.balance_after, t.reason, t.created_at
    from public.wallet_transactions t
   where t.customer_id = app.current_customer_id()
     and t.salon_id = app.current_salon_id()
     and (p_before is null or t.id < p_before)
   order by t.id desc
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;

comment on function public.my_wallet_history is
  'The customer''s own ledger, newest first, keyset-paged. Append-only, so a page can never shift under the reader. Both the customer AND the salon are named in the predicate (0057).';

revoke all on function public.my_wallet_history(integer, bigint) from public, anon;
grant execute on function public.my_wallet_history(integer, bigint) to authenticated;
