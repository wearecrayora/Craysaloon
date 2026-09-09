import 'server-only';
import postgres from 'postgres';

/**
 * The ONLY path from the console to the admin plane.
 *
 * Why a direct Postgres connection rather than a Supabase RPC call: `app_admin`
 * is deliberately not exposed through PostgREST (ADR-35). If it were, reaching
 * provision/activate/set-secret would need only a missing grant to go wrong.
 * Kept off PostgREST entirely, it needs a database connection *and* a grant -
 * two independent failures instead of one.
 *
 * Everything here is `server-only`: importing this file from a client component
 * is a build error, not a runtime surprise.
 *
 * On Vercel, ADMIN_DATABASE_URL must be the TRANSACTION POOLER url (port 6543).
 * Serverless invocations open and discard connections constantly and would
 * exhaust the direct connection slots within minutes of real use.
 */

declare global {
  // eslint-disable-next-line no-var
  var __adminSql: ReturnType<typeof postgres> | undefined;
}

function client() {
  const url = process.env.ADMIN_DATABASE_URL;
  if (!url) {
    throw new Error(
      'ADMIN_DATABASE_URL is not set. The console cannot reach the admin plane ' +
        'without it. See console/.env.local.example.',
    );
  }

  // Reused across hot reloads in development; in production each serverless
  // instance gets its own small pool.
  if (!globalThis.__adminSql) {
    globalThis.__adminSql = postgres(url, {
      max: 3,
      idle_timeout: 20,
      connect_timeout: 15,
      // The transaction pooler does not support prepared statements.
      prepare: false,
      onnotice: () => {},
      // The URL carries a password. Never let it reach a log.
      debug: false,
    });
  }
  return globalThis.__adminSql;
}

/**
 * The shapeless half of provisioning - working hours, wallet/reward/loyalty
 * rules, cancellation policy - which the database takes as jsonb. Typed as
 * real JSON rather than `Record<string, unknown>` so that something
 * unserialisable cannot be handed to the driver and fail at runtime.
 */
export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };
export type SettingsJson = { [key: string]: JsonValue };

export type ProvisionInput = {
  legalName: string;
  displayName: string;
  ownerName: string;
  ownerPhone: string;
  plan: string;
  setupFeePaise: number;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  gstNumber?: string | null;
  timezone?: string;
  languages?: string[];
  settings?: SettingsJson;
};

export type ProvisionResult = {
  salon_id: string;
  join_code: string;
  owner_user_id: string;
  status: string;
};

/**
 * RULES 6.2 - one transaction. The function does the whole thing; this is a
 * single call precisely so that a failure cannot leave a half-built tenant.
 */
export async function provisionSalon(
  actorAdminId: string,
  input: ProvisionInput,
): Promise<ProvisionResult> {
  const sql = client();
  const [row] = await sql<{ provision_salon: ProvisionResult }[]>`
    select app_admin.provision_salon(
      ${actorAdminId}::uuid,
      ${input.legalName},
      ${input.displayName},
      ${input.ownerName},
      ${input.ownerPhone},
      ${input.plan},
      ${input.setupFeePaise},
      ${input.phone ?? null},
      ${input.email ?? null},
      ${input.address ?? null},
      ${input.gstNumber ?? null},
      ${input.timezone ?? 'Asia/Kolkata'},
      ${sql.array(input.languages ?? ['en', 'hi'])},
      ${sql.json(input.settings ?? {})}
    )`;
  if (!row) throw new Error('provision_salon returned no row');
  return row.provision_salon;
}

/** RULES 6.3 - the only door from setup to active, and it names a human. */
export async function activateSalon(actorAdminId: string, salonId: string, reason: string | null) {
  const sql = client();
  await sql`select app_admin.activate_salon(${actorAdminId}::uuid, ${salonId}::uuid, ${reason})`;
}

/** RULES 6.9 - status changes, never deletion. Cannot reach `active`. */
export async function setSalonStatus(
  actorAdminId: string,
  salonId: string,
  status: 'grace' | 'suspended',
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_salon_status(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${status}, ${reason})`;
}

/** RULES 6.4 - collected offline; the reference is the only evidence. */
export async function recordSetupFee(
  actorAdminId: string,
  salonId: string,
  status: 'unpaid' | 'paid' | 'waived',
  reference: string | null,
  paidOn: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.record_setup_fee(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${status}, ${reference}, ${paidOn}::date)`;
}

