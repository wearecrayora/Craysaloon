-- 0093 The salon's branding reaches its customers' devices (PRD 20).
--
-- Two gaps from the M13 release audit, both "the salon's brand stops at the
-- console":
--
-- 1. my_branding(): a bound app re-reads its salon's branding ("branding
--    published in the console reaches the app on next open"). Until now the app
--    stored the salon's branding once, at join, and never asked again: a salon
--    that republished its colours or logo kept its old look on every phone that
--    had already joined. The join-code lookup cannot serve a bound user - it is
--    anonymous and rate-limited by design - so this is the signed-in
--    counterpart: the caller's OWN salon only, from the token, never a
--    parameter.
--
--    It returns the privacy contact too, because the app stores the two
--    together (the consent notice must name someone even offline) and a
--    contact changed in the console should reach the phone the same way.
--
-- 2. salon_push_brand(): what dispatch-notifications puts on a push ("every
--    push carries the salon's name, logo and colour"). It takes a salon id, so
--    it is service_role ONLY - granted to authenticated it would describe any
--    salon to anyone.

create or replace function public.my_branding()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'salon_id',     s.id,
           'display_name', s.display_name,
           'version',      coalesce(b.version, 0),
           'tokens',       b.tokens,
           'grievance',    jsonb_build_object('name',  s.grievance_name,
                                              'email', s.grievance_email,
                                              'phone', s.grievance_phone))
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.id = app.current_salon_id()
$$;

comment on function public.my_branding() is
  'The signed-in caller''s own salon branding and privacy contact (0093). From the token, never a parameter, so it can only ever return the caller''s salon.';

revoke all on function public.my_branding() from public, anon;
grant execute on function public.my_branding() to authenticated;

-- The published LIGHT primary: it tints the notification's small icon and app
-- name on a light shade, and it has already passed the contrast gate at
-- publish. The logo only when it is a real https URL - a placeholder must not
-- reach FCM, which would reject the whole message over a bad image.
create or replace function public.salon_push_brand(p_salon_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'name',  s.display_name,
           'color', nullif(coalesce(b.tokens #>> '{resolved,light,color,primary}',
                                    b.tokens #>> '{brand,light,primary}'), ''),
           'logo',  case when b.tokens #>> '{assets,logo}' like 'https://%'
                         then b.tokens #>> '{assets,logo}' end)
    from public.salons s
    left join public.salon_branding b on b.salon_id = s.id
   where s.id = p_salon_id
$$;

comment on function public.salon_push_brand(uuid) is
  'Name, colour and logo for a push from this salon (0093). service_role only: it takes a salon id, so any wider grant would describe any salon to anyone.';

revoke all on function public.salon_push_brand(uuid) from public, anon, authenticated;
grant execute on function public.salon_push_brand(uuid) to service_role;
