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

/**
 * Grant, extend or end a messaging trial (0032). `days` counts from NOW; zero
 * ends it immediately. Capped at 365 in the database.
 */
export async function setMessagingTrial(
  actorAdminId: string,
  salonId: string,
  days: number,
  reason: string,
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ ends: string }[]>`
    select app_admin.set_messaging_trial(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${days}, ${reason}) as ends`;
  if (!row) throw new Error('set_messaging_trial returned no row');
  return row.ends;
}

/**
 * Grant or end a messaging grace period (0033). Granted while a trial runs, it
 * starts when the trial ends. When it ends, a salon with no Message Central
 * account of its own is BLOCKED. Zero ends it now; capped at 365 days.
 */
export async function setMessagingGrace(
  actorAdminId: string,
  salonId: string,
  days: number,
  reason: string,
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ ends: string }[]>`
    select app_admin.set_messaging_grace(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${days}, ${reason}) as ends`;
  if (!row) throw new Error('set_messaging_grace returned no row');
  return row.ends;
}

// ---------------------------------------------------------------------------
// Customer binding (K12). Super-admin only - enforced by the database
// (app_admin.assert_super_admin, 0036), not by this file.
// ---------------------------------------------------------------------------

export type BindingLookup =
  | { bound: false }
  | {
      bound: true;
      salon_id: string;
      salon_name: string;
      join_code: string;
      salon_status: string;
      customer_status: string;
      bound_at: string;
      wallet_transactions: number;
      bookings: number;
      visits: number;
      can_unbind: boolean;
      balance_paise: number;
      paid_paise: number;
      bonus_paise: number;
    };

/** RULES 4.6 + RULES 2: one complete number, a reason, audited - not a search. */
export async function lookupBinding(
  actorAdminId: string,
  phone: string,
  reason: string,
): Promise<BindingLookup> {
  const sql = client();
  const [row] = await sql<{ r: BindingLookup }[]>`
    select app_admin.lookup_binding(${actorAdminId}::uuid, ${phone}, ${reason}) as r`;
  if (!row) throw new Error('lookup_binding returned no row');
  return row.r;
}

export async function unbindCustomer(actorAdminId: string, phone: string, reason: string) {
  const sql = client();
  await sql`select app_admin.unbind_customer(${actorAdminId}::uuid, ${phone}, ${reason})`;
}

/** RULES 4.6 - the acknowledged balance must equal the real one, or the database refuses. */
export async function transferCustomer(
  actorAdminId: string,
  phone: string,
  toSalonId: string,
  reason: string,
  acknowledgedBalancePaise: number,
) {
  const sql = client();
  await sql`
    select app_admin.transfer_customer(
      ${actorAdminId}::uuid, ${phone}, ${toSalonId}::uuid, ${reason},
      ${acknowledgedBalancePaise}::bigint)`;
}

/** Where a customer can be transferred to: salons that can take a new customer today. */
export async function listTransferDestinations() {
  const sql = client();
  return sql<{ id: string; display_name: string; join_code: string }[]>`
    select id, display_name, join_code
      from public.salons
     where status = 'active' and app.salon_writable(id)
     order by display_name`;
}

/**
 * The salon's named privacy contact (DPDP ss.5, 13).
 *
 * Not a secret: this is published to every customer in the consent notice,
 * BEFORE they log in, because that is the only moment it matters. It is read
 * back here on purpose - an operator has to be able to see and correct it.
 */
export async function getGrievanceContact(salonId: string) {
  const sql = client();
  const [row] = await sql<
    { grievance_name: string | null; grievance_email: string | null; grievance_phone: string | null }[]
  >`
    select grievance_name, grievance_email, grievance_phone
      from public.salons where id = ${salonId}::uuid`;
  return row ?? null;
}

