-- 0088 A salon with no subscription row has the default plan's features.
--
-- 0087 answered "no" for every feature when a salon had no subscription row.
-- Every salon the console provisions has one, so in production that branch was
-- dead - but a missing row is a data fault, and a data fault should not switch
-- an owner's dashboard off. The default plan is 'starter', the column default.

create or replace function app.salon_has_feature(p_salon uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select f.enabled from public.feature_flags f
      where f.salon_id = p_salon and f.flag = p_feature),
    p_feature = any(app.plan_features(coalesce(
      (select s.plan from public.subscriptions s where s.salon_id = p_salon),
      'starter'))))
$$;

revoke all on function app.salon_has_feature(uuid, text) from public, anon, authenticated;
