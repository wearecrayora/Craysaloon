-- 0041 Who may WRITE what, inside a salon
--
-- 0038 fixed reads: `authenticated` includes customers, so tenant scoping alone
-- let one customer read another. The write side had the same hole and a worse
-- blast radius. Found while building the owner's catalogue screens, by asserting
-- what a customer could do and watching the assertion fail:
--
--   * a CUSTOMER could add a service to the salon's menu, and **repriced an
--     existing one to 1 paisa** (the test caught exactly that);
--   * a customer could insert a `visits` row - claiming a completed visit, which
--     is what loyalty, metrics and reminders are computed from;
--   * a STAFF member could update `public.users` - including their own `role`,
--     which is privilege escalation with extra steps;
--   * an OWNER could update `salons` (status, join_code, webhook_token) and
--     rewrite `salon_branding` - flipping their own salon to `active`, changing
--     the code printed on their counter cards, or publishing a palette that
--     never passed the contrast gate. RULES 6.3 and 11 say provisioning,
--     activation and branding are Crayora's, through the console. Nothing
--     enforced it.
--
-- Not one permissive write policy in the schema mentioned a role. They were all
-- `salon_id = app.current_salon_id() and app.salon_writable(salon_id)`, which
-- answers "is this my salon" and never "am I allowed".
--
-- THE MODEL, stated once and enforced with RESTRICTIVE policies (AND-ed with
-- every permissive policy, present and future - see ADR-41):
--
--   Crayora only      salons, salon_branding
--                     -> no tenant writes at all; the console does it
--   Owner or manager  services, add_ons, service_addons, staff,
--                     staff_schedules, staff_time_off, users, message_templates
--                     -> the salon's configuration and its team
--   Staff and up      visits, booking_items, reminders
--                     -> the day's work; never a customer
--   Own rows only     customers, consents, notification_tokens, bookings
--                     -> already confined by 0038's customer_scope
--
-- SELECT is untouched: a customer still reads the menu, or they cannot book.

-- ---------------------------------------------------------------------------
-- Crayora only
-- ---------------------------------------------------------------------------
--
-- `salons` carries status, join_code and webhook_token. A salon that could
-- update its own row could switch itself on (RULES 6.3: activation is a
-- deliberate human action BY CRAYORA), change the code on cards already printed,
-- or rotate the webhook token its payments arrive on.
--
-- `salon_branding` is published by the console, which runs the contrast gate and
-- bumps the version installed apps re-theme from (§9.4). A tenant-side write
-- skips the gate and can leave a palette a customer cannot read.

do $$
declare
  v_table text;
begin
  foreach v_table in array array['salons', 'salon_branding'] loop
    execute format($f$
      create policy crayora_only_write on public.%I
        as restrictive for insert to authenticated with check (false)
    $f$, v_table);
    execute format($f$
      create policy crayora_only_change on public.%I
        as restrictive for update to authenticated using (false) with check (false)
    $f$, v_table);
    execute format($f$
      create policy crayora_only_delete on public.%I
        as restrictive for delete to authenticated using (false)
    $f$, v_table);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner or manager: the salon's configuration and its team
-- ---------------------------------------------------------------------------
--
-- `users` is in this list for the reason that makes it urgent: it holds `role`.
-- A staff member who can update that table can make themselves an owner.

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'services', 'add_ons', 'service_addons', 'staff',
    'staff_schedules', 'staff_time_off', 'users', 'message_templates'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      execute format($f$
        create policy owner_manager_write on public.%I
          as restrictive for insert to authenticated
          with check (app.current_app_role() in ('owner', 'manager'))
      $f$, v_table);
      execute format($f$
        create policy owner_manager_change on public.%I
          as restrictive for update to authenticated
          using (app.current_app_role() in ('owner', 'manager'))
          with check (app.current_app_role() in ('owner', 'manager'))
      $f$, v_table);
      execute format($f$
        create policy owner_manager_delete on public.%I
          as restrictive for delete to authenticated
          using (app.current_app_role() in ('owner', 'manager'))
      $f$, v_table);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff and up: the day's work
-- ---------------------------------------------------------------------------
--
-- A visit is the record that a service happened and was paid for. It drives
-- loyalty, reminders, dashboards and referral release. A customer inserting one
-- would be writing their own history.

do $$
declare
  v_table text;
begin
  foreach v_table in array array['visits', 'booking_items', 'reminders'] loop
    if to_regclass('public.' || v_table) is not null then
      execute format($f$
        create policy staff_write on public.%I
          as restrictive for insert to authenticated
          with check (app.current_app_role() in ('owner', 'manager', 'staff'))
      $f$, v_table);
      execute format($f$
        create policy staff_change on public.%I
          as restrictive for update to authenticated
          using (app.current_app_role() in ('owner', 'manager', 'staff'))
          with check (app.current_app_role() in ('owner', 'manager', 'staff'))
      $f$, v_table);
      execute format($f$
        create policy staff_delete on public.%I
          as restrictive for delete to authenticated
          using (app.current_app_role() in ('owner', 'manager', 'staff'))
      $f$, v_table);
    end if;
  end loop;
end;
$$;

comment on policy owner_manager_change on public.users is
  'RESTRICTIVE (0041). public.users holds `role`: without this, a staff member could update their own row and become an owner.';

comment on policy crayora_only_change on public.salons is
  'RESTRICTIVE (0041). Status, join_code and webhook_token live here. A salon cannot switch itself on, reprint its own code, or rotate the token its payments arrive on - that is Crayora''s, through the console (RULES 6.3, 11).';
