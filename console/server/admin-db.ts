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
 * On Cloudflare, ADMIN_DATABASE_URL must be the TRANSACTION POOLER url (port 6543).
 * Serverless invocations open and discard connections constantly and would
 * exhaust the direct connection slots within minutes of real use.
 */

/**
 * A connection for THIS call, never shared.
 *
 * On Cloudflare Workers a socket belongs to the request that opened it. The
 * console used to keep one pool on globalThis (a Vercel habit): the first
 * request in a fresh isolate worked, and every later one that touched the
 * database waited on a socket it could not use - the runtime cancelled it as
 * hung and the admin saw Error 1101 (found 13 Oct 2026, the first time anyone
 * signed in after the move to Cloudflare). So each call opens its own
 * single-connection client against the TRANSACTION pooler, which is built for
 * exactly this, and lets it close on idle.
 */
function client() {
  const url = process.env.ADMIN_DATABASE_URL;
  if (!url) {
    throw new Error(
      'ADMIN_DATABASE_URL is not set. The console cannot reach the admin plane ' +
        'without it. See console/.env.local.example.',
    );
  }

  return postgres(url, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 15,
    // The transaction pooler does not support prepared statements.
    prepare: false,
    onnotice: () => {},
    // The URL carries a password. Never let it reach a log.
    debug: false,
  });
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
  // Every argument is cast: through the transaction pooler the driver sends
  // parameters untyped, and an array arrives as TEXT - so no function matched
  // and provisioning failed with "provision_salon(..., text, jsonb) does not
  // exist" (13 Oct 2026, the first salon provisioned on Cloudflare).
  const [row] = await sql<{ provision_salon: ProvisionResult }[]>`
    select app_admin.provision_salon(
      ${actorAdminId}::uuid,
      ${input.legalName}::text,
      ${input.displayName}::text,
      ${input.ownerName}::text,
      ${input.ownerPhone}::text,
      ${input.plan}::text,
      ${input.setupFeePaise}::bigint,
      ${input.phone ?? null}::text,
      ${input.email ?? null}::text,
      ${input.address ?? null}::text,
      ${input.gstNumber ?? null}::text,
      ${input.timezone ?? 'Asia/Kolkata'}::text,
      ${input.languages ?? ['en', 'hi']}::text[],
      ${sql.json(input.settings ?? {})}::jsonb
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

/**
 * Super-admin only: switch a salon on before its setup is complete (0116/0117).
 * A reason is required; the audit row lists what was skipped, and so does the
 * return value.
 */
export async function activateSalonAnyway(
  actorAdminId: string,
  salonId: string,
  reason: string,
): Promise<string[]> {
  const sql = client();
  const [row] = await sql<{ r: { skipped: string[] } }[]>`
    select app_admin.activate_salon_anyway(${actorAdminId}::uuid, ${salonId}::uuid, ${reason}) as r`;
  return row?.r?.skipped ?? [];
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
    /** A reversal row points at the payment it undoes (0112). */
    reverses_id: number | null;
    reason: string | null;
    reversed: boolean;
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

/**
 * A payment recorded by mistake is reversed by a NEW row - the table is
 * append-only - with a reason, audited, once per payment (0112).
 */
export async function reverseSubscriptionPayment(
  actorAdminId: string,
  paymentId: number,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.reverse_subscription_payment(${actorAdminId}::uuid, ${paymentId}::bigint,
      ${reason})`;
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

export type SalonGst = { gst_number: string | null; gst_rate_bp: number | null };

export async function getSalonGst(salonId: string): Promise<SalonGst | null> {
  const sql = client();
  const [row] = await sql<SalonGst[]>`
    select gst_number, gst_rate_bp from public.salons where id = ${salonId}::uuid`;
  return row ?? null;
}

/**
 * Registers a salon for GST (a GSTIN and a rate, both) or unregisters it
 * (neither). From here on its paid visits get tax invoices - or bills of supply.
 * Audited, with a reason; the database validates the GSTIN's shape (0094).
 */
