-- RELEASE GATE: binding at first login, the claims hook, unbind and transfer
--
-- Never skipped, never deleted, never narrowed to pass.
--
-- PHASES M4 done-when, asserted against the functions that actually run:
--   * binding completes in the same step as first login (RULES 4.3)
--   * "already bound" never names the other salon (RULES 4.4)
--   * unbind and transfer are Crayora actions, reason-required, audited, and a
--     transfer leaves wallet and history with the old salon (RULES 4.5, 4.6)
--   * consent rows exist for every bound customer, with DPDP-correct defaults
-- plus the claims hook, without which a bound customer could still read nothing,
-- and what every binding change must also do (0035): announce a new customer,
-- and end the sessions of one whose binding moved or went.

select plan(40);

insert into auth.users (id) values
  ('88888888-aaaa-4000-8000-00000000000a'),   -- operator (not super)
  ('88888888-aaaa-4000-8000-00000000000b'),   -- super-admin
  ('88888888-aaaa-4000-8000-0000000000c1'),   -- customer
  ('88888888-aaaa-4000-8000-0000000000c2'),   -- second customer
  ('88888888-aaaa-4000-8000-0000000000f1');   -- salon B's owner

insert into public.platform_admins (id, email, name, is_super, active)
values ('88888888-aaaa-4000-8000-00000000000a', 'bind@crayora.test', 'Bind Op', false, true),
       ('88888888-aaaa-4000-8000-00000000000b', 'super@crayora.test', 'Bind Super', true, true);

insert into public.salons (id, legal_name, display_name, join_code, status,
                           activated_by, activated_at)
values
  ('88888888-0000-4000-8000-00000000000a', 'Salon Alpha Ltd', 'Salon Alpha',
   'CRAY-AAAQQQ', 'active', '88888888-aaaa-4000-8000-00000000000a', now()),
  ('88888888-0000-4000-8000-00000000000b', 'Salon Beta Ltd', 'Salon Beta',
   'CRAY-BBBQQQ', 'active', '88888888-aaaa-4000-8000-00000000000a', now());

