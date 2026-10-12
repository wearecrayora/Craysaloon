-- 0097 The owner sets bonus expiry, in the app (RULES 5.3.3; PRD 4.2: "Not bonus
-- expiry - that is the owner's, set in the app").
--
-- The mechanism was always there: app.wallet_bonus_for reads
-- wallet_rule.bonus_expiry_days (default 180) and every top-up captures it onto
-- the bonus lot at issue (RULES 5.3.4) - so a change here affects only credit
-- issued afterwards. What was missing was the owner's way to set it: nothing
-- called it, so every salon ran on the default.
--
-- And a second bug, waiting for the first to be fixed: app_admin.set_salon_rules
-- REPLACED wallet_rule with the console's three keys. Once an owner chose an
-- expiry, the next console save would have reset it to 180 without a word.
-- It now merges, keeping the owner's key.

create or replace function public.set_bonus_expiry(p_days integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon  uuid := app.current_salon_id();
  v_role   text := app.current_app_role();
  v_before jsonb;
begin
  -- The OWNER's setting - not a manager's, not staff (RULES 5.3.3).
  if v_salon is null or v_role is distinct from 'owner' then
    raise exception 'set_bonus_expiry: only the salon''s owner sets bonus expiry'
      using errcode = '42501';
  end if;
  -- 0 = bonus never expires. Otherwise a month to two years: shorter is a
  -- bonus nobody can use, longer is a liability the salon forgets it carries.
  if p_days is null or not (p_days = 0 or p_days between 30 and 730) then
    raise exception 'set_bonus_expiry: % is not 0 (never) or 30 to 730 days', p_days
      using errcode = '22023';
  end if;
  if not app.salon_writable(v_salon) then
    return jsonb_build_object('ok', false, 'reason', 'salon_unavailable');
  end if;

  select s.wallet_rule -> 'bonus_expiry_days' into v_before
    from public.salons s where s.id = v_salon for update;

  update public.salons
     set wallet_rule = coalesce(wallet_rule, '{}'::jsonb)
                       || jsonb_build_object('bonus_expiry_days', p_days),
         updated_at  = now()
   where id = v_salon;

  -- Audited as the owner's act: what it was, what it became, who.
  insert into public.audit_log (salon_id, actor_user_id, actor_kind, action, entity,
                                entity_id, before_state, after_state)
  values (v_salon, auth.uid(), 'owner', 'salon.bonus_expiry_set', 'salons', v_salon::text,
          jsonb_build_object('bonus_expiry_days', v_before),
          jsonb_build_object('bonus_expiry_days', p_days));

  return jsonb_build_object('ok', true, 'bonus_expiry_days', p_days);
end;
$$;

comment on function public.set_bonus_expiry(integer) is
  'The owner sets how long BONUS credit lasts (0 = never; 30-730 days), captured onto each lot at issue. Paid credit has no expiry and no field for one (RULES 5.3.3, 0097).';

revoke all on function public.set_bonus_expiry(integer) from public, anon;
grant execute on function public.set_bonus_expiry(integer) to authenticated;

-- The console's rules save keeps the owner's expiry.
do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('app_admin.set_salon_rules(uuid, uuid, jsonb)'::regprocedure)
    into strict v_def;
  v_new := replace(v_def,
    $old$set wallet_rule  = coalesce(p_rules -> 'wallet_rule', wallet_rule),$old$,
    $new$set wallet_rule  = case
                            when p_rules ? 'wallet_rule'
                              -- the console's keys, plus the OWNER's expiry,
                              -- which the console never sends (0097)
                              then (p_rules -> 'wallet_rule')
                                   || jsonb_strip_nulls(jsonb_build_object(
                                        'bonus_expiry_days', wallet_rule -> 'bonus_expiry_days'))
                            else wallet_rule
                          end,$new$);
  if v_new = v_def then
    raise exception '0097: set_salon_rules did not contain the wallet_rule assignment it patches';
  end if;
  execute v_new;
end;
$patch$;

select app_admin.close_privileges();