export async function setSalonGst(
  actorAdminId: string,
  salonId: string,
  gstNumber: string | null,
  rateBp: number | null,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_salon_gst(${actorAdminId}::uuid, ${salonId}::uuid, ${gstNumber},
      ${rateBp}::int, ${reason})`;
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
/**
 * The salon's SMS sender ID, WhatsApp Business number and template approval
 * status (0102). Not secrets - but they decide which paid rungs exist, so they
 * are Crayora's to set, audited, like the credentials beside them.
 */
export async function setMessagingIdentity(
  actorAdminId: string,
  salonId: string,
  smsSenderId: string | null,
  whatsappNumber: string | null,
  whatsappStatus: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_messaging_identity(${actorAdminId}::uuid, ${salonId}::uuid,
      ${smsSenderId}, ${whatsappNumber}, ${whatsappStatus})`;
}

/** Map one message (key, language) to an approved WhatsApp template; a null name clears it. */
export async function setWhatsappTemplate(
  actorAdminId: string,
  salonId: string,
  templateKey: string,
  locale: string,
  templateName: string | null,
  lang: string | null,
  variables: string[],
) {
  const sql = client();
  await sql`
    select app_admin.set_whatsapp_template(${actorAdminId}::uuid, ${salonId}::uuid,
      ${templateKey}, ${locale}, ${templateName}, ${lang}, ${variables}::text[])`;
}

export type MessageKey = { template_key: string; placeholders: string[] };
export type WhatsappTemplateRow = {
  template_key: string;
  locale: string;
  template_name: string;
  lang: string | null;
  variables: string[];
};

/** The messages this product sends, and the values each one may use (0102). */
export async function listMessageKeys(): Promise<MessageKey[]> {
  const sql = client();
  return sql<MessageKey[]>`
    select t.template_key,
           coalesce(array_agg(distinct m[1]) filter (where m[1] is not null), '{}') as placeholders
      from public.message_templates t
      left join lateral regexp_matches(t.body, '\\{\\{([a-z_]+)\\}\\}', 'g') m on true
     where t.salon_id is null and t.channel = 'push'
     group by t.template_key
     order by t.template_key`;
}

