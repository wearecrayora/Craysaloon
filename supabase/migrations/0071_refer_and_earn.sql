-- 0071 M9: Refer & Earn, and the fifth ledger caller
--
-- `app.referral_release_reward` has been named in RULES 5.2 since M1 and left
-- unbuilt on purpose - "a function that moves money before the rule justifying
-- it exists is worse than a missing one" (PHASES, M7). The rule exists now, and
-- so does the event it keys off: a visit can finally be PAID (0069).
--
-- The three rules, and where each is enforced:
--
--   * **a reward releases only after a completed, PAID first visit** (RULES 10)
--     - `visits.payment_status = 'paid'`, and it must be the referred
--       customer's FIRST such visit
--   * **self-referral is rejected by a constraint**, not by code - the table has
--     carried `referrals_no_self_referral` since M1
--   * **a cancelled or refunded visit releases nothing** - a cancelled booking
--     never produces a visit, and an unpaid one never reaches the condition
--
-- **`reward_rule` shape, defined here and written by the console in the same
-- change:** `{referrer_paise, referred_paise}`. 0058 is what happens when the
-- two are defined separately - the console wrote one shape, the ledger read
-- another, and the whole feature silently did nothing.
--
-- **The reward is BONUS credit**, not paid. Paid credit is money a customer
-- handed over and it never expires (RULES 5.3.3); a referral reward is
-- promotional credit the salon issued, which is exactly what a bonus lot is.
-- It carries the salon's own bonus expiry, captured onto the lot at issue.

-- ---------------------------------------------------------------------------
-- 1. A customer's own code
-- ---------------------------------------------------------------------------

