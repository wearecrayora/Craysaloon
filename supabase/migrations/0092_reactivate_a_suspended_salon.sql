-- 0092 A salon suspended by hand can be brought back - by a person, on purpose.
--
-- set_salon_status moves a salon to grace or suspended and, by design, never to
-- active (admin-plane gate: "activate_salon is the only door"). activate_salon
-- opens only from `setup`. Between them, a salon an operator suspended - for a
-- fraud review, a dispute, a mistake - could never be returned to service.
-- The billing gate (0087) had to fake it with a raw UPDATE, which is how the
-- gap was found.
--
-- RULES 6.3 holds: this is a deliberate human action, not a payment or a timer.
-- It is super-admin only, reason-required, audited, and it refuses:
--   * a salon in setup     - that is activate_salon's job, with its checks;
--   * a purged salon        - nothing personal is left to come back to (0090);
--   * a salon whose subscription has lapsed - reactivating it would change
--     nothing a customer can see, and would hide the real problem. Record the
--     payment first (0087); then this.

create or replace function app_admin.reactivate_salon(
  p_actor_admin_id uuid,
  p_salon_id       uuid,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salon record;
begin
  perform app_admin.assert_super_admin(p_actor_admin_id);

  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'app_admin: reactivating a salon needs a reason - why was the suspension lifted?';
  end if;

  select s.id, s.status, s.purged_at into v_salon
    from public.salons s where s.id = p_salon_id for update;

  if v_salon.id is null then
    raise exception 'app_admin: no salon %', p_salon_id;
  end if;
  if v_salon.purged_at is not null then
    raise exception 'app_admin: this salon was purged - it cannot be reactivated';
  end if;
  if v_salon.status = 'setup' then
    raise exception 'app_admin: a salon in setup is activated, not reactivated - use Activate';
  end if;
  if v_salon.status = 'active' then
    return;
  end if;
  if not app.billing_open(p_salon_id) then
    raise exception
      'app_admin: this salon''s subscription has lapsed (%). Record the payment first - '
      'reactivating would not let it take bookings anyway', app.billing_state(p_salon_id);
  end if;

  update public.salons set status = 'active', updated_at = now() where id = p_salon_id;

  perform app_admin.audit(
    p_salon_id, p_actor_admin_id, 'salon.reactivated', 'salons', p_salon_id::text, p_reason,
    jsonb_build_object('status', v_salon.status), jsonb_build_object('status', 'active'));
end;
$$;

comment on function app_admin.reactivate_salon is
  'Lifts a manual grace or suspension (0092). Super-admin, reason-required, audited. Refuses setup (use activate_salon), purged salons, and a lapsed subscription.';

select app_admin.close_privileges();
