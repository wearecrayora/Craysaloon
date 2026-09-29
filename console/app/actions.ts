'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { resolveTokens, validateBranding, type BrandInput } from '@cray/design-tokens';
import { requireAdmin } from '@/server/auth';
import { JOIN_ORIGIN, renderQrPack } from '@/server/qr-pack';
import { putBrandObject, putObject, signedUrl } from '@/server/r2';
import { logoKey, logoProblem, sha256Hex, sniffLogo } from '@/lib/logo';
import { checkMessageCentralCredentials } from '@/server/message-central-check';
import { parseRupees } from '@/lib/money';
import {
  activateSalon,
  provisionSalon,
  getJoinCode,
  lookupBinding,
  publishBranding,
  transferCustomer,
  unbindCustomer,
  type BindingLookup,
  recordAsset,
  recordIntegrationTest,
  recordSetupFee,
  recordSubscriptionPayment,
  recordExportOffered,
  recordCreditSettlement,
  purgeSalon,
  startSupportSession,
  endSupportSession,
  supportUnmaskPhone,
  completeAccessRequest,
  reactivateSalon,
  extendSubscription,
  setBilling,
  setFeatureFlag,
  setIntegrationSecret,
  setMessagingGrace,
  setMessagingTrial,
  setSalonRules,
  setGrievanceContact,
  setServiceAddOn,
  carryOutErasure,
  walletCorrectByPhone,
  setSalonStatus,
  upsertAddOn,
  upsertService,
  upsertStaff,
} from '@/server/admin-db';

/**
 * Server actions. Every one of them calls requireAdmin() FIRST and passes the
 * resulting id into the app_admin function, which writes audit_log in the same
 * transaction as the mutation (RULES 6.5). There is no code path here that
 * mutates anything without an attributable actor.
 */

export type ActionState = { error?: string; ok?: string; joinCode?: string; url?: string };

export type PublishState = {
  error?: string;
  ok?: string;
  version?: number;
  /** Gate output, rendered as-is so the operator sees the measured ratios. */
  failures?: { rule: string; detail: string; measured?: number; required?: number }[];
  warnings?: { rule: string; detail: string; measured?: number; required?: number }[];
};

// An Indian mobile number, in any of the forms a person actually types. The
// database canonicalises and rejects too - this is only so the operator sees a
// useful message instead of a Postgres exception.
const phone = z
  .string()
  .trim()
  .regex(/^(?:\+?0*91[\s-]?)?[6-9]\d{9}$/u, 'Not a valid Indian mobile number');

const ProvisionSchema = z.object({
  legalName: z.string().trim().min(2, 'Legal name is required'),
  displayName: z
    .string()
    .trim()
    .min(2, 'Display name is required - it appears in every message the customer sees'),
  ownerName: z.string().trim().min(2, "The owner's name is required"),
  ownerPhone: phone,
  plan: z.string().trim().min(1, 'Plan is required'),
  setupFeeRupees: z.coerce.number().int().min(0, 'The setup fee cannot be negative'),
  phone: z.string().trim().optional().or(z.literal('')),
  email: z.string().trim().email('Not a valid email').optional().or(z.literal('')),
  address: z.string().trim().optional().or(z.literal('')),
  gstNumber: z.string().trim().optional().or(z.literal('')),
  timezone: z.string().trim().default('Asia/Kolkata'),
});

function fieldsOf(form: FormData) {
  return Object.fromEntries(form.entries());
}

function message(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  // app_admin functions raise with an `app_admin: ` prefix and a sentence
  // written for a human. Show that sentence; hide anything else, which would
  // be a Postgres internal the operator can do nothing with.
  const m = /app_admin: (.+)/s.exec(raw);
  if (m?.[1]) return m[1].trim();
  if (/phone_hash: /.test(raw)) return 'That phone number is not a valid Indian mobile number.';
  return 'Something went wrong. The action was not applied.';
}