/**
 * ARCHITECTURE 8.2 - write-only. There is deliberately no counterpart that
 * reads a credential back, here or in the database.
 */
export async function setIntegrationSecret(
  actorAdminId: string,
  salonId: string,
  provider: 'razorpay' | 'message_central' | 'whatsapp' | 'rcs',
  secret: string,
  publicKeyId: string | null,
  senderId: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.set_integration_secret(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${provider}, ${secret},
      ${publicKeyId}, ${senderId})`;
}

/**
 * Writes tokens and bumps salon_branding.version in one statement. Whether the
 * palette MAY be published is decided before this is called, by
 * validateBranding() from the shared token package - one implementation of the
 * contrast rule, shared with the app so the preview cannot lie (ADR-22).
 */
export async function publishBranding(
  actorAdminId: string,
  salonId: string,
  tokens: SettingsJson,
): Promise<number> {
  const sql = client();
  const [row] = await sql<{ publish_branding: number }[]>`
    select app_admin.publish_branding(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${sql.json(tokens)})`;
  if (!row) throw new Error('publish_branding returned no row');
  return row.publish_branding;
}

export type SalonBranding = { version: number; tokens: SettingsJson } | null;

export async function getSalon(salonId: string) {
  const sql = client();
  const [row] = await sql<{ id: string; display_name: string; status: string }[]>`
    select id, display_name, status::text from public.salons where id = ${salonId}::uuid`;
  return row ?? null;
}

export async function getBranding(salonId: string): Promise<SalonBranding> {
  const sql = client();
  const [row] = await sql<{ version: number; tokens: SettingsJson }[]>`
    select version, tokens from public.salon_branding where salon_id = ${salonId}::uuid`;
  return row ?? null;
}

export async function recordIntegrationTest(
  actorAdminId: string,
  salonId: string,
  provider: string,
  ok: boolean,
  detail: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.record_integration_test(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${provider}, ${ok}, ${detail})`;
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

export type SalonRow = {
  id: string;
  display_name: string;
  legal_name: string;
  join_code: string;
  status: 'setup' | 'active' | 'grace' | 'suspended';
  created_at: string;
  activated_at: string | null;
  plan: string | null;
  setup_fee_paise: string | null;
  setup_fee_status: string | null;
  integrations_ok: number;
  integrations_total: number;
};

export async function listSalons(): Promise<SalonRow[]> {
  const sql = client();
  return sql<SalonRow[]>`
    select s.id, s.display_name, s.legal_name, s.join_code, s.status,
           s.created_at, s.activated_at,
           sub.plan, sub.setup_fee_paise::text, sub.setup_fee_status::text,
           count(*) filter (where si.status = 'ok')::int      as integrations_ok,
           count(si.*)::int                                    as integrations_total
      from public.salons s
      left join public.subscriptions sub on sub.salon_id = s.id
      left join public.salon_integrations si on si.salon_id = s.id
     group by s.id, sub.plan, sub.setup_fee_paise, sub.setup_fee_status
     order by s.created_at desc`;
}

// ---------------------------------------------------------------------------
// Catalogue and rules
// ---------------------------------------------------------------------------

export type ServiceRow = {
  id: string;
  name: string;
  category: string | null;
  price_paise: string;
  duration_minutes: number;
  repeat_cycle_days: number | null;
  active: boolean;
};

export type AddOnRow = {
  id: string;
  name: string;
  price_paise: string;
  extra_duration_minutes: number;
  active: boolean;
};

export type StaffRow = { id: string; name: string; skills: string[]; active: boolean };

export type SalonRules = {
  wallet_rule: unknown;
  reward_rule: unknown;
  loyalty_rule: unknown;
  default_reminder_cycle_days: number;
  cancellation_policy: string | null;
};

export async function listServices(salonId: string): Promise<ServiceRow[]> {
  const sql = client();
  return sql<ServiceRow[]>`
    select id, name, category, price_paise::text, duration_minutes, repeat_cycle_days, active
      from public.services where salon_id = ${salonId}::uuid
     order by active desc, name`;
}

export async function listAddOns(salonId: string): Promise<AddOnRow[]> {
  const sql = client();
  return sql<AddOnRow[]>`
    select id, name, price_paise::text, extra_duration_minutes, active
      from public.add_ons where salon_id = ${salonId}::uuid
     order by active desc, name`;
}

export async function listStaff(salonId: string): Promise<StaffRow[]> {
  const sql = client();
  return sql<StaffRow[]>`
    select id, name, skills, active
      from public.staff where salon_id = ${salonId}::uuid
     order by active desc, name`;
}

export async function getRules(salonId: string): Promise<SalonRules | null> {
  const sql = client();
  const [row] = await sql<SalonRules[]>`
    select wallet_rule, reward_rule, loyalty_rule,
           default_reminder_cycle_days, cancellation_policy
      from public.salons where id = ${salonId}::uuid`;
  return row ?? null;
}

export async function upsertService(
  actorAdminId: string,
  salonId: string,
  v: {
    id: string | null;
    name: string;
    pricePaise: number;
    durationMinutes: number;
    category: string | null;
    repeatCycleDays: number | null;
    active: boolean;
  },
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ upsert_service: string }[]>`
    select app_admin.upsert_service(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${v.id}::uuid, ${v.name},
      ${v.pricePaise}, ${v.durationMinutes}, ${v.category},
      ${v.repeatCycleDays}, ${v.active})`;
  if (!row) throw new Error('upsert_service returned no row');
  return row.upsert_service;
}