-- A completed Message Central verification, as otp-verify would have it.
create or replace function pg_temp.verified(p_phone text, p_salon uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := public.otp_record_challenge(p_phone, p_salon, 'mc-' || p_phone, 'salon');
  perform public.otp_complete(v);
  return v;
end $$;

create or replace function pg_temp.claims(p_uid uuid) returns jsonb language sql as $$
  select public.custom_access_token_hook(
    jsonb_build_object('user_id', p_uid, 'claims', jsonb_build_object('sub', p_uid))) -> 'claims'
$$;

-- ---------------------------------------------------------------------------
-- The claims hook, before anything is bound
-- ---------------------------------------------------------------------------

select is(
  pg_temp.claims('88888888-aaaa-4000-8000-0000000000c1') ->> 'app_role',
  'customer_unbound',
  'an account with no binding gets customer_unbound'
);

select is(
  pg_temp.claims('88888888-aaaa-4000-8000-0000000000c1') ? 'salon_id',
  false,
  'and no salon_id - so RLS shows it nothing'
);

-- ---------------------------------------------------------------------------
-- First join: bound, in one step
-- ---------------------------------------------------------------------------

select public.start_join('CRAY-AAAQQQ', '9844400001');
create temp table t1 as select pg_temp.verified('9844400001', '88888888-0000-4000-8000-00000000000a') as id;

select is(
  public.otp_finish_login((select id from t1), '88888888-aaaa-4000-8000-0000000000c1',
                          '{"promotional": true}'::jsonb) ->> 'outcome',
  'bound',
  'a first login binds the customer to the salon whose code they entered'
);

select results_eq(
  $$select salon_id, phone, auth_user_id from public.customers
     where phone_hash = app.phone_hash('9844400001')$$,
  $$values ('88888888-0000-4000-8000-00000000000a'::uuid, '9844400001',
            '88888888-aaaa-4000-8000-0000000000c1'::uuid)$$,
  'the salon gets a customer row with the VERIFIED number, so it can contact them'
);

select is(
  (select salon_id from public.customer_identities where phone_hash = app.phone_hash('9844400001')),
  '88888888-0000-4000-8000-00000000000a'::uuid,
  'and the global binding points at that salon'
);

select is(
  (select count(*)::int from public.binding_events
    where phone_hash = app.phone_hash('9844400001') and kind = 'bind' and actor_admin_id is null),
  1,
  'a self-service bind is recorded, with no admin actor'
);

-- DPDP: service messages are the service; marketing only if ticked; photos never here.
select results_eq(
  $$select purpose::text, granted from public.consents c
      join public.customers cu on cu.id = c.customer_id
     where cu.phone_hash = app.phone_hash('9844400001') order by purpose::text$$,
  $$values ('photos', false), ('promotional', true),
           ('service_communication', true), ('whatsapp', false)$$,
  'consent defaults: service on, marketing only as ticked, photos never at binding'
);

select is(
  (select count(*)::int from public.domain_events
    where type = 'customer.bound' and payload ->> 'via' = 'join'
      and salon_id = '88888888-0000-4000-8000-00000000000a'
      and aggregate_id = (select customer_id from public.customer_identities
                           where phone_hash = app.phone_hash('9844400001'))),
  1,
  'binding announces customer.bound to the salon, for the welcome automation'
);

select is(
  (select count(*)::int from public.join_intents where phone_hash = app.phone_hash('9844400001')),
  0,
  'the join intent is consumed'
);

select is(
  (select phone from public.otp_challenges where id = (select id from t1)),
  null,
  'the plaintext number on the challenge is wiped the moment login finishes'
);

select results_eq(
  $$select pg_temp.claims('88888888-aaaa-4000-8000-0000000000c1') ->> 'app_role',
           pg_temp.claims('88888888-aaaa-4000-8000-0000000000c1') ->> 'salon_id'$$,
  $$values ('customer', '88888888-0000-4000-8000-00000000000a')$$,
  'the next token carries app_role customer and the salon - RLS can now serve it'
);

-- ---------------------------------------------------------------------------
-- Returning: nothing changes
-- ---------------------------------------------------------------------------

create temp table t2 as select pg_temp.verified('9844400001', '88888888-0000-4000-8000-00000000000a') as id;
select is(
  public.otp_finish_login((select id from t2), '88888888-aaaa-4000-8000-0000000000c1',
                          '{"promotional": false}'::jsonb) ->> 'outcome',
  'returning',
  'a later login to the same salon is "returning"'
);

select is(
  (select count(*)::int from public.consents c join public.customers cu on cu.id = c.customer_id
    where cu.phone_hash = app.phone_hash('9844400001')),
  4,
  'and does not overwrite the consent choices already made'
);

-- ---------------------------------------------------------------------------
-- Already bound elsewhere: refused, naming no salon
-- ---------------------------------------------------------------------------

create temp table t3 as select pg_temp.verified('9844400001', '88888888-0000-4000-8000-00000000000b') as id;
create temp table r3 as
  select public.otp_finish_login((select id from t3), '88888888-aaaa-4000-8000-0000000000c1') as r;

select is((select r ->> 'reason' from r3), 'already_bound',
  'a number bound to one salon cannot bind to another');

select is(
  (select (r::text ~* 'Alpha|88888888-0000-4000-8000-00000000000a') from r3),
  false,
  'and the refusal names neither the other salon nor its id (RULES 4.4)'
);

-- ---------------------------------------------------------------------------
-- Staff: the owner provisioned in the console, logging in for the first time
-- ---------------------------------------------------------------------------

insert into public.users (id, salon_id, role, name, phone, phone_hash, active)
values ('88888888-5555-4000-8000-0000000000f1', '88888888-0000-4000-8000-00000000000b',
        'owner', 'Beta Owner', '9844400009', app.phone_hash('9844400009'), true);

create temp table t4 as select pg_temp.verified('9844400009', '88888888-0000-4000-8000-00000000000b') as id;
select is(
  public.otp_finish_login((select id from t4), '88888888-aaaa-4000-8000-0000000000f1') ->> 'outcome',
  'staff',
  'an owner''s first login attaches their account to the staff row'
);

select is(
  (select count(*)::int from public.customers where phone_hash = app.phone_hash('9844400009')),
  0,
  'and does not make the owner a customer of their own salon'
);

select results_eq(
  $$select pg_temp.claims('88888888-aaaa-4000-8000-0000000000f1') ->> 'app_role',
           pg_temp.claims('88888888-aaaa-4000-8000-0000000000f1') ->> 'salon_id'$$,
  $$values ('owner', '88888888-0000-4000-8000-00000000000b')$$,
  'the owner''s token carries app_role owner and their salon'
);

select is(
  pg_temp.claims('88888888-aaaa-4000-8000-00000000000a') ? 'salon_id',
  false,
  'a platform admin''s token never carries a salon_id (RULES 6.7)'
);

-- ---------------------------------------------------------------------------
-- Unbind: only with no history
-- ---------------------------------------------------------------------------

select public.start_join('CRAY-AAAQQQ', '9844400002');
create temp table t5 as select pg_temp.verified('9844400002', '88888888-0000-4000-8000-00000000000a') as id;
select public.otp_finish_login((select id from t5), '88888888-aaaa-4000-8000-0000000000c2');

-- A session the customer is holding when Crayora unbinds them.
insert into auth.sessions (id, user_id)
values (extensions.gen_random_uuid(), '88888888-aaaa-4000-8000-0000000000c2');

select throws_ok(
  $$select app_admin.unbind_customer('88888888-aaaa-4000-8000-00000000000a',
      '9844400002', 'Scanned the wrong salon''s QR')$$,
  '42501', null,
  'an ordinary operator cannot unbind - binding changes are super-admin only (ARCH 14.3 #7)'
);

select is(
  app_admin.lookup_binding('88888888-aaaa-4000-8000-00000000000b', '9844400002',
                           'Customer called: scanned the wrong QR') ->> 'can_unbind',
  'true',
  'the lookup tells support a customer with no history can be unbound'
);

select lives_ok(
  $$select app_admin.unbind_customer('88888888-aaaa-4000-8000-00000000000b',
      '9844400002', 'Scanned the wrong salon''s QR')$$,
  'a customer with no history can be unbound by a Crayora super-admin'
);

select is(
  (select count(*)::int from public.customer_identities where phone_hash = app.phone_hash('9844400002')),
  0,
  'and is then free to bind again'
);

select is(
  (select count(*)::int from auth.sessions where user_id = '88888888-aaaa-4000-8000-0000000000c2'),
  0,
  'and every session they held ends - no token can refresh with the old salon'
);

-- History exists for customer 1: unbind must refuse and point at transfer.
insert into public.wallet_transactions (salon_id, customer_id, kind, amount_paise, balance_after)
select '88888888-0000-4000-8000-00000000000a', id, 'credit_topup', 55000, 55000
  from public.customers where phone_hash = app.phone_hash('9844400001');
insert into public.wallet_accounts (customer_id, salon_id, balance_paise)
select id, '88888888-0000-4000-8000-00000000000a', 55000
  from public.customers where phone_hash = app.phone_hash('9844400001');

select throws_ok(
  $$select app_admin.unbind_customer('88888888-aaaa-4000-8000-00000000000b',
      '9844400001', 'wants to leave')$$,
  'P0001', null,
  'a customer with history cannot be unbound - only transferred, with the balance acknowledged'
);

-- ---------------------------------------------------------------------------
-- The lookup support must do first (RULES 4.6), without being a search (RULES 2)
-- ---------------------------------------------------------------------------

create temp table lk as
  select app_admin.lookup_binding('88888888-aaaa-4000-8000-00000000000b', '9844400001',
                                  'Customer asked to move salons') as r;

select results_eq(
  $$select r ->> 'salon_name', (r ->> 'balance_paise')::bigint, r ->> 'can_unbind' from lk$$,
  $$values ('Salon Alpha', 55000::bigint, 'false')$$,
  'a super-admin sees the salon, the balance to disclose, and that only a transfer is possible'
);

select throws_ok(
  $$select app_admin.lookup_binding('88888888-aaaa-4000-8000-00000000000a', '9844400001', 'curious')$$,
  '42501', null,
  'an ordinary operator cannot look a number up'
);

select is(
  app_admin.lookup_binding('88888888-aaaa-4000-8000-00000000000b', '9844400077', 'probe') ->> 'bound',
  'false',
  'an unbound number says only that'
);

select is(
  (select count(*)::int from public.audit_log
    where action = 'customer.binding_looked_up'
      and actor_user_id = '88888888-aaaa-4000-8000-00000000000b'
      and entity_id !~ '9844400'),
  3,
  'every lookup is audited - found or not - and the log keeps the last four digits only'
);

-- ---------------------------------------------------------------------------
-- Transfer: the binding moves, NOTHING ELSE DOES
-- ---------------------------------------------------------------------------

insert into auth.sessions (id, user_id)
values (extensions.gen_random_uuid(), '88888888-aaaa-4000-8000-0000000000c1');

select throws_ok(
  $$select app_admin.transfer_customer('88888888-aaaa-4000-8000-00000000000b',
      '9844400001', '88888888-0000-4000-8000-00000000000b', 'moving', null)$$,
  'P0001', null,
  'a transfer without the acknowledged balance is refused'
);

select throws_ok(
  $$select app_admin.transfer_customer('88888888-aaaa-4000-8000-00000000000b',
      '9844400001', '88888888-0000-4000-8000-00000000000b', 'moving', 0)$$,
  'P0001', null,
  'acknowledging a balance that is not the real one is refused - "0" is not looking'
);

select throws_ok(
  $$select app_admin.transfer_customer('88888888-aaaa-4000-8000-00000000000a',
      '9844400001', '88888888-0000-4000-8000-00000000000b', 'moving', 55000)$$,
  '42501', null,
  'an ordinary operator cannot transfer'
);

select lives_ok(
  $$select app_admin.transfer_customer('88888888-aaaa-4000-8000-00000000000b',
      '9844400001', '88888888-0000-4000-8000-00000000000b',
      'Customer moved house', 55000)$$,
  'with the real balance acknowledged, a super-admin can transfer the customer'
);

select results_eq(
  $$select count(*)::int, min(wt.salon_id::text)
      from public.wallet_transactions wt join public.customers c on c.id = wt.customer_id
     where c.phone_hash = app.phone_hash('9844400001')$$,
  $$values (1, '88888888-0000-4000-8000-00000000000a')$$,
  'the wallet stays with the old salon - its money settled there, and cannot move'
);

select results_eq(
  $$select status::text from public.customers
     where phone_hash = app.phone_hash('9844400001') order by created_at$$,
  $$values ('transferred_out'), ('active')$$,
  'the old record is kept as transferred_out; the new salon starts fresh'
);

select is(
  (select phone from public.customers
    where phone_hash = app.phone_hash('9844400001')
      and salon_id = '88888888-0000-4000-8000-00000000000b'),
  '9844400001',
  'the new salon gets the number, so it can reach the customer it was given'
);

select is(
  (select count(*)::int from public.domain_events
    where type = 'customer.bound' and payload ->> 'via' = 'transfer'
      and salon_id = '88888888-0000-4000-8000-00000000000b'),
  1,
  'the new salon is told it has a new customer'
);

select is(
  (select count(*)::int from auth.sessions where user_id = '88888888-aaaa-4000-8000-0000000000c1'),
  0,
  'a transfer ends the customer''s sessions, so the next login carries the new salon'
);

select is(
  pg_temp.claims('88888888-aaaa-4000-8000-0000000000c1') ->> 'salon_id',
  '88888888-0000-4000-8000-00000000000b',
  'and that next token names the new salon'
);

select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('custom_access_token_hook', 'otp_finish_login')
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
  0,
  'neither the claims hook nor the binding step can be called by a tenant'
);

select * from finish();
