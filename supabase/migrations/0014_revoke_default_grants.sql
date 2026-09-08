-- 0014 Revoke Supabase's default table grants
--
-- FOUND BY THE MONEY GATE, not by reading the schema.
--
-- Supabase grants ALL privileges on every table in `public` to `anon` and
-- `authenticated` by default. 0013 revoked a handful by hand and missed the
-- rest - including INSERT on both ledgers, which is the one that matters.
--
-- RLS was still denying those writes: the ledgers have no INSERT policy, so a
-- tenant insert fails anyway. But that is ONE layer. The design says the
-- append-only rule holds three ways (grant, policy, trigger), and a grant that
-- exists is a grant that a future "just add an INSERT policy" turns live.
--
-- Two changes here:
--   1. `anon` loses every table privilege. Its only legitimate entry points
--      are security definer functions (resolve_join_code, start_join at M3),
--      which need no table grant at all.
--   2. `authenticated` loses write privileges on every read-only table, so
--      "read-only" is true at the grant layer as well as the policy layer.
--
-- Default privileges are altered too, so a table added tomorrow does not
-- silently arrive with write grants.

-- ---------------------------------------------------------------------------
-- 1. anon holds nothing. Not one table, not one privilege.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;

-- ---------------------------------------------------------------------------
-- 2. authenticated is read-only on everything it does not legitimately write.
-- ---------------------------------------------------------------------------
--
-- The list mirrors `readonly` and `no_policy` in 0012. Kept explicit rather
-- than derived, so the two files can be diffed against each other by eye.

do $$
declare
  t text;
  readonly constant text[] := array[
    -- Ledgers and money. Written ONLY by the five callers in RULES 5.2,
    -- which are security definer and therefore bypass both grant and policy.
    'wallet_accounts', 'wallet_lots', 'wallet_transactions', 'loyalty_ledger',
    'payments', 'payment_allocations',
    -- Written by automations and the console, never by a tenant.
    'audit_log', 'daily_salon_metrics', 'retention_cohorts',
    'notifications', 'notification_deliveries',
    'subscriptions', 'feature_flags', 'referrals',
    'customer_service_intervals',
    -- Cross-tenant, secrets and machinery: no tenant access of any kind.
    'customer_identities', 'binding_events', 'join_intents',
    'salon_integrations', 'platform_admins',
    'domain_events', 'jobs', 'idempotency_keys', 'webhook_events',
    'rate_limit_counters', 'schema_migrations'
  ];
begin
  foreach t in array readonly loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format(
        'revoke insert, update, delete on public.%I from authenticated', t);
    end if;
  end loop;
end;
$$;

-- The cross-tenant and secret tables lose SELECT as well. Forced RLS with no
-- policy already denies them, but a table holding Vault handles and the
-- one-binding-per-phone index should not be readable at the grant layer
-- either.
revoke all on public.customer_identities  from authenticated;
revoke all on public.binding_events       from authenticated;
revoke all on public.join_intents         from authenticated;
revoke all on public.salon_integrations   from authenticated;
revoke all on public.platform_admins      from authenticated;
revoke all on public.domain_events        from authenticated;
revoke all on public.jobs                 from authenticated;
revoke all on public.idempotency_keys     from authenticated;
revoke all on public.webhook_events       from authenticated;
revoke all on public.rate_limit_counters  from authenticated;
revoke all on public.schema_migrations    from authenticated;
