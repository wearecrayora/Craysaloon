-- 0042 A visit is written by the server, not by hands
--
-- 0041 put visits, booking_items and reminders in a "staff and up" bucket. That
-- was the wrong line, and the gate caught it in the same session: the assertion
-- said *"a visit is not written by hand even by an owner"* and failed against my
-- own migration.
--
-- The test is right. A visit is the record that a service happened and was paid
-- for, and it is what loyalty, reminders, dashboards and referral release are
-- computed from. It has exactly one legitimate origin: `app.mark_visit_complete`
-- (M6), a SECURITY DEFINER function that also posts the ledger effects in the
-- same transaction (ARCHITECTURE 6.4, 10.3). The same holds for `booking_items`,
-- which exist to SNAPSHOT price and duration - a hand-written row is a snapshot
-- of nothing - and for `reminders`, which the reminder engine generates under a
-- unique index that stops duplicates (§6.6).
--
-- "Staff may write it" sounds conservative and is not: it means a phone with a
-- staff session can write history directly, skipping the function that makes the
-- money and the loyalty consistent with it. The server functions bypass RLS
-- because they are SECURITY DEFINER, so closing the tables costs nothing that
-- should be possible.

do $$
declare
  v_table text;
begin
  foreach v_table in array array['visits', 'booking_items', 'reminders'] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('drop policy if exists staff_write on public.%I', v_table);
      execute format('drop policy if exists staff_change on public.%I', v_table);
      execute format('drop policy if exists staff_delete on public.%I', v_table);

      execute format($f$
        create policy server_only_write on public.%I
          as restrictive for insert to authenticated with check (false)
      $f$, v_table);
      execute format($f$
        create policy server_only_change on public.%I
          as restrictive for update to authenticated using (false) with check (false)
      $f$, v_table);
      execute format($f$
        create policy server_only_delete on public.%I
          as restrictive for delete to authenticated using (false)
      $f$, v_table);
    end if;
  end loop;
end;
$$;

comment on policy server_only_write on public.visits is
  'RESTRICTIVE (0042). A visit comes from app.mark_visit_complete, which posts the ledger effects in the same transaction. No device writes one directly - not a customer, not a stylist, not the owner.';

-- The write model as it now stands, in one place:
--
--   Crayora only   salons, salon_branding
--   Server only    visits, booking_items, reminders
--   Owner/manager  services, add_ons, service_addons, staff, staff_schedules,
--                  staff_time_off, users, message_templates
--   Own rows only  customers, consents, notification_tokens, bookings
--
-- SELECT is untouched throughout: a customer still reads the menu (0038, 0041).
