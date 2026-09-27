-- 0040 The owner's customer list (M5, screen O4)
--
-- One call returns what the screen shows: who they are, when they were last in,
-- what they hold, how many visits. In the database because the alternative is
-- the app fetching twenty customers and then twenty balances and twenty counts,
-- on salon wi-fi.
--
-- **SECURITY INVOKER, and it must stay that way.** It runs as the caller, so
-- every policy applies: an owner sees their salon, a customer sees only their own
-- row (0038), nobody sees another salon. This is also why the function lives
-- wholly in `public` and calls nothing in `app`: tenant roles have no USAGE on
-- `app` (0025, the phone_hash oracle), so reaching a helper there would force
-- this to be SECURITY DEFINER - which, with an owner that bypasses RLS, would
-- turn the list into a way around the isolation 0038 exists to enforce. A
-- convenience is not worth that, so there is no helper call here at all.
--
-- **Keyset, never OFFSET.** The cursor is (last_visit_at, id) - the exact ORDER
-- BY including its tiebreaker, so a page boundary is total and inserting a
-- customer mid-scroll cannot make a row skip or repeat. 0039's index matches it.
--
-- **Search is a name prefix, or a WHOLE phone number.** `lower(name) like 'ay%'`
-- uses the index. A number is matched on the salon's own copy of it, whole:
-- there is no partial-number search, because a phone number is only ever known
-- in full anyway - the customer reads it out - and a prefix search over numbers
-- is a lookup tool nobody asked for (RULES 4.7). A customer erased under DPDP
-- has no stored number and is therefore not findable by number, which is the
-- point of erasure.

create or replace function public.list_customers(
  p_search            text default null,
  p_cursor_last_visit timestamptz default null,
  p_cursor_id         uuid default null,
  p_limit             integer default 20
)
returns table (
  id             uuid,
  name           text,
  phone          text,
  last_visit_at  timestamptz,
  balance_paise  bigint,
  visit_count    integer,
  loyalty_points bigint,
  tier           text
)
language sql
stable
set search_path = ''
as $$
  with bounded as (
    -- A caller cannot ask for an unbounded page. 100 is the ceiling; the app
    -- asks for 20.
    select least(greatest(coalesce(p_limit, 20), 1), 100) as n,
           nullif(btrim(coalesce(p_search, '')), '') as q
  ),
  parsed as (
    select b.n, b.q,
           case
             when b.q ~ '^[0-9+ ()-]{10,}$'
               then right(regexp_replace(b.q, '[^0-9]', '', 'g'), 10)
           end as digits
      from bounded b
  ),
  matched as (
    select c.*
      from public.customers c, parsed p
     where c.deleted_at is null
       and c.status = 'active'
       and (
         p.q is null
         or (p.digits is not null and c.phone = p.digits)
         or (p.digits is null and lower(c.name) like lower(p.q) || '%')
       )
  )
  select m.id, m.name, m.phone, m.last_visit_at,
         coalesce(w.balance_paise, 0) as balance_paise,
         coalesce(v.visits, 0)::integer as visit_count,
         m.loyalty_points, m.tier
    from matched m
    left join public.wallet_accounts w on w.customer_id = m.id
    left join lateral (
      select count(*) as visits from public.visits vi where vi.customer_id = m.id
    ) v on true
   where
     p_cursor_id is null
     or case
          when p_cursor_last_visit is not null then
            m.last_visit_at < p_cursor_last_visit
            or (m.last_visit_at = p_cursor_last_visit and m.id < p_cursor_id)
            or m.last_visit_at is null
          else
            m.last_visit_at is null and m.id < p_cursor_id
        end
   order by m.last_visit_at desc nulls last, m.id desc
   limit (select n from parsed);
$$;

comment on function public.list_customers is
  'Screen O4. SECURITY INVOKER on purpose - every RLS policy applies, so an owner sees their salon and a customer sees only themselves (0038). Keyset on (last_visit_at, id), never OFFSET. Name prefix or WHOLE number; no partial-number search (RULES 4.7).';

revoke all on function public.list_customers(text, timestamptz, uuid, integer) from public, anon;
grant execute on function public.list_customers(text, timestamptz, uuid, integer) to authenticated;
