-- 0032 Messaging trial - Crayora pays for a salon's OTPs, on purpose, for N days
--
-- The operator can grant a salon a trial of any length. Until it ends, that
-- salon's customer OTPs are sent from CRAYORA's Message Central account - so a
-- salon can go live before it has set up its own. This is a commercial
-- concession, decided by a named human, with a reason, and audited.
--
-- It changes one rule. RULES 7.1.3 said Crayora's account is a FAULT-ONLY
-- fallback, never a normal state, and every use is alerted. A trial makes it a
-- normal, intended state for a bounded period. So trial sends are recorded
-- under their own sender value, `trial`, and are neither alerted nor counted as
-- fallbacks. A send from Crayora's account OUTSIDE a trial is still a fault,
-- and still alerts.
--
-- What a trial is NOT: a billing trial. PRD 14's "no trial - the setup fee is
-- the commitment" is about the product, and it stands. The setup fee and the
-- subscription are untouched; only OTP costs are covered.
--
-- Three decisions, stated so they can be revisited:
--
--   1. If the salon has entered its OWN account, that is used even during the
--      trial. There is no reason for Crayora to keep paying once a salon is
--      set up.
--   2. When the trial ends without the salon's own account, customers can
--      still log in: Crayora keeps sending, every send alerts again, and the
--      console flags it. Locking a salon's customers out is the worse default.
--   3. A trial is capped at 365 days, so a typo cannot grant ten years.

alter table public.subscriptions
  add column messaging_trial_ends_at timestamptz;

comment on column public.subscriptions.messaging_trial_ends_at is
  'Until this moment, the salon''s customer OTPs are sent - intentionally - from Crayora''s Message Central account (0032). Null or past means no trial. Set only by app_admin.set_messaging_trial.';

-- ---------------------------------------------------------------------------
-- The one way to grant, extend or end a trial
-- ---------------------------------------------------------------------------

create or replace function app_admin.set_messaging_trial(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_days           integer,
  p_reason         text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before timestamptz;
  v_after  timestamptz;
begin
  perform app_admin.assert_admin(p_actor_admin_id);

  if p_days is null or p_days < 0 then
    raise exception 'app_admin: trial days must be zero or more (zero ends the trial now)';
  end if;
  if p_days > 365 then
    raise exception 'app_admin: a messaging trial can be at most 365 days - this one asked for %', p_days;
  end if;

  -- Every day of trial is money Crayora spends on a salon's behalf, so the
  -- reason is required, the same way a suspension's is.
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'app_admin: a messaging trial needs a reason - Crayora pays for every OTP sent under it';
  end if;

  select messaging_trial_ends_at into v_before
    from public.subscriptions where salon_id = p_salon_id
   for update;

  if not found then
    raise exception 'app_admin: no subscription for salon %', p_salon_id;
  end if;

  -- Zero ends it now rather than setting null, so "a trial existed and was
  -- ended" stays distinguishable from "there never was one".
  v_after := now() + make_interval(days => p_days);

  update public.subscriptions
     set messaging_trial_ends_at = v_after, updated_at = now()
   where salon_id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id,
    case when p_days = 0 then 'messaging_trial.ended' else 'messaging_trial.granted' end,
    'subscriptions', p_salon_id::text, p_reason,
    jsonb_build_object('messaging_trial_ends_at', v_before),
    jsonb_build_object('messaging_trial_ends_at', v_after, 'days', p_days));

  return v_after;
end;
$$;

-- ---------------------------------------------------------------------------
-- `trial` as a sender, distinct from a `platform` fallback
-- ---------------------------------------------------------------------------

alter table public.otp_challenges drop constraint otp_challenges_sender_check;
alter table public.otp_challenges
  add constraint otp_challenges_sender_check
  check (sender in ('salon', 'trial', 'platform'));

comment on column public.otp_challenges.sender is
  'salon = the salon''s own account. trial = Crayora''s account, intentionally, under a messaging trial (0032) - not alerted. platform = Crayora''s account as a FAULT fallback - always alerted (RULES 7.1.3).';

-- ---------------------------------------------------------------------------
-- otp_begin reports whether a trial is running
-- ---------------------------------------------------------------------------

create or replace function public.otp_begin(p_phone text, p_device_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   bytea;
  v_sender jsonb;
  v_caller text;
  v_trial  boolean;
begin
  v_hash := app.phone_hash(p_phone);

  v_sender := app.resolve_otp_sender(p_phone);
  if not (v_sender ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'no_salon_context');
  end if;

  if not app.rate_limit_hit(
       'otp_send_phone:' || encode(v_hash, 'hex'), 3, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  -- The customer's address, passed by the Edge Function - not
  -- app.caller_key(), which would see the function's own (0030).
  v_caller := coalesce(nullif(trim(coalesce(p_device_key, '')), ''), 'unknown');
  if not app.rate_limit_hit(
       'otp_send_caller:' || v_caller, 10, interval '10 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  select coalesce(messaging_trial_ends_at > now(), false) into v_trial
    from public.subscriptions
   where salon_id = (v_sender ->> 'salon_id')::uuid;

  return jsonb_build_object(
    'ok', true,
    'salon_id', v_sender ->> 'salon_id',
    'source', v_sender ->> 'source',
    'mobile', app.canonical_phone(p_phone),
    'country_code', '91',
    'messaging_trial_active', coalesce(v_trial, false)
  );
end;
$$;

-- 0020: a function added to app_admin is PUBLIC-executable until this runs.
select app_admin.close_privileges();