/** A name plus at least one reachable channel. The database enforces both (0053). */
export async function setGrievanceContact(
  actorAdminId: string,
  salonId: string,
  name: string,
  email: string | null,
  phone: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.set_grievance_contact(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${name}, ${email}, ${phone})`;
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

/** RULES 6.4 - collected offline: amount, date and reference. The reference is the only evidence. */
export async function recordSetupFee(
  actorAdminId: string,
  salonId: string,
  status: 'unpaid' | 'paid' | 'waived',
  reference: string | null,
  paidOn: string | null,
  amountPaise: number | null = null,
) {
  const sql = client();
  await sql`
    select app_admin.record_setup_fee(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${status}, ${reference}, ${paidOn}::date,
      ${amountPaise}::bigint)`;
}

// ---------------------------------------------------------------------------
// Billing (M11, 0087). The DATABASE computes the state from renews_at; the
// console only shows it, so it can never disagree with what RLS enforces.
// ---------------------------------------------------------------------------

export type BillingState = 'unbilled' | 'active' | 'grace' | 'suspended' | 'purge_due';
export type Feature = 'dashboard' | 'referrals';

export type BillingOverview = {
  subscription: {
    plan: 'starter' | 'growth' | 'pro';
    monthly_price_paise: number;
    billing_starts_on: string | null;
    setup_fee_status: 'unpaid' | 'paid' | 'waived';
    setup_fee_paise: number;
    setup_fee_reference: string | null;
    setup_fee_paid_on: string | null;
  };
  dates: {
    state: BillingState;
    renews_at: string | null;
    grace_ends_at: string | null;
    notice_60_at: string | null;
    notice_80_at: string | null;
    purge_after: string | null;
  } | null;
  writable: boolean;
  payments: {
    id: number;
    amount_paise: number;
    months: number;
    period_start: string;
    period_end: string;
    reference: string;
    paid_on: string;
    recorded_by: string | null;
  }[];
  notices: { kind: string; due_at: string; cycle_renews_at: string }[];
  features: Record<Feature, { plan: boolean; override: boolean | null; effective: boolean }>;
};

export async function getBillingOverview(
  actorAdminId: string,
  salonId: string,
): Promise<BillingOverview | null> {
  const sql = client();
  const [row] = await sql<{ r: BillingOverview | null }[]>`
    select app_admin.billing_overview(${actorAdminId}::uuid, ${salonId}::uuid) as r`;
  return row?.r ?? null;
}

/** Plan, agreed price and the first due date. The due date is set once. */
export async function setBilling(
  actorAdminId: string,
  salonId: string,
  plan: 'starter' | 'growth' | 'pro',
  monthlyPricePaise: number,
  billingStartsOn: string | null,
  reason: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.set_billing(${actorAdminId}::uuid, ${salonId}::uuid, ${plan},
      ${monthlyPricePaise}::bigint, ${billingStartsOn}::date, ${reason})`;
}

/** Collected offline, like the setup fee. Moves renews_at on from where it was. */
export async function recordSubscriptionPayment(
  actorAdminId: string,
  salonId: string,
  amountPaise: number,
  months: number,
  reference: string,
  paidOn: string | null,
) {
  const sql = client();
  await sql`
    select app_admin.record_subscription_payment(${actorAdminId}::uuid, ${salonId}::uuid,
      ${amountPaise}::bigint, ${months}::int, ${reference}, ${paidOn}::date)`;
}

/** A comp: time given away, so a reason is required and audited. */
export async function extendSubscription(
  actorAdminId: string,
  salonId: string,
  days: number,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.extend_subscription(${actorAdminId}::uuid, ${salonId}::uuid,
      ${days}::int, ${reason})`;
}

/** A per-salon override of the plan; null clears it back to the plan. */
export async function setFeatureFlag(
  actorAdminId: string,
  salonId: string,
  flag: Feature,
  enabled: boolean | null,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_feature_flag(${actorAdminId}::uuid, ${salonId}::uuid, ${flag},
      ${enabled}::boolean, ${reason})`;
}

export type PlatformMetrics = {
  salons: Record<string, number> | null;
  billing: Partial<Record<BillingState, number>> | null;
  mrr_paise: number;
  activations_30d: number;
  churned_30d: number;
  subscription_revenue_30d_paise: number;
  setup_fees_paise: number;
  sends_30d: Record<string, number>;
  median_hours_to_first_bind: number | null;
  salons_never_bound: number;
};