export async function upsertAddOn(
  actorAdminId: string,
  salonId: string,
  v: {
    id: string | null;
    name: string;
    pricePaise: number;
    extraDurationMinutes: number;
    active: boolean;
  },
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ upsert_add_on: string }[]>`
    select app_admin.upsert_add_on(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${v.id}::uuid, ${v.name},
      ${v.pricePaise}, ${v.extraDurationMinutes}, ${v.active})`;
  if (!row) throw new Error('upsert_add_on returned no row');
  return row.upsert_add_on;
}

export async function upsertStaff(
  actorAdminId: string,
  salonId: string,
  v: { id: string | null; name: string; skills: string[]; active: boolean },
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ upsert_staff: string }[]>`
    select app_admin.upsert_staff(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${v.id}::uuid, ${v.name},
      ${sql.array(v.skills)}, ${v.active})`;
  if (!row) throw new Error('upsert_staff returned no row');
  return row.upsert_staff;
}

/**
 * Bonus expiry is NOT among the keys this accepts, and the database refuses a
 * payload that mentions expiry at all. That is the owner's setting, made in
 * the app (RULES 5.3.3); paid credit never expires.
 */
export async function setSalonRules(
  actorAdminId: string,
  salonId: string,
  rules: SettingsJson,
): Promise<void> {
  const sql = client();
  await sql`
    select app_admin.set_salon_rules(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${sql.json(rules)})`;
}

export type IntegrationRow = {
  provider: 'razorpay' | 'message_central' | 'whatsapp' | 'rcs';
  status: 'missing' | 'untested' | 'ok' | 'failing';
  last4: string | null;
  public_key_id: string | null;
  sender_id: string | null;
  whatsapp_template_status: string | null;
  last_tested_at: string | null;
  has_secret: boolean;
};

/**
 * Everything the console is allowed to know about a salon's credentials.
 *
 * Note what is NOT selected: vault_secret_id. Not because reading a uuid would
 * leak anything by itself, but because the moment it is in scope somebody will
 * join it to vault.decrypted_secrets to build a "just show me the key" screen.
 * `has_secret` answers the only question the UI actually has.
 */
export async function listIntegrations(salonId: string): Promise<IntegrationRow[]> {
  const sql = client();
  return sql<IntegrationRow[]>`
    select provider::text, status::text, last4, public_key_id, sender_id,
           whatsapp_template_status::text, last_tested_at,
           (vault_secret_id is not null) as has_secret
      from public.salon_integrations
     where salon_id = ${salonId}::uuid
     order by provider`;
}

/**
 * Identity check for the console's own auth. `platform_admins` has forced RLS
 * and no policies, so a tenant-role client genuinely cannot read it - which is
 * why this lookup has to happen here rather than through the Supabase client.
 */
export async function findActivePlatformAdmin(authUserId: string) {
  const sql = client();
  const [row] = await sql<{ id: string; name: string; email: string; is_super: boolean }[]>`
    select id, name, email, is_super
      from public.platform_admins
     where id = ${authUserId}::uuid and active
     limit 1`;
  return row ?? null;
}
