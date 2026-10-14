-- 0111 Stylists get the salon's push notifications too.
--
-- Decided 14 Oct 2026: 0108 told owners and managers when a customer booked,
-- cancelled, chose to pay at the counter or paid a bill online. Stylists are
-- the ones standing at the chair, so they are told as well. Every active login
-- of the salon with a live device is told; a login the owner has switched off
-- is told nothing - that is the line the gate now holds.

create or replace function app.notify_staff(p_salon_id uuid, p_purpose text, p_template_key text, p_params jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_locale text;
  v_count  integer;
begin
  select coalesce(s.languages[1], 'en') into v_locale from public.salons s where s.id = p_salon_id;

  -- Owner, manager and stylist alike (0111) - but only an ACTIVE login: one
  -- the owner switched off hears nothing more about the salon's customers.
  insert into public.notifications
    (salon_id, user_id, purpose, category, locale, template_key, params, status)
  select p_salon_id, u.id, p_purpose, 'transactional', coalesce(v_locale, 'en'),
         p_template_key, coalesce(p_params, '{}'::jsonb), 'pending'
    from public.users u
   where u.salon_id = p_salon_id
     and u.active
     and u.role in ('owner', 'manager', 'staff')
     and exists (select 1 from public.notification_tokens nt
                  where nt.user_id = u.id and nt.dead_at is null);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function app.notify_staff(uuid, text, text, jsonb) from public, anon, authenticated;
