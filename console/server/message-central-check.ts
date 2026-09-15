import 'server-only';

/**
 * Check a salon's Message Central credentials BEFORE storing them - without
 * sending an SMS, and without ever reading a stored secret back.
 *
 * This runs on the value the operator has just typed into the form, at the
 * moment of saving. It never touches Vault, so it sits entirely outside the
 * write-only rule (ARCHITECTURE 8.2, GATE-7): the console is holding this
 * value for the length of one request because the operator handed it over,
 * not because it went and fetched it.
 *
 * Why at save time: a mistyped Customer ID or a token copied from the wrong
 * account would otherwise be stored, look fine in the console, and fail on the
 * first customer who tries to log in - who then gets an OTP from Crayora's
 * fallback account, or none at all.
 *
 * Two checks, both measured against the live Message Central API on
 * 2026-09-15 before being relied on:
 *
 *  1. The token names its own account. It is a JWT whose `sub` claim is the
 *     Customer ID, so a token from one account pasted beside another
 *     account's ID is caught without any network call at all.
 *
 *  2. Message Central accepts it. validateOtp on a verification that does not
 *     exist SENDS NOTHING, and answers:
 *        genuine, active token   -> 400, responseCode 505 ("verificationId is
 *                                   invalid or expired") - authentication passed
 *        anything else           -> 401
 *     Message Central verifies the signature: a token with its signature or
 *     payload altered is refused. (An early probe that changed only the LAST
 *     character "passed" - because that character held base64 padding bits and
 *     the signature was byte-for-byte unchanged. It proved nothing, and was
 *     not taken as evidence.)
 */

const BASE = (process.env.MESSAGE_CENTRAL_BASE_URL ?? 'https://cpaas.messagecentral.com').replace(
  /\/+$/,
  '',
);

export type CheckResult = { ok: true } | { ok: false; reason: string };

function tokenSubject(token: string): string | null {
  const parts = token.split('.');
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const json = Buffer.from(parts[1], 'base64url').toString('utf8');
    const claims = JSON.parse(json) as { sub?: unknown; exp?: unknown };
    return typeof claims.sub === 'string' ? claims.sub : null;
  } catch {
    return null;
  }
}

function tokenExpired(token: string): boolean {
  try {
    const claims = JSON.parse(Buffer.from(token.split('.')[1] ?? '', 'base64url').toString('utf8'));
    return typeof claims.exp === 'number' && claims.exp * 1000 < Date.now();
  } catch {
    return false;
  }
}

export async function checkMessageCentralCredentials(
  customerId: string,
  authToken: string,
): Promise<CheckResult> {
  const id = customerId.trim();
  const token = authToken.trim();

  if (!/^C-[A-Z0-9]{6,}$/i.test(id)) {
    return {
      ok: false,
      reason:
        'That does not look like a Message Central Customer ID. It starts with "C-", ' +
        'for example C-84AF935335B54FC.',
    };
  }

  // 1. The pair must belong together.
  const sub = tokenSubject(token);
  if (!sub) {
    return {
      ok: false,
      reason:
        'That is not a Message Central auth token. It is a long value starting with "eyJ", ' +
        'from the Message Central dashboard.',
    };
  }
  if (sub.toUpperCase() !== id.toUpperCase()) {
    return {
      ok: false,
      reason:
        'This auth token belongs to a different Message Central account than the Customer ID ' +
        'entered. Copy both from the same salon’s dashboard.',
    };
  }
  if (tokenExpired(token)) {
    return { ok: false, reason: 'This auth token has expired. Generate a new one in Message Central.' };
  }

  // 2. Message Central must accept it. Sends nothing.
  try {
    const res = await fetch(
      `${BASE}/verification/v3/validateOtp?verificationId=1&code=000000&flowType=SMS`,
      { headers: { authToken: token }, signal: AbortSignal.timeout(10_000) },
    );
    if (res.status === 401 || res.status === 403) {
      return {
        ok: false,
        reason: 'Message Central rejected this auth token. It may have been revoked or mistyped.',
      };
    }
    // 400/505 means authentication passed and only the (deliberately bogus)
    // verification was unknown. Anything else is an outage, not a verdict.
    const body = (await res.json().catch(() => null)) as { responseCode?: number } | null;
    if (res.status === 400 && body?.responseCode === 505) return { ok: true };
    return {
      ok: false,
      reason: `Message Central gave an unexpected answer (HTTP ${res.status}). Try again in a minute.`,
    };
  } catch {
    return { ok: false, reason: 'Could not reach Message Central to check these credentials.' };
  }
}
