-- RELEASE GATE: who may WRITE what, inside a salon
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- 0038 closed the read side. This is the write side, which had the same hole and
-- a worse blast radius: a customer repriced a service to 1 paisa, a staff member
-- could have made themselves an owner, and an owner could have switched their own
-- salon on. Every one of those was allowed by a policy that asked "is this my
-- salon" and never "am I allowed" (0041).
--
-- Two halves, as with the read gate:
--   * catalogue   - every tenant-writable table is covered by a role-aware
--                   RESTRICTIVE policy, or is named here as customer-writable
--                   on purpose. A table added next year fails until it is one or
--                   the other.
--   * behavioural - the escalations themselves, attempted as each role.

select plan(24);

-- ---------------------------------------------------------------------------
-- Catalogue: nothing tenant-writable is left role-blind
-- ---------------------------------------------------------------------------

select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      -- a tenant can write it...
      and exists (
        select 1 from pg_policy p
         where p.polrelid = c.oid and p.polpermissive and p.polcmd in ('a', 'w', 'd')
           and 'authenticated' = any(select rolname from pg_roles where oid = any(p.polroles))
      )
      -- ...and nothing restrictive says who may.
      and not exists (
        select 1 from pg_policy p
         where p.polrelid = c.oid and not p.polpermissive
           and (pg_get_expr(p.polqual, p.polrelid) like '%current_app_role%'
             or pg_get_expr(p.polwithcheck, p.polrelid) like '%current_app_role%'
             or pg_get_expr(p.polwithcheck, p.polrelid) = 'false')
      )
      -- Written by their owner, by design, and confined to their own rows by
      -- 0038: a customer edits their own profile, their own consent, their own
      -- device tokens, and books their own appointment.
      and c.relname not in ('customers', 'consents', 'notification_tokens', 'bookings')),
  '',
  'every tenant-writable table says WHO may write it, or is a documented own-rows table'
);

select is(
  (select count(*)::int from pg_policy
    where polname in ('crayora_only_write', 'crayora_only_change', 'crayora_only_delete',
                      'owner_manager_write', 'owner_manager_change', 'owner_manager_delete',
                      'staff_write', 'staff_change', 'staff_delete')
      and polpermissive),
  0,
  'every write-scope policy is RESTRICTIVE - a permissive one would grant, not confine'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('eeeeeeee-aaaa-4000-8000-00000000000f'),   -- the owner
  ('eeeeeeee-aaaa-4000-8000-00000000000b'),   -- a staff member
  ('eeeeeeee-aaaa-4000-8000-00000000000c');   -- a customer

insert into public.platform_admins (id, email, name, is_super, active)
values ('eeeeeeee-aaaa-4000-8000-00000000000f', 'write@crayora.test', 'Write Op', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status, activated_by, activated_at)
values ('eeeeeeee-0000-4000-8000-000000000001', 'Write Salon Ltd', 'Write Salon',
        'CRAY-WWWQQQ', 'active', 'eeeeeeee-aaaa-4000-8000-00000000000f', now());

insert into public.users (id, salon_id, auth_user_id, role, name, phone, phone_hash, active)
values
  ('eeeeeeee-5555-4000-8000-00000000000f', 'eeeeeeee-0000-4000-8000-000000000001',
   'eeeeeeee-aaaa-4000-8000-00000000000f', 'owner', 'Write Owner', '9877700009',
   app.phone_hash('9877700009'), true),
  ('eeeeeeee-5555-4000-8000-00000000000a', 'eeeeeeee-0000-4000-8000-000000000001',
   null, 'staff', 'Write Stylist', '9877700008', app.phone_hash('9877700008'), true);

insert into public.services (id, salon_id, name, price_paise, duration_minutes, active)
values ('eeeeeeee-2222-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'Haircut', 40000, 30, true);

insert into public.customers (id, salon_id, auth_user_id, name, phone, phone_hash)
values ('eeeeeeee-1111-4000-8000-00000000000c', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-aaaa-4000-8000-00000000000c', 'Write Customer', '9877700001',
        app.phone_hash('9877700001'));

insert into public.bookings (id, salon_id, customer_id, starts_at, ends_at, status)
values ('eeeeeeee-3333-4000-8000-000000000001', 'eeeeeeee-0000-4000-8000-000000000001',
        'eeeeeeee-1111-4000-8000-00000000000c', now(), now() + interval '30 min', 'confirmed');

-- ---------------------------------------------------------------------------
-- As the OWNER: the salon's configuration is theirs; Crayora's is not
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-aaaa-4000-8000-00000000000f",'
  '"app_role":"owner",'
  '"salon_id":"eeeeeeee-0000-4000-8000-000000000001"}',
  true
);

select lives_ok(
  $$insert into public.services (salon_id, name, price_paise, duration_minutes, active)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'Beard trim', 20000, 20, true)$$,
  'an owner can add a service - the catalogue is theirs to run'
);

select lives_ok(
  $$update public.services set price_paise = 45000
     where id = 'eeeeeeee-2222-4000-8000-000000000001'$$,
  'and reprice one'
);

select lives_ok(
  $$insert into public.staff (salon_id, name, active)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'New Stylist', true)$$,
  'and hire'
);

-- THE PAYLOAD THE APP ACTUALLY SENDS: no salon_id at all. It used to fail with a
-- not-null violation, which no test noticed because every test named the salon
-- explicitly - a payload the app never sends (0043).
select lives_ok(
  $$insert into public.services (name, price_paise, duration_minutes, active)
    values ('Head massage', 30000, 25, true)$$,
  'an insert that names no salon lands in the caller''s own - what the app sends'
);