export async function getPlatformMetrics(actorAdminId: string): Promise<PlatformMetrics> {
  const sql = client();
  const [row] = await sql<{ r: PlatformMetrics }[]>`
    select app_admin.platform_metrics(${actorAdminId}::uuid) as r`;
  if (!row) throw new Error('platform_metrics returned no row');
  return row.r;
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

/**
 * The salon's own webhook path token.
 *
 * Razorpay has to be told where to send that salon's payment notifications, and
 * the URL carries this token: it is how the webhook knows WHICH salon it is for,
 * without trusting anything in the body (ARCHITECTURE 8.3). Shown to the
 * operator so they can paste it into the salon's Razorpay dashboard.
 *
 * It is not a secret in the credential sense - it identifies, it does not
 * authorise; the signature does that - but it is per-salon and not published.
 */
export async function getWebhookToken(salonId: string) {
  const sql = client();
  const [row] = await sql<{ webhook_token: string | null }[]>`
    select webhook_token from public.salons where id = ${salonId}::uuid`;
  return row?.webhook_token ?? null;
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
  /** The salon's own Message Central account is stored and not known-bad. */
  otp_own_account: boolean;
  /** OTPs sent from Crayora's account because something FAILED, last 7 days. */
  otp_fallbacks_7d: number;
  /** When the messaging trial ends (0032). Null: none was ever granted. */
  messaging_trial_ends_at: string | null;
  /** OTPs Crayora paid for ON PURPOSE under the trial, last 7 days. */
  otp_trial_sends_7d: number;
  /** When the post-trial grace period ends (0033). Null: none granted. */
  messaging_grace_ends_at: string | null;
  /** own | trial | grace | blocked | fallback - computed by the database, one definition. */
  messaging_state: 'own' | 'trial' | 'grace' | 'blocked' | 'fallback';
};

export async function listSalons(): Promise<SalonRow[]> {
  const sql = client();
  return sql<SalonRow[]>`
    select s.id, s.display_name, s.legal_name, s.join_code, s.status,
           s.created_at, s.activated_at,
           sub.plan, sub.setup_fee_paise::text, sub.setup_fee_status::text,
           count(*) filter (where si.status = 'ok')::int      as integrations_ok,
           count(si.*)::int                                    as integrations_total,
           coalesce(bool_or(si.provider = 'message_central'
                   and si.vault_secret_id is not null
                   and si.status <> 'failing'), false)         as otp_own_account,
           (select count(*)::int from public.otp_challenges oc
             where oc.salon_id = s.id and oc.sender = 'platform'
               and oc.created_at > now() - interval '7 days')  as otp_fallbacks_7d,
           sub.messaging_trial_ends_at,
           sub.messaging_grace_ends_at,
           app.salon_messaging_state(s.id)                     as messaging_state,
           (select count(*)::int from public.otp_challenges oc
             where oc.salon_id = s.id and oc.sender = 'trial'
               and oc.created_at > now() - interval '7 days')  as otp_trial_sends_7d
      from public.salons s
      left join public.subscriptions sub on sub.salon_id = s.id
      left join public.salon_integrations si on si.salon_id = s.id
     group by s.id, sub.plan, sub.setup_fee_paise, sub.setup_fee_status,
              sub.messaging_trial_ends_at, sub.messaging_grace_ends_at
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

/**
 * Which add-ons are offered with which service. create_booking REFUSES an
 * add-on that is not linked to the service being booked, so until this is set
 * an add-on can be created and never sold.
 */
export async function listServiceAddOns(salonId: string) {
  const sql = client();
  return sql<{ service_id: string; add_on_id: string }[]>`
    select service_id, add_on_id from public.service_addons
     where salon_id = ${salonId}::uuid`;
}

export async function setServiceAddOn(
  actorAdminId: string,
  salonId: string,
  serviceId: string,
  addOnId: string,
  linked: boolean,
) {
  const sql = client();
  await sql`
    select app_admin.set_service_add_on(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${serviceId}::uuid, ${addOnId}::uuid, ${linked})`;
}

export type DataRightsRequest = {
  request_id: string;
  salon_name: string;
  kind: 'access' | 'erasure' | 'grievance';
  status: string;
  requested_at: string;
  due_at: string;
  overdue: boolean;
};

/** Open requests, oldest deadline first. No customer identifiers - by design (0081). */
export async function listDataRightsRequests(actorAdminId: string): Promise<DataRightsRequest[]> {
  const sql = client();
  return sql<DataRightsRequest[]>`
    select request_id, salon_name, kind, status, requested_at, due_at, overdue
      from app_admin.list_data_rights_requests(${actorAdminId}::uuid)`;
}

/** DPDP s.12(3). By REQUEST id: an erasure can only follow a request the customer made. */
export async function carryOutErasure(actorAdminId: string, requestId: string, reason: string) {
  const sql = client();
  await sql`select app_admin.carry_out_erasure(${actorAdminId}::uuid, ${requestId}::uuid, ${reason})`;
}

/**
 * Ledger caller 5 of five: the only human path to a balance. By PHONE, resolved
 * in the database - the console is never handed a customer id (0081).
 */
export async function walletCorrectByPhone(
  actorAdminId: string,
  phone: string,
  amountPaise: number,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.wallet_correct_by_phone(
      ${actorAdminId}::uuid, ${phone}, ${amountPaise}::bigint, ${reason})`;
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

/** RULES 6.5 in spirit: generating a salon's public-facing artifact is attributable. */
export async function recordAsset(
  actorAdminId: string,
  salonId: string,
  kind: 'qr_pack',
  objectKey: string,
) {
  const sql = client();
  await sql`
    select app_admin.record_asset(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${kind}, ${objectKey})`;
}

export async function getJoinCode(salonId: string) {
  const sql = client();
  const [row] = await sql<{ join_code: string; display_name: string }[]>`
    select join_code, display_name from public.salons where id = ${salonId}::uuid`;
  return row ?? null;
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
