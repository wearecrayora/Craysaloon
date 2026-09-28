-- 0054 The privacy contact travels with the salon's name, correctly this time
--
-- 0053 rewrote app.resolve_join_code from memory and guessed the rate limiter's
-- signature, which broke the pre-auth read entirely - the join-flow and OTP
-- gates went red on the next run, which is exactly what they are for. This is
-- 0026's body, unchanged except for the added `grievance` object.
--
-- Why it is in the pre-auth payload at all: the consent notice must say who a
-- customer can ask and how to complain (DPDP s.5), and the notice is shown
-- BEFORE they log in - that is the only moment consent is being asked for. It is
-- a business contact, never a data principal's details.

create or replace function app.resolve_join_code(
  p_code        text,
  p_device_key  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code  text;
  v_row   record;
begin
  if not app.rate_limit_hit(
       'join_code:' || app.caller_key(p_device_key), 60, interval '1 hour') then
    raise exception 'rate limit exceeded' using errcode = '53400';
  end if;

  v_code := app.normalise_join_code(p_code);
  if v_code is null then
    return null;
  end if;

  select s.id, s.display_name, s.grievance_name, s.grievance_email, s.grievance_phone,
         b.version, b.tokens
    into v_row
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.join_code = v_code
     and s.status = 'active';

  if v_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'salon_id',         v_row.id,
    'display_name',     v_row.display_name,
    'branding_version', v_row.version,
    'branding',         v_row.tokens,
    'grievance',        jsonb_build_object(
                          'name',  v_row.grievance_name,
                          'email', v_row.grievance_email,
                          'phone', v_row.grievance_phone)
  );
end;
$$;

comment on function app.resolve_join_code is
  'The only pre-auth read in the system. Returns display name, branding and the salon''''s PRIVACY CONTACT for an ACTIVE salon; null for anything else, including a code that exists but belongs to a salon in setup - so a leaked QR cannot bind customers before the operator switches the salon on. The contact is published deliberately: the consent notice is shown before login and must say who to ask and how to complain (DPDP s.5, RULES 11.6a).';