create or replace function app.new_referral_code(p_salon_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- The same unambiguous alphabet as the join code (PRD 6.3): no 0/O, no 1/I/L.
  -- A referral code is read aloud in a salon and typed by someone else, which
  -- is precisely the situation that alphabet exists for.
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code     text;
  v_try      integer := 0;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;

    exit when not exists (
      select 1 from public.referrals r
       where r.salon_id = p_salon_id and r.code = v_code);

    v_try := v_try + 1;
    if v_try > 20 then
      -- 31^6 is about 900 million per salon. Twenty collisions means something
      -- is wrong with the random source, not with luck.
      raise exception 'new_referral_code: could not find a free code';
    end if;
  end loop;

  return v_code;
end;
$$;

create or replace function public.my_referral_code()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_code     text;
  v_rule     jsonb;
begin
  if v_salon is null or v_customer is null then
    raise exception 'my_referral_code: no customer in this session' using errcode = '42501';
  end if;

  -- One code per customer per salon, reused forever. A code that changes is a
  -- code somebody has already given to a friend and can no longer honour.
  select r.code into v_code
    from public.referrals r
   where r.salon_id = v_salon and r.referrer_id = v_customer
   order by r.created_at
   limit 1;

  if v_code is null then
    v_code := app.new_referral_code(v_salon);
    insert into public.referrals (salon_id, referrer_id, code, status)
    values (v_salon, v_customer, v_code, 'invited');
  end if;

  select s.reward_rule into v_rule from public.salons s where s.id = v_salon;
  v_rule := coalesce(v_rule, '{}'::jsonb);

  return jsonb_build_object(
    'code', v_code,
    -- What the screen must state, from the server, so it cannot promise an
    -- amount the ledger would refuse.
    'referrer_paise', coalesce((v_rule ->> 'referrer_paise')::bigint, 0),
    'referred_paise', coalesce((v_rule ->> 'referred_paise')::bigint, 0));
end;
$$;

comment on function public.my_referral_code is
  'The customer''s own referral code, created once and reused forever - a code that changes is one somebody has already given to a friend. Returns the reward amounts from the salon''s rule, so the screen states what the ledger will actually pay.';

revoke all on function public.my_referral_code() from public, anon;
grant execute on function public.my_referral_code() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Claiming one
-- ---------------------------------------------------------------------------

create or replace function public.claim_referral(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon    uuid := app.current_salon_id();
  v_customer uuid := app.current_customer_id();
  v_code     text := upper(btrim(coalesce(p_code, '')));
  v_referral record;
  v_rule     jsonb;
begin
  if v_salon is null or v_customer is null then
    raise exception 'claim_referral: no customer in this session' using errcode = '42501';
  end if;

  if exists (select 1 from public.referrals r
              where r.salon_id = v_salon and r.referred_customer_id = v_customer) then
    -- The unique index would refuse it anyway. Answering plainly is kinder than
    -- a constraint violation, and the answer is the same either way.
    return jsonb_build_object('ok', false, 'reason', 'already_referred');
  end if;

  -- A referral is for a NEW customer. Someone who has already been in and paid
  -- cannot be referred afterwards by a friend who wants the reward.
  if exists (select 1 from public.visits v
              where v.customer_id = v_customer and v.payment_status = 'paid') then
    return jsonb_build_object('ok', false, 'reason', 'not_a_new_customer');
  end if;

  select r.id, r.referrer_id, r.status into v_referral
    from public.referrals r
   where r.salon_id = v_salon and r.code = v_code
     and r.referred_customer_id is null
   order by r.created_at
   limit 1;

  if v_referral.id is null then
    return jsonb_build_object('ok', false, 'reason', 'unknown_code');
  end if;

  if v_referral.referrer_id = v_customer then
    -- The table's check constraint refuses this too. Two refusals, on purpose:
    -- self-referral is the first thing anybody tries.
    return jsonb_build_object('ok', false, 'reason', 'self_referral');
  end if;

  select s.reward_rule into v_rule from public.salons s where s.id = v_salon;
  v_rule := coalesce(v_rule, '{}'::jsonb);

  update public.referrals
     set referred_customer_id = v_customer,
         status = 'pending_visit',
         -- Captured at CLAIM time, like bonus terms on a lot: changing the rule
         -- tomorrow cannot change what somebody was already promised.
         reward_paise = coalesce((v_rule ->> 'referrer_paise')::bigint, 0)
   where id = v_referral.id;

  return jsonb_build_object('ok', true, 'status', 'pending_visit',
                            'referred_paise',
                            coalesce((v_rule ->> 'referred_paise')::bigint, 0));
end;
$$;

comment on function public.claim_referral is
  'Attaches a new customer to a referral code. Refuses self-referral (twice - here and by the table''s constraint), a second referrer (unique index), and anyone who has already paid for a visit: a referral is for a new customer, not a retrospective claim on an existing one.';

revoke all on function public.claim_referral(text) from public, anon;
grant execute on function public.claim_referral(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Caller 4 of five: the release
-- ---------------------------------------------------------------------------

create or replace function app.referral_release_reward(p_referral_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref     record;
  v_rule    jsonb;
  v_days    integer;
  v_expires timestamptz;
  v_referred_paise bigint;
  v_visit   uuid;
  v_lot     uuid;
begin
  select r.id, r.salon_id, r.referrer_id, r.referred_customer_id, r.status, r.reward_paise
    into v_ref
    from public.referrals r
   where r.id = p_referral_id
   for update;

  if v_ref.id is null then
    raise exception 'referral_release_reward: no such referral';
  end if;

  -- Idempotent through the status transition. Automation D can run twice, the
  -- sweep can overlap, a webhook can redeliver: only one of them pays.
  if v_ref.status = 'rewarded' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if v_ref.status <> 'pending_visit' or v_ref.referred_customer_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_pending');
  end if;

  -- THE RULE (RULES 10): a completed, PAID first visit. Not a booking, not a
  -- completed-but-unpaid visit, and not a cancelled one - a cancelled booking
  -- never produces a visit row at all.
  select v.id into v_visit
    from public.visits v
   where v.customer_id = v_ref.referred_customer_id
     and v.payment_status = 'paid'
   order by v.completed_at
   limit 1;

  if v_visit is null then
    return jsonb_build_object('ok', false, 'reason', 'no_paid_visit');
  end if;

  select s.reward_rule into v_rule from public.salons s where s.id = v_ref.salon_id;
  v_rule := coalesce(v_rule, '{}'::jsonb);
  v_referred_paise := coalesce((v_rule ->> 'referred_paise')::bigint, 0);

  -- Bonus credit, with the salon's own expiry captured onto the lot at issue.
  -- Promotional credit the salon issued is exactly what a bonus lot is; paid
  -- credit is money a customer handed over, and that never expires.
  v_days := coalesce((v_rule ->> 'bonus_expiry_days')::integer, 180);
  v_expires := case when v_days > 0 then now() + make_interval(days => v_days) end;

  if coalesce(v_ref.reward_paise, 0) > 0 then
    insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
    values (v_ref.salon_id, v_ref.referrer_id, 'bonus',
            v_ref.reward_paise, v_ref.reward_paise, v_expires)
    returning id into v_lot;

    perform app.wallet_post(
      v_ref.salon_id, v_ref.referrer_id, 'credit_referral', v_ref.reward_paise,
      v_lot, null, v_visit, 'referral reward', null);
  end if;

  if v_referred_paise > 0 then
    insert into public.wallet_lots
      (salon_id, customer_id, kind, amount_paise, remaining_paise, expires_at)
    values (v_ref.salon_id, v_ref.referred_customer_id, 'bonus',
            v_referred_paise, v_referred_paise, v_expires)
    returning id into v_lot;

    perform app.wallet_post(
      v_ref.salon_id, v_ref.referred_customer_id, 'credit_referral', v_referred_paise,
      v_lot, null, v_visit, 'referral reward', null);
  end if;

  update public.referrals
     set status = 'rewarded', completed_visit_id = v_visit, rewarded_at = now()
   where id = p_referral_id;

  -- Both are told (PRD Automation D). The intent is recorded here; the ladder
  -- decides how it actually reaches them.
  perform app.notify(v_ref.salon_id, v_ref.referrer_id, 'referral_rewarded',
                     'transactional', 'referral_rewarded',
                     jsonb_build_object('amount_paise', v_ref.reward_paise));
  if v_referred_paise > 0 then
    perform app.notify(v_ref.salon_id, v_ref.referred_customer_id, 'referral_rewarded',
                       'transactional', 'referral_rewarded',
                       jsonb_build_object('amount_paise', v_referred_paise));
  end if;

  return jsonb_build_object('ok', true, 'already', false,
                            'referrer_paise', v_ref.reward_paise,
                            'referred_paise', v_referred_paise,
                            'visit_id', v_visit);
end;
$$;

comment on function app.referral_release_reward is
  'Caller 4 of five (RULES 5.2). Releases BOTH rewards, once, after the referred customer''s first completed PAID visit. Idempotent through the status transition, so an overlapping sweep or a replayed checkout pays once. Bonus-kind credit with the salon''s own expiry captured onto the lot.';

-- ---------------------------------------------------------------------------
-- 4. Automation D's trigger: a visit that just became paid
-- ---------------------------------------------------------------------------

create or replace function app.release_due_referrals(p_salon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref    record;
  v_result jsonb;
  v_paid   integer := 0;
begin
  for v_ref in
    select r.id
      from public.referrals r
     where r.salon_id = p_salon_id
       and r.status = 'pending_visit'
       and r.referred_customer_id is not null
       and exists (
         select 1 from public.visits v
          where v.customer_id = r.referred_customer_id
            and v.payment_status = 'paid')
     -- Overlapping sweeps must not both pay. The status transition inside the
     -- release is the real guard; this keeps them from queueing behind it.
     for update skip locked
  loop
    v_result := app.referral_release_reward(v_ref.id);
    if v_result ->> 'ok' = 'true' and coalesce(v_result ->> 'already', 'false') <> 'true' then
      v_paid := v_paid + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'released', v_paid);
end;
$$;

comment on function app.release_due_referrals is
  'Automation D, per salon. Sweeps rather than firing inline from checkout on purpose: a referral reward that depends on a checkout succeeding would be lost the one time a checkout half-failed, and the sweep runs every minute anyway.';

select app_admin.close_privileges();
