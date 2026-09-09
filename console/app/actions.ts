'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { validateBranding, type BrandInput } from '@cray/design-tokens';
import { requireAdmin } from '@/server/auth';
import {
  activateSalon,
  provisionSalon,
  publishBranding,
  recordSetupFee,
  setIntegrationSecret,
  setSalonRules,
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

export type ActionState = { error?: string; ok?: string; joinCode?: string };

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

  if (status !== 'unpaid' && status !== 'paid' && status !== 'waived') {
    return { error: 'Status must be unpaid, paid or waived.' };
  }

  try {
    await recordSetupFee(admin.id, salonId, status, reference, paidOn);
    revalidatePath('/');
    return { ok: 'Setup fee recorded.' };
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

  try {
    const version = await publishBranding(
      admin.id,
      salonId,
      input as unknown as Record<string, never>,
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

  if (!PROVIDERS.includes(provider)) {
    return { error: 'Unknown provider.' };
  }
  if (!secret.trim()) {
    return { error: 'Paste the credential before saving.' };
  }

  try {
    await setIntegrationSecret(admin.id, salonId, provider, secret, publicKeyId, senderId);
    revalidatePath(`/salon/${salonId}/credentials`);
    revalidatePath('/');
    return {
      ok:
        `Saved for ${provider.replace('_', ' ')}. It cannot be read back - the console ` +
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
const rupeesToPaise = (v: FormDataEntryValue | null) =>
  Math.round(Number(String(v ?? '0')) * 100);

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
  if (!Number.isFinite(pricePaise) || pricePaise < 0) return { error: 'Price is not a number.' };
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
  if (!Number.isFinite(pricePaise) || pricePaise < 0) return { error: 'Price is not a number.' };

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
  const cycle = Number(form.get('reminderCycleDays') ?? 0);

  if (!Number.isFinite(topup) || topup <= 0) {
    return { error: 'The wallet top-up threshold must be a positive amount.' };
  }
  if (!Number.isFinite(bonus) || bonus < 0) {
    return { error: 'The bonus cannot be negative.' };
  }
  if (!Number.isInteger(cycle) || cycle <= 0) {
    return { error: 'The reminder cycle must be a whole number of days.' };
  }

  try {
    await setSalonRules(admin.id, salonId, {
      wallet_rule: { topup_paise: topup, bonus_paise: bonus },
      default_reminder_cycle_days: cycle,
      cancellation_policy: String(form.get('cancellationPolicy') ?? '').trim() || null,
    });
    revalidatePath(`/salon/${salonId}/catalogue`);
    return { ok: 'Rules saved.' };
  } catch (e) {
    return { error: message(e) };
  }
}