select is(
  (select salon_id from public.services where name = 'Head massage'),
  'eeeeeeee-0000-4000-8000-000000000001'::uuid,
  'and it lands in THEIR salon, from their token rather than from the request'
);

select lives_ok(
  $$insert into public.staff (name, active) values ('Quiet Hire', true)$$,
  'the same for the team - no salon_id in the payload'
);

-- And naming someone else's salon is still refused, so the default is a
-- convenience rather than the protection.
select throws_ok(
  $$insert into public.services (salon_id, name, price_paise, duration_minutes, active)
    values ('cccccccc-0000-4000-8000-000000000001', 'Someone Else''s', 100, 10, true)$$,
  '42501', null,
  'naming ANOTHER salon is refused - the policy, not the default, is the control'
);

-- RULES 6.3 and 6.9: status is Crayora's. An owner who could write it could
-- switch their own salon on, or out of a suspension.
update public.salons set status = 'suspended'
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
select is(
  (select status::text from public.salons where id = 'eeeeeeee-0000-4000-8000-000000000001'),
  'active',
  'an owner cannot change their salon''s status - not on, not off (RULES 6.3, 6.9)'
);

update public.salons set join_code = 'CRAY-HACKED'
 where id = 'eeeeeeee-0000-4000-8000-000000000001';
select is(
  (select join_code from public.salons where id = 'eeeeeeee-0000-4000-8000-000000000001'),
  'CRAY-WWWQQQ',
  'an owner cannot change the code printed on their own counter cards'
);

select throws_ok(
  $$insert into public.salon_branding (salon_id, version, tokens)
    values ('eeeeeeee-0000-4000-8000-000000000001', 99, '{"displayName":"X"}'::jsonb)$$,
  '42501', null,
  'nor publish branding that never passed the contrast gate (ARCH 9.4)'
);

select throws_ok(
  $$insert into public.visits (salon_id, booking_id, customer_id, final_amount_paise, completed_at)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-3333-4000-8000-000000000001',
            'eeeeeeee-1111-4000-8000-00000000000c', 40000, now())$$,
  '42501', null,
  'a visit is not written by hand even by an owner - it comes from mark-complete (M6)'
);

-- ---------------------------------------------------------------------------
-- As a STAFF member: the day's work, and no promotions
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-aaaa-4000-8000-00000000000f",'
  '"app_role":"staff",'
  '"salon_id":"eeeeeeee-0000-4000-8000-000000000001"}',
  true
);

update public.users set role = 'owner'
 where id = 'eeeeeeee-5555-4000-8000-00000000000a';
select is(
  (select role::text from public.users where id = 'eeeeeeee-5555-4000-8000-00000000000a'),
  'staff',
  'a staff member cannot promote themselves - public.users holds `role`'
);

update public.services set price_paise = 1
 where id = 'eeeeeeee-2222-4000-8000-000000000001';
select is(
  (select price_paise from public.services where id = 'eeeeeeee-2222-4000-8000-000000000001'),
  45000::bigint,
  'and cannot reprice the menu'
);

select throws_ok(
  $$insert into public.staff (salon_id, name, active)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'Friend', true)$$,
  '42501', null,
  'nor add to the team'
);

-- ---------------------------------------------------------------------------
-- As a CUSTOMER: their own rows, and nothing of the salon's
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"eeeeeeee-aaaa-4000-8000-00000000000c",'
  '"app_role":"customer",'
  '"salon_id":"eeeeeeee-0000-4000-8000-000000000001"}',
  true
);

select throws_ok(
  $$insert into public.services (salon_id, name, price_paise, duration_minutes, active)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'Free Haircut', 0, 30, true)$$,
  '42501', null,
  'a customer cannot add to the menu'
);

update public.services set price_paise = 1
 where id = 'eeeeeeee-2222-4000-8000-000000000001';
select is(
  (select price_paise from public.services where id = 'eeeeeeee-2222-4000-8000-000000000001'),
  45000::bigint,
  'and cannot reprice it - the bug that started this migration'
);

select throws_ok(
  $$insert into public.visits (salon_id, booking_id, customer_id, final_amount_paise, completed_at)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'eeeeeeee-3333-4000-8000-000000000001',
            'eeeeeeee-1111-4000-8000-00000000000c', 40000, now())$$,
  '42501', null,
  'nor write their own visit history, which loyalty and reminders are computed from'
);

select throws_ok(
  $$insert into public.users (salon_id, role, name, phone, phone_hash, active)
    values ('eeeeeeee-0000-4000-8000-000000000001', 'owner', 'Me Now', '9877700077',
            '\x00'::bytea, true)$$,
  '42501', null,
  'nor make themselves staff'
);

select lives_ok(
  $$update public.customers set name = 'My Own Name'
     where id = 'eeeeeeee-1111-4000-8000-00000000000c'$$,
  'but a customer can still edit their OWN profile - that is theirs'
);

select is(
  (select name from public.customers where id = 'eeeeeeee-1111-4000-8000-00000000000c'),
  'My Own Name',
  'and the edit actually applied'
);

-- The menu must stay READABLE: a customer who cannot read it cannot book.
select is((select count(*)::int from public.services), 3,
  'reading the menu is untouched - only writing it was ever the problem');

reset role;
select * from finish();
