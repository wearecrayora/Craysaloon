-- 0013 Integrity constraints
--
-- The invariants that would end the business if they failed, enforced by the
-- database rather than by application code that can be bypassed, forgotten,
-- or worked around by a future session in a hurry.

-- ---------------------------------------------------------------------------
-- 1. Append-only ledgers, enforced TWICE
-- ---------------------------------------------------------------------------
--
-- The grant stops tenant roles. The trigger stops everyone INCLUDING the
-- service role and the table owner - which the grant does not (RULES 5.1.1).
-- Reversals are new rows; there is no legitimate UPDATE or DELETE here.

revoke update, delete on public.wallet_transactions from authenticated, anon;
revoke update, delete on public.loyalty_ledger      from authenticated, anon;
revoke insert, update, delete on public.wallet_lots      from authenticated, anon;
revoke insert, update, delete on public.wallet_accounts  from authenticated, anon;

create or replace function app.block_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'append-only: % on %.% is not permitted. Reversals are new rows (RULES.md 5.1.1).',
    tg_op, tg_table_schema, tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create trigger wallet_transactions_append_only
  before update or delete on public.wallet_transactions
  for each row execute function app.block_ledger_mutation();

create trigger loyalty_ledger_append_only
  before update or delete on public.loyalty_ledger
  for each row execute function app.block_ledger_mutation();

-- ---------------------------------------------------------------------------
-- 2. No double-booking a barber
-- ---------------------------------------------------------------------------
--
-- An application-level availability check loses every race: two requests read
-- "free" and both write. Only the database can win it (ARCHITECTURE 6.5).
--
-- The partial WHERE matters: cancelled and completed bookings must not block
-- the slot. Rows with staff_id NULL never conflict, which is correct - an
-- unassigned walk-in blocks nobody.

alter table public.bookings
  add constraint bookings_no_staff_overlap
  exclude using gist (
    salon_id with =,
    staff_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('pending', 'confirmed'));

-- ---------------------------------------------------------------------------
-- 3. A customer's wallet account belongs to the same salon as the customer
-- ---------------------------------------------------------------------------
--
-- Cheap to state, catastrophic if wrong: it would let credit issued by one
-- salon be spent at another, which is precisely what makes the wallet a
-- closed-loop instrument outside PPI licensing (RULES 6d).

create or replace function app.assert_same_salon_as_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_salon uuid;
begin
  select salon_id into v_customer_salon
    from public.customers where id = new.customer_id;

  if v_customer_salon is null then
    raise exception 'customer % does not exist', new.customer_id;
  end if;

  if v_customer_salon <> new.salon_id then
    raise exception
      'cross-salon write blocked: % row claims salon % but customer % belongs to %',
      tg_table_name, new.salon_id, new.customer_id, v_customer_salon
      using errcode = 'raise_exception';
  end if;

  return new;
end;
$$;

create trigger wallet_accounts_same_salon
  before insert or update on public.wallet_accounts
  for each row execute function app.assert_same_salon_as_customer();

create trigger wallet_lots_same_salon
  before insert on public.wallet_lots
  for each row execute function app.assert_same_salon_as_customer();

create trigger wallet_transactions_same_salon
  before insert on public.wallet_transactions
  for each row execute function app.assert_same_salon_as_customer();

create trigger loyalty_ledger_same_salon
  before insert on public.loyalty_ledger
  for each row execute function app.assert_same_salon_as_customer();

-- ---------------------------------------------------------------------------
-- 4. binding_events is append-only too
-- ---------------------------------------------------------------------------
--
-- It is the audit trail for the exclusivity rule. An editable history is not
-- a history.

create trigger binding_events_append_only
  before update or delete on public.binding_events
  for each row execute function app.block_ledger_mutation();

-- ---------------------------------------------------------------------------
-- 5. audit_log is append-only
-- ---------------------------------------------------------------------------

create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function app.block_ledger_mutation();