export async function listWhatsappTemplates(salonId: string): Promise<WhatsappTemplateRow[]> {
  const sql = client();
  return sql<WhatsappTemplateRow[]>`
    select template_key, locale, provider_template_id as template_name,
           provider_lang as lang, coalesce(provider_variables, '{}') as variables
      from public.message_templates
     where salon_id = ${salonId}::uuid and channel = 'whatsapp'
     order by template_key, locale`;
}

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
      ${actorAdminId}::uuid, ${salonId}::uuid, ${sql.json(tokens)}::jsonb)`;
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
  kind: 'access' | 'erasure' | 'grievance' | 'correction';
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
      ${v.skills}::text[], ${v.active}::boolean)`;
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
      ${actorAdminId}::uuid, ${salonId}::uuid, ${sql.json(rules)}::jsonb)`;
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

// ---------------------------------------------------------------------------
// Offboarding (M12, 0089). Super-admin only; the database refuses anyone else.
// ---------------------------------------------------------------------------

/** Everything the salon holds, as one JSON document for the owner. Read-only. */
export async function getSalonExport(actorAdminId: string, salonId: string): Promise<unknown> {
  const sql = client();
  const [row] = await sql<{ r: unknown }[]>`
    select app_admin.salon_export(${actorAdminId}::uuid, ${salonId}::uuid) as r`;
  return row?.r ?? null;
}

export async function recordExportOffered(actorAdminId: string, salonId: string, note: string) {
  const sql = client();
  await sql`select app_admin.record_export_offered(${actorAdminId}::uuid, ${salonId}::uuid, ${note})`;
}

/** Records HOW the salon settled its customers' credit. The ledger is not touched (RULES 5.2). */
export async function recordCreditSettlement(actorAdminId: string, salonId: string, note: string) {
  const sql = client();
  await sql`select app_admin.record_credit_settlement(${actorAdminId}::uuid, ${salonId}::uuid, ${note})`;
}

export type PurgeResult = {
  ok: boolean;
  already: boolean;
  customers_anonymised?: number;
  bindings_released?: number;
  staff_closed?: number;
};

export async function purgeSalon(
  actorAdminId: string,
  salonId: string,
  reason: string,
  typedName: string,
): Promise<PurgeResult> {
  const sql = client();
  const [row] = await sql<{ r: PurgeResult }[]>`
    select app_admin.purge_salon(${actorAdminId}::uuid, ${salonId}::uuid, ${reason}, ${typedName}) as r`;
  if (!row) throw new Error('purge_salon returned no row');
  return row.r;
}

export type OffboardingFacts = {
  export_offered_at: string | null;
  export_offered_note: string | null;
  credit_settled_at: string | null;
  credit_settled_note: string | null;
  purged_at: string | null;
  outstanding_paise: number;
};

export async function getOffboardingFacts(salonId: string): Promise<OffboardingFacts | null> {
  const sql = client();
  const [row] = await sql<OffboardingFacts[]>`
    select s.export_offered_at, s.export_offered_note, s.credit_settled_at, s.credit_settled_note,
           s.purged_at,
           (select coalesce(sum(w.balance_paise), 0)::int from public.wallet_accounts w
             where w.salon_id = s.id) as outstanding_paise
      from public.salons s where s.id = ${salonId}::uuid`;
  return row ?? null;
}

// ---------------------------------------------------------------------------
// Support mode (M12, 0089, RULES 6.8)
// ---------------------------------------------------------------------------

export type SupportSession = {
  id: string;
  admin: string;
  reason: string;
  started_at: string;
  ends_at: string;
  ended_at: string | null;
  live: boolean;
  mine: boolean;
};

export async function listSupportSessions(actorAdminId: string, salonId: string): Promise<SupportSession[]> {
  const sql = client();
  const [row] = await sql<{ r: SupportSession[] }[]>`
    select app_admin.list_support_sessions(${actorAdminId}::uuid, ${salonId}::uuid) as r`;
  return row?.r ?? [];
}

export async function startSupportSession(
  actorAdminId: string,
  salonId: string,
  reason: string,
  minutes: number,
) {
  const sql = client();
  await sql`
    select app_admin.start_support_session(${actorAdminId}::uuid, ${salonId}::uuid, ${reason},
      ${minutes}::int)`;
}

export async function endSupportSession(actorAdminId: string, sessionId: string) {
  const sql = client();
  await sql`select app_admin.end_support_session(${actorAdminId}::uuid, ${sessionId}::uuid)`;
}

export type SupportCustomer = {
  customer_id: string;
  name: string | null;
  phone_last4: string;
  balance_paise: number;
  last_visit_at: string | null;
  anonymised: boolean;
};

/** Masked, and only inside a live session - the database refuses otherwise. */
export async function supportCustomers(
  actorAdminId: string,
  salonId: string,
  search: string | null,
): Promise<SupportCustomer[]> {
  const sql = client();
  const [row] = await sql<{ r: SupportCustomer[] }[]>`
    select app_admin.support_customers(${actorAdminId}::uuid, ${salonId}::uuid, ${search}) as r`;
  return row?.r ?? [];
}

/** A separate act with its own reason, audited on its own (RULES 6.8). */
export async function supportUnmaskPhone(actorAdminId: string, customerId: string, reason: string) {
  const sql = client();
  const [row] = await sql<{ r: string | null }[]>`
    select app_admin.support_unmask_phone(${actorAdminId}::uuid, ${customerId}::uuid, ${reason}) as r`;
  return row?.r ?? null;
}

// ---------------------------------------------------------------------------
// The right of access (0091): a customer's copy of their data, by REQUEST id.
// ---------------------------------------------------------------------------

export async function getAccessRequestExport(actorAdminId: string, requestId: string): Promise<unknown> {
  const sql = client();
  const [row] = await sql<{ r: unknown }[]>`
    select app_admin.access_request_export(${actorAdminId}::uuid, ${requestId}::uuid) as r`;
  return row?.r ?? null;
}

export async function completeAccessRequest(actorAdminId: string, requestId: string, howSent: string) {
  const sql = client();
  await sql`
    select app_admin.complete_access_request(${actorAdminId}::uuid, ${requestId}::uuid, ${howSent})`;
}

/** Lifts a manual grace or suspension (0092). Super-admin; refused for purged or lapsed salons. */
export async function reactivateSalon(actorAdminId: string, salonId: string, reason: string) {
  const sql = client();
  await sql`select app_admin.reactivate_salon(${actorAdminId}::uuid, ${salonId}::uuid, ${reason})`;
}

// ---------------------------------------------------------------------------
// Setup checklist and logins (0105)
// ---------------------------------------------------------------------------

export type SetupFacts = {
  display_name: string;
  join_code: string;
  status: string;
  owner_name: string | null;
  owner_phone_last4: string | null;
  branding_version: number | null;
  has_logo: boolean;
  services: number;
  stylists: number;
  mc_status: string | null;
  mc_has_secret: boolean;
  razorpay_has_secret: boolean;
  sms_sender: boolean;
  whatsapp_approved: boolean;
  grievance_set: boolean;
  fee_status: string | null;
  logins: number;
  customers: number;
};

/** Everything the setup checklist needs to say what is done and what is not. */
export async function getSetupFacts(salonId: string): Promise<SetupFacts | null> {
  const sql = client();
  const [row] = await sql<SetupFacts[]>`
    select s.display_name, s.join_code, s.status::text,
           o.name as owner_name, right(o.phone, 4) as owner_phone_last4,
           b.version as branding_version,
           coalesce(b.tokens #>> '{assets,logo}' like 'https://%', false) as has_logo,
           (select count(*)::int from public.services x where x.salon_id = s.id and x.active) as services,
           (select count(*)::int from public.staff x where x.salon_id = s.id and x.active) as stylists,
           mc.status::text as mc_status,
           (mc.vault_secret_id is not null) as mc_has_secret,
           coalesce(rz.vault_secret_id is not null, false) as razorpay_has_secret,
           coalesce(mc.sender_id is not null, false) as sms_sender,
           coalesce(wa.whatsapp_template_status = 'approved' and wa.sender_id is not null, false)
             as whatsapp_approved,
           (coalesce(btrim(s.grievance_name), '') <> ''
             and coalesce(btrim(coalesce(s.grievance_email, s.grievance_phone)), '') <> '')
             as grievance_set,
           sub.setup_fee_status::text as fee_status,
           (select count(*)::int from public.users u
             where u.salon_id = s.id and u.active and u.role <> 'owner') as logins,
           (select count(*)::int from public.customers c where c.salon_id = s.id) as customers
      from public.salons s
      left join public.users o on o.salon_id = s.id and o.role = 'owner' and o.active
      left join public.salon_branding b on b.salon_id = s.id
      left join public.salon_integrations mc on mc.salon_id = s.id and mc.provider = 'message_central'
      left join public.salon_integrations rz on rz.salon_id = s.id and rz.provider = 'razorpay'
      left join public.salon_integrations wa on wa.salon_id = s.id and wa.provider = 'whatsapp'
      left join public.subscriptions sub on sub.salon_id = s.id
     where s.id = ${salonId}::uuid
     limit 1`;
  return row ?? null;
}

export type SalonLogin = {
  id: string;
  role: 'owner' | 'manager' | 'staff';
  name: string;
  phone_last4: string;
  active: boolean;
  signed_in: boolean;
};

/** Who can sign in to this salon. The number is shown by its last four only. */
export async function listSalonLogins(salonId: string): Promise<SalonLogin[]> {
  const sql = client();
  return sql<SalonLogin[]>`
    select id, role::text, name, right(phone, 4) as phone_last4, active,
           (auth_user_id is not null) as signed_in
      from public.users
     where salon_id = ${salonId}::uuid
     order by (role = 'owner') desc, active desc, name`;
}

export async function addSalonLogin(
  actorAdminId: string,
  salonId: string,
  name: string,
  phone: string,
  role: 'manager' | 'staff',
): Promise<string> {
  const sql = client();
  const [row] = await sql<{ id: string }[]>`
    select app_admin.add_salon_login(${actorAdminId}::uuid, ${salonId}::uuid,
      ${name}::text, ${phone}::text, ${role}::text) as id`;
  if (!row) throw new Error('add_salon_login returned no row');
  return row.id;
}

export async function setSalonLoginActive(
  actorAdminId: string,
  userId: string,
  active: boolean,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_salon_login_active(${actorAdminId}::uuid, ${userId}::uuid,
      ${active}::boolean, ${reason}::text)`;
}

