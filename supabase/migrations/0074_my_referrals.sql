-- 0074 What the Refer & Earn screen reads
--
-- C11 shows the customer their code and what has happened to it: who has
-- claimed it and is yet to visit, and who has earned them a reward. Those are
-- OTHER customers' rows, so this cannot be a plain table read - the restrictive
-- customer-scope policy (0038) exists precisely to stop one customer reading
-- another's, and it should keep doing so.
--
-- So: a definer function that returns **no identifying detail about the
-- friend**. A count and a status is everything the screen needs, and it is the
-- most a referrer is entitled to. Whether Farah has been to the salon is
-- Farah's business, not the business of whoever gave her a code.

create or replace function public.my_referrals()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_pending  integer;
  v_rewarded integer;
  v_earned   bigint;
begin
  if v_salon is null or v_customer is null then
    raise exception 'my_referrals: no customer in this session' using errcode = '42501';
  end if;

  select
    count(*) filter (where r.status = 'pending_visit')::integer,
    count(*) filter (where r.status = 'rewarded')::integer,
    coalesce(sum(r.reward_paise) filter (where r.status = 'rewarded'), 0)
    into v_pending, v_rewarded, v_earned
    from public.referrals r
   where r.salon_id = v_salon and r.referrer_id = v_customer;

  return jsonb_build_object(
    -- Signed up, not yet been in. The screen says "waiting for their first
    -- visit", which is true and is also the nudge.
    'pending', coalesce(v_pending, 0),
    'rewarded', coalesce(v_rewarded, 0),
    'earned_paise', coalesce(v_earned, 0));
end;
$$;

comment on function public.my_referrals is
  'The referrer''s own summary: how many friends have claimed the code, how many have earned a reward, and how much. Deliberately a COUNT and no names - whether a friend has been to the salon is the friend''s business, not the business of whoever gave them a code.';

revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;
