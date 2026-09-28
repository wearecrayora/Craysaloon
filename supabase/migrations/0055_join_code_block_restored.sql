-- 0055 Restoring the blocked-salon check I dropped in 0053/0054
--
-- 0053 rebuilt app.resolve_join_code from 0026's body to add the privacy
-- contact. 0033 had since added ONE line to that function - a blocked salon
-- resolves to nothing, exactly like an unknown code - and rebuilding from the
-- older text silently removed it. A salon whose messaging was cut off would
-- have started accepting new customers again.
--
-- The messaging-access gate caught it on the next run, which is the system
-- working. The lesson is cheaper than the bug: **never reconstruct a function
-- from an older migration.** Read the live definition
-- (`pg_get_functiondef`) or the newest migration that touched it, and diff.
--
-- This is 0033's body with 0053's `grievance` object, and nothing else.

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
     and s.status = 'active'
     -- 0033, restored in 0055: identical to an unknown code, so no oracle.
     and not app.salon_blocked(s.id);

  if v_row.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'salon_id',         v_row.id,
    'display_name',     v_row.display_name,
    'branding_version', v_row.version,
    'branding',         v_row.tokens,
    -- Published on purpose: the consent notice is shown BEFORE login and must
    -- say who to ask and how to complain (DPDP s.5, RULES 11.6a). A business
    -- contact, never a data principal''s details.
    'grievance',        jsonb_build_object(
                          'name',  v_row.grievance_name,
                          'email', v_row.grievance_email,
                          'phone', v_row.grievance_phone)
  );
end;
$$;

comment on function app.resolve_join_code is
  'The only pre-auth read in the system. Returns display name, branding and the salon''s privacy contact for an ACTIVE, non-blocked salon; null for anything else - a salon in setup, a blocked one, or an unknown code all look identical, so this is no oracle (0033, 0055).';