// ---------------------------------------------------------------------------
// Audit log (K16) and messaging (K8)
// ---------------------------------------------------------------------------

export type AuditRow = {
  id: string;
  created_at: string;
  salon_name: string | null;
  actor_kind: string;
  actor_name: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  reason: string | null;
  after_state: unknown;
};

/** The newest 200 audit rows, filtered. Read-only - the log is append-only. */
export type Operator = { id: string; name: string; email: string; is_super: boolean; active: boolean };

/** Every Crayora operator - super-admins only (0115). */
export async function listOperators(actorAdminId: string): Promise<Operator[]> {
  const sql = client();
  const [row] = await sql<{ r: Operator[] }[]>`
    select app_admin.list_operators(${actorAdminId}::uuid) as r`;
  return row?.r ?? [];
}

/**
 * Switch an operator off (or back on). Off ends their sessions at once - the
 * breach runbook's containment for console access by the wrong person (0115).
 */
export async function setOperatorActive(
  actorAdminId: string,
  adminId: string,
  active: boolean,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_operator_active(${actorAdminId}::uuid, ${adminId}::uuid,
      ${active}::boolean, ${reason})`;
}

export async function listAudit(filter: {
  salonId?: string | null;
  action?: string | null;
  actorKind?: string | null;
  days?: number;
}): Promise<AuditRow[]> {
  const sql = client();
  const days = Math.min(Math.max(filter.days ?? 30, 1), 365);
  const action = filter.action ? `%${filter.action}%` : null;
  return sql<AuditRow[]>`
    select a.id::text, a.created_at, s.display_name as salon_name, a.actor_kind::text,
           coalesce(pa.name, u.name) as actor_name, a.action, a.entity, a.entity_id,
           a.reason, a.after_state
      from public.audit_log a
      left join public.salons s on s.id = a.salon_id
      left join public.platform_admins pa on pa.id = a.actor_user_id
      left join public.users u on u.auth_user_id = a.actor_user_id or u.id = a.actor_user_id
     where a.created_at > now() - make_interval(days => ${days}::int)
       and (${filter.salonId ?? null}::uuid is null or a.salon_id = ${filter.salonId ?? null}::uuid)
       and (${action}::text is null or a.action ilike ${action}::text)
       and (${filter.actorKind ?? null}::text is null or a.actor_kind::text = ${filter.actorKind ?? null}::text)
     order by a.created_at desc
     limit 200`;
}

export type ChannelStats = {
  channel: string;
  attempts: number;
  sent: number;
  acked: number;
  failed: number;
  cost_paise: number;
};

export type MessagingStats = {
  channels: ChannelStats[];
  notifications: { status: string; n: number }[];
  otp: { sender: string; n: number }[];
  failures: { reason: string; n: number }[];
};

/** Thirty days of one salon's messaging: per channel, outcomes, what it cost. */
export async function getMessagingStats(salonId: string): Promise<MessagingStats> {
  const sql = client();
  const [channels, notifications, otp, failures] = await Promise.all([
    sql<ChannelStats[]>`
      select channel::text,
             count(*)::int as attempts,
             count(*) filter (where sent_at is not null)::int as sent,
             count(*) filter (where acked_at is not null)::int as acked,
             count(*) filter (where provider_status = 'failed')::int as failed,
             coalesce(sum(cost_paise), 0)::int as cost_paise
        from public.notification_deliveries
       where salon_id = ${salonId}::uuid and created_at > now() - interval '30 days'
       group by 1 order by 1`,
    sql<{ status: string; n: number }[]>`
      select status::text, count(*)::int as n from public.notifications
       where salon_id = ${salonId}::uuid and created_at > now() - interval '30 days'
       group by 1 order by 2 desc`,
    sql<{ sender: string; n: number }[]>`
      select coalesce(sender, 'unknown') as sender, count(*)::int as n from public.otp_challenges
       where salon_id = ${salonId}::uuid and created_at > now() - interval '30 days'
       group by 1 order by 2 desc`,
    sql<{ reason: string; n: number }[]>`
      select coalesce(failure_reason, 'unknown') as reason, count(*)::int as n
        from public.notification_deliveries
       where salon_id = ${salonId}::uuid and provider_status = 'failed'
         and created_at > now() - interval '30 days'
       group by 1 order by 2 desc limit 8`,
  ]);
  return { channels, notifications, otp, failures };
}

/** Salons for filter pickers: id and name only. */
export async function listSalonNames(): Promise<{ id: string; display_name: string }[]> {
  const sql = client();
  return sql<{ id: string; display_name: string }[]>`
    select id, display_name from public.salons order by display_name`;
}

// ---------------------------------------------------------------------------
// The app, run from the console (0119): home layout, switches, versions,
// announcements. Every write is an audited app_admin function.
// ---------------------------------------------------------------------------

export type AppConfigRow = {
  salon_id: string;
  home_tiles: string[];
  home_sections: string[];
  switches: Record<string, boolean>;
  min_build: number;
  latest_build: number;
  update_url: string | null;
  version: number;
  updated_at: string;
};

export async function getAppConfig(actorAdminId: string, salonId: string): Promise<AppConfigRow | null> {
  const sql = client();
  const [row] = await sql<{ r: AppConfigRow | null }[]>`
    select app_admin.get_app_config(${actorAdminId}::uuid, ${salonId}::uuid) as r`;
  return row?.r ?? null;
}

export async function setAppConfig(
  actorAdminId: string,
  salonId: string,
  tiles: string[],
  sections: string[],
  switches: Record<string, boolean>,
  reason: string,
) {
  const sql = client();
  await sql`
    select app_admin.set_app_config(
      ${actorAdminId}::uuid, ${salonId}::uuid, ${sql.array(tiles)}::text[],
      ${sql.array(sections)}::text[], ${sql.json(switches)}::jsonb, ${reason})`;
}

export async function setAppVersions(
  actorAdminId: string,
  minBuild: number,
  latestBuild: number,
  updateUrl: string | null,
  reason: string,
): Promise<number> {
  const sql = client();
  const [row] = await sql<{ r: { salons: number } }[]>`
    select app_admin.set_app_versions(
      ${actorAdminId}::uuid, ${minBuild}::int, ${latestBuild}::int, ${updateUrl}, ${reason}) as r`;
  return row?.r?.salons ?? 0;
}

export type AnnouncementInput = {
  title: string;
  body: string | null;
  titleHi: string | null;
  bodyHi: string | null;
  icon: string;
  startsAt: string | null;
  endsAt: string;
};

/** Null salonIds = every live or in-setup salon (super-admins only). */
export async function publishAnnouncement(
  actorAdminId: string,
  salonIds: string[] | null,
  a: AnnouncementInput,
): Promise<number> {
  const sql = client();
  const ids = salonIds ? sql.array(salonIds) : null;
  const [row] = await sql<{ r: { salons: number } }[]>`
    select app_admin.publish_announcement(
      ${actorAdminId}::uuid, ${ids}::uuid[], ${a.title}, ${a.body}, ${a.titleHi}, ${a.bodyHi},
      ${a.icon}, ${a.startsAt}::timestamptz, ${a.endsAt}::timestamptz) as r`;
  return row?.r?.salons ?? 0;
}

export async function endAnnouncement(actorAdminId: string, id: string) {
  const sql = client();
  await sql`select app_admin.end_announcement(${actorAdminId}::uuid, ${id}::uuid)`;
}

export type AnnouncementRow = {
  id: string;
  title: string;
  body: string | null;
  icon: string;
  starts_at: string;
  ends_at: string;
  ended_at: string | null;
  live: boolean;
};

export async function listAnnouncements(actorAdminId: string, salonId: string): Promise<AnnouncementRow[]> {
  const sql = client();
  return sql<AnnouncementRow[]>`
    select * from app_admin.list_announcements(${actorAdminId}::uuid, ${salonId}::uuid)`;
}