export async function provisionAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();

  const parsed = ProvisionSchema.safeParse(fieldsOf(form));
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Check the form' };
  }
  const v = parsed.data;

  try {
    const result = await provisionSalon(admin.id, {
      legalName: v.legalName,
      displayName: v.displayName,
      ownerName: v.ownerName,
      ownerPhone: v.ownerPhone,
      plan: v.plan,
      // Money is integer paise everywhere (ADR-06). The form collects rupees
      // because that is what the operator was told on the phone.
      setupFeePaise: v.setupFeeRupees * 100,
      phone: v.phone || null,
      email: v.email || null,
      address: v.address || null,
      gstNumber: v.gstNumber || null,
      timezone: v.timezone,
    });

    revalidatePath('/');
    return {
      ok: `${v.displayName} provisioned in setup.`,
      joinCode: result.join_code,
    };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * The person at the salon who answers a privacy question or an erasure request.
 *
 * DPDP s.5 says the consent notice must tell a customer how to contact the Data
 * Fiduciary about their data, and s.13 gives them a right to grievance
 * redressal. The salon is the Fiduciary (RULES 11.7), so this is the salon's own
 * contact, and it is REQUIRED before activation - the database refuses to
 * activate without it, so this form is part of provisioning, not an extra.
 */
export async function grievanceAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const name = String(form.get('name') ?? '').trim();
  const email = String(form.get('email') ?? '').trim() || null;
  const phone = String(form.get('phone') ?? '').trim() || null;

  if (!name) {
    return { error: 'Name the person, not a department - a customer needs someone to ask.' };
  }
  if (!email && !phone) {
    return { error: 'An email or a phone number is required - a name alone is unreachable.' };
  }

  try {
    await setGrievanceContact(admin.id, salonId, name, email, phone);
    revalidatePath(`/salon/${salonId}/privacy`);
    revalidatePath('/');
    return { ok: 'Privacy contact saved. It appears in the consent notice customers see before login.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function activateAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const reason = String(form.get('reason') ?? '').trim() || null;

  try {
    await activateSalon(admin.id, salonId, reason);
    revalidatePath('/');
    return { ok: 'Salon activated.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function suspendAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const status = String(form.get('status') ?? '');
  const reason = String(form.get('reason') ?? '').trim();

  if (status !== 'grace' && status !== 'suspended') {
    return { error: 'Status must be grace or suspended.' };
  }
  if (!reason) {
    return { error: 'A reason is required - this stops a real business taking bookings.' };
  }

  try {
    await setSalonStatus(admin.id, salonId, status, reason);
    revalidatePath('/');
    return { ok: `Salon moved to ${status}.` };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function setupFeeAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const status = String(form.get('status') ?? '');
  const reference = String(form.get('reference') ?? '').trim() || null;
  const paidOn = String(form.get('paidOn') ?? '').trim() || null;
  const amountText = String(form.get('amount') ?? '').trim();
  const amountPaise = amountText === '' ? null : parseRupees(amountText);

  if (status !== 'unpaid' && status !== 'paid' && status !== 'waived') {
    return { error: 'Status must be unpaid, paid or waived.' };
  }
  if (amountText !== '' && amountPaise === null) {
    return { error: 'The amount is not a rupee amount.' };
  }

  try {
    await recordSetupFee(admin.id, salonId, status, reference, paidOn, amountPaise);
    revalidatePath('/');
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: 'Setup fee recorded.' };
  } catch (e) {
    return { error: message(e) };
  }
}

const PLANS = ['starter', 'growth', 'pro'] as const;

export async function setBillingAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const plan = String(form.get('plan') ?? '') as (typeof PLANS)[number];
  const price = parseRupees(String(form.get('price') ?? ''));
  const startsOn = String(form.get('startsOn') ?? '').trim() || null;
  const reason = String(form.get('reason') ?? '').trim() || null;

  if (!PLANS.includes(plan)) return { error: 'Choose a plan.' };
  if (price === null) return { error: 'The monthly price is not a rupee amount.' };

  try {
    await setBilling(admin.id, salonId, plan, price, startsOn, reason);
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: 'Billing saved.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function subscriptionPaymentAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const amount = parseRupees(String(form.get('amount') ?? ''));
  const months = Number(form.get('months') ?? 0);
  const reference = String(form.get('reference') ?? '').trim();
  const paidOn = String(form.get('paidOn') ?? '').trim() || null;

  if (amount === null || amount <= 0) return { error: 'Enter the amount received.' };
  if (!Number.isInteger(months) || months < 1 || months > 24) {
    return { error: 'A payment covers 1 to 24 months.' };
  }
  if (!reference) {
    return { error: 'A reference is required - the money moved outside the system.' };
  }

  try {
    await recordSubscriptionPayment(admin.id, salonId, amount, months, reference, paidOn);
    revalidatePath(`/salon/${salonId}/billing`);
    revalidatePath('/metrics');
    return { ok: 'Payment recorded.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function extendAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const days = Number(form.get('days') ?? 0);
  const reason = String(form.get('reason') ?? '').trim();

  if (!Number.isInteger(days) || days < 1 || days > 90) {
    return { error: 'An extension is 1 to 90 days.' };
  }
  if (!reason) return { error: 'A reason is required - this is revenue given away.' };

  try {
    await extendSubscription(admin.id, salonId, days, reason);
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: `Extended by ${days} day${days === 1 ? '' : 's'}.` };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function featureFlagAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const flag = String(form.get('flag') ?? '');
  const value = String(form.get('value') ?? '');
  const reason = String(form.get('reason') ?? '').trim();

  if (flag !== 'dashboard' && flag !== 'referrals') return { error: 'Unknown feature.' };
  if (!reason) return { error: 'A reason is required, and audited.' };
  const enabled = value === 'on' ? true : value === 'off' ? false : null;

  try {
    await setFeatureFlag(admin.id, salonId, flag, enabled, reason);
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: 'Saved.' };
  } catch (e) {
    return { error: message(e) };
  }
}


export type UploadLogoState = { url?: string; error?: string };

/**
 * Upload a salon logo to the public brand bucket and hand back its URL.
 *
 * Nothing is published here: the URL goes into the studio's draft, and only
 * Publish (below, audited) puts it in front of customers. The bytes decide what
 * the file is (lib/logo.ts) - PNG, JPEG or WebP, 512 KB at most, never SVG - and
 * the key is the content hash, so a new logo is a new URL that no cache can
 * confuse with the old one.
 */
export async function uploadLogoAction(
  _prev: UploadLogoState,
  form: FormData,
): Promise<UploadLogoState> {
  await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const file = form.get('logo');
  if (!(file instanceof File)) return { error: 'Choose a logo file first.' };

  const bytes = new Uint8Array(await file.arrayBuffer());
  const problem = logoProblem(bytes);
  if (problem) return { error: problem };
  const type = sniffLogo(bytes)!;

  try {
    const key = logoKey(salonId, await sha256Hex(bytes), type.ext);
    await putBrandObject(key, bytes, type.contentType);
    return { url: `${JOIN_ORIGIN}/brand/${key}` };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Publish branding. DESIGN 3.3 and ARCHITECTURE 14.2: a failing palette BLOCKS
 * publish. Not a warning, not an override.
 *
 * The gate runs HERE, on the server, rather than in the studio component. The
 * browser already runs the same check for live feedback, but a check that only
 * runs in a browser is advice: anything that can post a form can skip it.
 *
 * Warnings are different from failures on purpose. "Your primary is nearly the
 * same as the surface" is a judgement about how the app will look; refusing to
 * publish over it would be the token package overruling a designer. Contrast
 * failures are not judgement - they are the difference between text a customer
 * can read and text they cannot.
 */
export async function publishBrandingAction(
  _prev: PublishState,
  form: FormData,
): Promise<PublishState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');

  let input: BrandInput;
  try {
    input = JSON.parse(String(form.get('branding') ?? '')) as BrandInput;
  } catch {
    return { error: 'The branding payload was not valid JSON.' };
  }

  const gate = validateBranding(input);
  if (!gate.ok) {
    return {
      error:
        'Publish blocked: this palette fails contrast. A customer would not be able to read ' +
        'parts of their own salon app.',
      failures: gate.failures,
      warnings: gate.warnings,
    };
  }

  // Derive here, once, and publish the result. The app reads these values and
  // computes nothing: a Dart port of the derivation would be free to drift from
  // this preview, which is the one thing ADR-22 exists to prevent (0037 refuses
  // a document without them). ADR-40.
  const document = {
    ...input,
    resolved: {
      light: resolveTokens(input, 'light'),
      dark: resolveTokens(input, 'dark'),
    },
  };

  try {
    const version = await publishBranding(
      admin.id,
      salonId,
      document as unknown as Record<string, never>,
    );
    revalidatePath(`/salon/${salonId}/branding`);
    revalidatePath('/');
    return {
      ok: `Published. Installed apps will re-theme on their next launch.`,
      version,
      warnings: gate.warnings,
    };
  } catch (e) {
    return { error: message(e) };
  }
}


const PROVIDERS = ['razorpay', 'message_central', 'whatsapp', 'rcs'] as const;
type Provider = (typeof PROVIDERS)[number];

/**
 * Store a per-salon credential. Write-only, all the way down: this action
 * takes a secret and returns nothing about it but its last four characters,
 * which the console already displays.
 *
 * The secret is never echoed back into the form, never logged, and never put
 * in the returned state - a rejected action must not hand the value back to
 * the browser for a "retry with the same value" convenience, because that is
 * how a credential ends up in a React server-action payload and then in a
 * browser devtools tab.
 */
export async function setSecretAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();

  const salonId = String(form.get('salonId') ?? '');
  const provider = String(form.get('provider') ?? '') as Provider;
  const secret = String(form.get('secret') ?? '');
  const publicKeyId = String(form.get('publicKeyId') ?? '').trim() || null;
  const senderId = String(form.get('senderId') ?? '').trim() || null;
  const webhookSecret = String(form.get('webhookSecret') ?? '').trim();

  if (!PROVIDERS.includes(provider)) {
    return { error: 'Unknown provider.' };
  }
  if (!secret.trim()) {
    return { error: 'Paste the credential before saving.' };
  }

  // Message Central is checked BEFORE it is stored, because it is the one
  // credential a customer cannot log in without. A wrong one would otherwise
  // look fine here and fail on the salon's first customer - who would then be
  // sent an OTP from Crayora's fallback account, at Crayora's cost. The check
  // sends no SMS and reads nothing back from Vault: it tests the value the
  // operator has just typed.
  if (provider === 'message_central') {
    if (!publicKeyId) {
      return { error: 'Enter the salon\u2019s Message Central Customer ID as well as its auth token.' };
    }
    const check = await checkMessageCentralCredentials(publicKeyId, secret);
    if (!check.ok) {
      // Nothing is stored. The previous credential, if any, is still in use.
      return { error: `Not saved. ${check.reason}` };
    }
  }

  // Razorpay uses TWO secrets that do different jobs: the key secret signs API
  // calls, and the webhook secret verifies what Razorpay sends back. One opaque
  // string cannot carry both, so they are stored together as JSON - and the
  // webhook secret is required, because without it a payment notification cannot
  // be verified and the only safe response is to refuse every one of them.
  if (provider === 'razorpay') {
    if (!publicKeyId) {
      return { error: 'Enter the salon’s Razorpay Key ID as well as its key secret.' };
    }
    if (!webhookSecret) {
      return {
        error:
          'Enter the webhook secret too. Without it the salon’s payment notifications ' +
          'cannot be verified, and unverified ones are refused - so top-ups would never credit.',
      };
    }
  }

  const stored =
    provider === 'razorpay'
      ? JSON.stringify({ key_secret: secret.trim(), webhook_secret: webhookSecret })
      : secret.trim();

  try {
    await setIntegrationSecret(
      admin.id,
      salonId,
      provider,
      stored,
      publicKeyId,
      // VerifyNow sends under Message Central's own registered sender, so a
      // sender id for Message Central would be stored and never used.
      provider === 'message_central' ? null : senderId,
    );

    if (provider === 'message_central') {
      // It passed the check above, so record that - status `ok`, not the
      // `untested` a save would otherwise leave. Audited like everything else.
      await recordIntegrationTest(
        admin.id,
        salonId,
        'message_central',
        true,
        'Checked on save: token matches the Customer ID and Message Central accepted it. No SMS sent.',
      );
    }

    revalidatePath(`/salon/${salonId}/credentials`);
    revalidatePath('/');
    return {
      ok:
        provider === 'message_central'
          ? 'Saved and checked with Message Central. From now on this salon\u2019s customers ' +
            'get their OTP from its own account, and it pays for them.'
          : `Saved for ${provider.replace('_', ' ')}. It cannot be read back - the console ` +
            `only ever shows the last four characters.`,
    };
  } catch (e) {
    return { error: message(e) };
  }
}


// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

// Rupees in the form, paise in the database. The operator was quoted a price
// in rupees on the phone; storing anything but integer paise is how rounding
// bugs get in (ADR-06).
const rupeesToPaise = (v: FormDataEntryValue | null) => parseRupees(v);

const id = (v: FormDataEntryValue | null) => {
  const s = String(v ?? '').trim();
  return s === '' ? null : s;
};

export async function upsertServiceAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const name = String(form.get('name') ?? '').trim();
  const pricePaise = rupeesToPaise(form.get('priceRupees'));
  const durationMinutes = Number(form.get('durationMinutes') ?? 0);
  const repeat = String(form.get('repeatCycleDays') ?? '').trim();

  if (!name) return { error: 'A service needs a name.' };
  // null, not NaN: the parser refuses anything that is not an amount, so an
  // empty field and "₹four hundred" get the same clear answer (lib/money.ts).
  if (pricePaise === null) return { error: 'Enter the price in rupees, for example 400 or 400.50.' };
  if (!Number.isInteger(durationMinutes) || durationMinutes <= 0) {
    return { error: 'A service must take some time.' };
  }

  try {
    await upsertService(admin.id, salonId, {
      id: id(form.get('id')),
      name,
      pricePaise,
      durationMinutes,
      category: String(form.get('category') ?? '').trim() || null,
      repeatCycleDays: repeat === '' ? null : Number(repeat),
      active: form.get('active') === 'on',
    });
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: `Saved ${name}.` };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function upsertAddOnAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const name = String(form.get('name') ?? '').trim();
  const pricePaise = rupeesToPaise(form.get('priceRupees'));

  if (!name) return { error: 'An add-on needs a name.' };
  if (pricePaise === null) return { error: 'Enter the price in rupees, for example 400 or 400.50.' };

  try {
    await upsertAddOn(admin.id, salonId, {
      id: id(form.get('id')),
      name,
      pricePaise,
      extraDurationMinutes: Number(form.get('extraDurationMinutes') ?? 0) || 0,
      active: form.get('active') === 'on',
    });
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: `Saved ${name}.` };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function upsertStaffAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const name = String(form.get('name') ?? '').trim();
  if (!name) return { error: 'A staff member needs a name.' };

  const skills = String(form.get('skills') ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  try {
    await upsertStaff(admin.id, salonId, {
      id: id(form.get('id')),
      name,
      skills,
      active: form.get('active') === 'on',
    });
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: `Saved ${name}.` };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Operating rules. Note what is absent and stays absent: bonus expiry. It is
 * the owner's setting, made in the app and captured onto each lot at issue
 * (RULES 5.3.3), and paid credit never expires at all. The database refuses a
 * payload that so much as mentions expiry, so a field added here by accident
 * fails loudly rather than quietly relocating that decision.
 */
export async function setRulesAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');

  const topup = rupeesToPaise(form.get('walletTopupRupees'));
  const bonus = rupeesToPaise(form.get('walletBonusRupees'));
  const minTopup = rupeesToPaise(form.get('walletMinTopupRupees'));
  const rewardReferrer = rupeesToPaise(form.get('rewardReferrerRupees'));
  const rewardReferred = rupeesToPaise(form.get('rewardReferredRupees'));
  const cycle = Number(form.get('reminderCycleDays') ?? 0);

  if (topup === null || topup <= 0) {
    return { error: 'The wallet top-up threshold must be a positive amount.' };
  }
  if (bonus === null) {
    return { error: 'Enter the bonus in rupees, for example 50.' };
  }
  if (minTopup === null || minTopup < 0) {
    return { error: 'Enter the smallest top-up in rupees, for example 100.' };
  }
  if (rewardReferrer === null || rewardReferrer < 0 || rewardReferred === null || rewardReferred < 0) {
    return { error: 'Enter both referral rewards in rupees, for example 100 and 50.' };
  }
  if (!Number.isInteger(cycle) || cycle <= 0) {
    return { error: 'The reminder cycle must be a whole number of days.' };
  }

  try {
    await setSalonRules(admin.id, salonId, {
      // The shape the ledger reads, through app.wallet_bonus_for (0058). These
      // three keys and no others: a fourth one here would be a rule the money
      // never applies, which is what min_topup_paise silently was until now.
      wallet_rule: {
        topup_paise: topup,
        bonus_paise: bonus,
        min_topup_paise: minTopup,
      },
      // The shape app.referral_release_reward reads (0071), written here in the
      // same change that defined it.
      reward_rule: {
        referrer_paise: rewardReferrer,
        referred_paise: rewardReferred,
      },
      default_reminder_cycle_days: cycle,
      cancellation_policy: String(form.get('cancellationPolicy') ?? '').trim() || null,
    });
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: 'Rules saved.' };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Render the printable QR pack, store it privately in R2, and hand back a
 * short-lived signed link.
 *
 * Order matters: render, upload, THEN audit. If the upload fails there is no
 * audit row claiming a pack exists; if the audit fails the object is orphaned
 * but harmless - it is private, and a signed URL is never issued for it.
 */
export async function generateQrPackAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');

  const salon = await getJoinCode(salonId);
  if (!salon) return { error: 'No such salon.' };

  let pdf: Uint8Array;
  try {
    pdf = await renderQrPack(salon.display_name, salon.join_code);
  } catch (e) {
    // renderQrPack refuses a name its fonts cannot print, with a sentence
    // written for the operator. Anything else is internal.
    const msg = e instanceof Error ? e.message : '';
    return {
      error: /cannot render/.test(msg) ? msg : 'The QR pack could not be rendered.',
    };
  }

  // Sortable timestamp in the key, so "latest" is a string sort and every
  // regeneration is kept rather than overwritten.
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const key = `salons/${salonId}/qr-pack/${stamp}-${salon.join_code}.pdf`;

  try {
    await putObject(key, pdf, 'application/pdf');
    await recordAsset(admin.id, salonId, 'qr_pack', key);
    const url = await signedUrl(key, 600);
    revalidatePath(`/salon/${salonId}/qr`);
    return { ok: 'QR pack generated. The link below works for 10 minutes.', url };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Messaging trial (0032). Until it ends, the salon's customer OTPs are sent
 * from Crayora's Message Central account, intentionally - so a salon can go
 * live before it has set up its own. Every day is Crayora's money, so the
 * reason is required and the length is capped (365 days) in the database.
 */
export async function setTrialAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const days = Number(String(form.get('days') ?? '').trim());
  const reason = String(form.get('reason') ?? '').trim();

  if (!Number.isInteger(days) || days < 0) {
    return { error: 'Enter the trial length as a whole number of days (0 ends it now).' };
  }
  if (!reason) {
    return { error: 'A reason is required - Crayora pays for every OTP sent under a trial.' };
  }

  try {
    const ends = await setMessagingTrial(admin.id, salonId, days, reason);
    revalidatePath('/');
    return {
      ok:
        days === 0
          ? 'Trial ended. From now on, OTPs use the salon’s own account - or, if it has none, Crayora’s as an alerted fallback.'
          : `Trial granted until ${new Date(ends).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}. Until then Crayora pays for this salon’s OTPs.`,
    };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Messaging grace (0033). After the trial, a further period during which
 * Crayora still sends the salon's OTPs. When it ends, a salon with no Message
 * Central account of its own is BLOCKED - so the reason is required.
 */
export async function setGraceAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const days = Number(String(form.get('days') ?? '').trim());
  const reason = String(form.get('reason') ?? '').trim();

  if (!Number.isInteger(days) || days < 0) {
    return { error: 'Enter the grace period as a whole number of days (0 ends it now).' };
  }
  if (!reason) {
    return { error: 'A reason is required - when grace ends, the salon is blocked.' };
  }

  try {
    const ends = await setMessagingGrace(admin.id, salonId, days, reason);
    revalidatePath('/');
    const when = new Date(ends).toLocaleDateString('en-IN', {
      day: 'numeric', month: 'short', year: 'numeric',
    });
    return {
      ok:
        days === 0
          ? 'Grace ended. If this salon has no Message Central account of its own, it is now blocked.'
          : `Grace runs until ${when}. After that, unless you have entered the salon’s own Message Central account under Credentials, it is blocked.`,
    };
  } catch (e) {
    return { error: message(e) };
  }
}

// ---------------------------------------------------------------------------
// Customer binding (K12) - super-admin only. The database enforces that
// (0036); the checks here only turn a refusal into a sentence.
// ---------------------------------------------------------------------------

export type BindingState = {
  error?: string;
  ok?: string;
  /** The number exactly as looked up, carried to the unbind/transfer forms. */
  phone?: string;
  result?: BindingLookup;
};

const SUPER_ONLY =
  'Customer binding is for a Crayora super-admin only. Ask one to handle this - every action here moves a customer between businesses.';


export async function lookupBindingAction(
  _prev: BindingState,
  form: FormData,
): Promise<BindingState> {
  const admin = await requireAdmin();
  if (!admin.isSuper) return { error: SUPER_ONLY };

  const p = phone.safeParse(String(form.get('phone') ?? ''));
  if (!p.success) return { error: 'Enter the customer’s complete 10-digit mobile number.' };
  const reason = String(form.get('reason') ?? '').trim();
  if (!reason) return { error: 'A reason is required - every lookup is recorded against your name.' };

  try {
    const result = await lookupBinding(admin.id, p.data, reason);
    return { phone: p.data, result };
  } catch (e) {
    return { error: message(e) };
  }
}

/** Offer (or stop offering) an add-on with a service. */
export async function setServiceAddOnAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const serviceId = String(form.get('serviceId') ?? '');
  const addOnId = String(form.get('addOnId') ?? '');
  const linked = form.get('linked') === 'true';

  try {
    await setServiceAddOn(admin.id, salonId, serviceId, addOnId, linked);
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: linked ? 'Offered with this service.' : 'No longer offered with this service.' };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Carry out a customer's erasure request (DPDP s.12(3)). Crayora is the
 * escalation when a salon has not answered; the salon is the Data Fiduciary.
 */
export async function carryOutErasureAction(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const admin = await requireAdmin();
  const requestId = String(form.get('requestId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();

  if (reason.length < 10) {
    return { error: 'Write down why, in a sentence - it is the audit entry for this erasure.' };
  }

  try {
    await carryOutErasure(admin.id, requestId, reason);
    revalidatePath('/data-rights');
    return {
      ok: 'Erased. Name, number and birthday are gone; the financial records stay, anonymised. The request is closed with that outcome.',
    };
  } catch (e) {
    return { error: message(e) };
  }
}

/**
 * Ledger caller 5 - the ONLY human path to a customer's balance anywhere in the
 * product. Super-admin only, reason required, audited twice over: once by the
 * correction and once by how the customer was found.
 */
export async function walletCorrectAction(
  _prev: BindingState,
  form: FormData,
): Promise<BindingState> {
  const admin = await requireAdmin();
  if (!admin.isSuper) return { error: SUPER_ONLY };

  const number = String(form.get('phone') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  const direction = String(form.get('direction') ?? '');
  // parseRupees takes rupees as typed and returns PAISE. Named for what it
  // holds, because a variable called `rupees` holding paise is a x100 bug
  // waiting for the next person to touch this.
  const paise = parseRupees(String(form.get('amount') ?? ''));

  if (direction !== 'credit' && direction !== 'debit') {
    return { error: 'Choose whether this adds to or takes from the balance.' };
  }
  if (paise === null || paise <= 0) {
    return { error: 'Enter the correction in rupees, greater than zero.' };
  }
  if (reason.length < 20) {
    return {
      error:
        'A correction moves a customer\'s money. Write what went wrong and how you verified it - at least a full sentence.',
    };
  }

  try {
    await walletCorrectByPhone(
      admin.id,
      number,
      direction === 'credit' ? paise : -paise,
      reason,
    );
    return { ok: 'Corrected. The ledger has a new row with your name and reason; nothing was edited.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function unbindAction(_prev: BindingState, form: FormData): Promise<BindingState> {
  const admin = await requireAdmin();
  if (!admin.isSuper) return { error: SUPER_ONLY };

  const number = String(form.get('phone') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  if (reason.length < 10) {
    return { error: 'Write down why, in a sentence - it is the audit entry for this unbind.' };
  }

  try {
    await unbindCustomer(admin.id, number, reason);
    return {
      ok: 'Unbound. The customer was signed out everywhere and can now join a salon by entering its code.',
    };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function transferAction(_prev: BindingState, form: FormData): Promise<BindingState> {
  const admin = await requireAdmin();
  if (!admin.isSuper) return { error: SUPER_ONLY };

  const number = String(form.get('phone') ?? '');
  const toSalonId = String(form.get('toSalonId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  const acknowledged = parseRupees(String(form.get('acknowledged') ?? ''));

  if (!toSalonId) return { error: 'Choose the salon the customer is moving to.' };
  if (reason.length < 10) {
    return { error: 'Write down why, in a sentence - it is the audit entry for this transfer.' };
  }
  if (acknowledged === null) {
    return { error: 'Enter the balance you told the customer, in rupees - for example 550 or 550.50.' };
  }
  if (form.get('told') !== 'on') {
    return {
      error:
        'Tick the box only once you have told the customer: their balance stays with the old salon and cannot be moved or refunded.',
    };
  }

  try {
    await transferCustomer(admin.id, number, toSalonId, reason, acknowledged);
    return {
      ok: 'Transferred. The customer was signed out everywhere; their next login opens the new salon, starting fresh. Their old wallet and history stay with the old salon.',
    };
  } catch (e) {
    return { error: message(e) };
  }
}

// ---------------------------------------------------------------------------
// Offboarding (M12). The database enforces super-admin, purge-due, the export
// offer and the credit settlement; these only turn its sentence into a message.
// ---------------------------------------------------------------------------

export async function exportOfferedAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const note = String(form.get('note') ?? '').trim();
  if (!note) return { error: 'Say how the export was offered, and when.' };
  try {
    await recordExportOffered(admin.id, salonId, note);
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: 'Recorded.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function creditSettledAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const note = String(form.get('note') ?? '').trim();
  if (!note) return { error: 'Say how the salon settled its customers’ credit.' };
  try {
    await recordCreditSettlement(admin.id, salonId, note);
    revalidatePath(`/salon/${salonId}/billing`);
    return { ok: 'Recorded. The balances stay in the books beside this note.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function purgeAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  const typedName = String(form.get('typedName') ?? '');
  if (!reason) return { error: 'A reason is required - it is the audit entry.' };
  try {
    const r = await purgeSalon(admin.id, salonId, reason, typedName);
    revalidatePath(`/salon/${salonId}/billing`);
    revalidatePath('/');
    return r.already
      ? { ok: 'This salon was already purged.' }
      : {
          ok:
            `Purged. ${r.customers_anonymised ?? 0} customers anonymised, ` +
            `${r.bindings_released ?? 0} bindings released, ${r.staff_closed ?? 0} staff accounts closed. ` +
            'Every financial record was kept.',
        };
  } catch (e) {
    return { error: message(e) };
  }
}

// ---------------------------------------------------------------------------
// Support mode (RULES 6.8)
// ---------------------------------------------------------------------------

export async function startSupportAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  const minutes = Number(form.get('minutes') ?? 60);
  if (!reason) return { error: 'A reason is required - what is the ticket?' };
  try {
    await startSupportSession(admin.id, salonId, reason, minutes);
    revalidatePath(`/salon/${salonId}/support`);
    return { ok: 'Support session started.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function endSupportAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const sessionId = String(form.get('sessionId') ?? '');
  try {
    await endSupportSession(admin.id, sessionId);
    revalidatePath(`/salon/${salonId}/support`);
    return { ok: 'Session ended.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function unmaskAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const customerId = String(form.get('customerId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  if (!reason) return { error: 'Un-masking needs its own reason.' };
  try {
    const phone = await supportUnmaskPhone(admin.id, customerId, reason);
    return { ok: phone ?? 'This customer has no number on record (anonymised).' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function accessSentAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const requestId = String(form.get('requestId') ?? '');
  const howSent = String(form.get('howSent') ?? '').trim();
  if (!howSent) return { error: 'Say how the copy reached the customer.' };
  try {
    await completeAccessRequest(admin.id, requestId, howSent);
    revalidatePath('/data-rights');
    return { ok: 'Closed. The customer sees the outcome under Your data.' };
  } catch (e) {
    return { error: message(e) };
  }
}

export async function reactivateAction(_prev: ActionState, form: FormData): Promise<ActionState> {
  const admin = await requireAdmin();
  const salonId = String(form.get('salonId') ?? '');
  const reason = String(form.get('reason') ?? '').trim();
  if (!reason) return { error: 'A reason is required - why was the suspension lifted?' };
  try {
    await reactivateSalon(admin.id, salonId, reason);
    revalidatePath('/');
    return { ok: 'Salon reactivated.' };
  } catch (e) {
    return { error: message(e) };
  }
}
