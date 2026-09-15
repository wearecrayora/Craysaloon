// Message Central VerifyNow (ADR-36).
//
// VerifyNow GENERATES, sends and verifies the OTP. We never see the code on
// the way out, and on the way back we only forward what the customer typed.
// Checked against Message Central's API docs, 2026-09-15:
//
//   POST /verification/v3/send          countryCode, customerId, flowType,
//                                       mobileNumber, otpLength   -> verificationId
//   GET  /verification/v3/validateOtp   verificationId, code, flowType
//                                       -> data.verificationStatus
//   Auth: header `authToken`
//
// NOTHING in this file logs a token, a code, a verificationId or a phone
// number. A log line is readable by more people than the database is, and
// every one of those values is enough on its own to cause harm.

export type McCreds = { customerId: string; authToken: string };

const BASE = (Deno.env.get('MESSAGE_CENTRAL_BASE_URL') ?? 'https://cpaas.messagecentral.com')
  .replace(/\/+$/, '');

// Six digits, not VerifyNow's default of four. A four-digit code is 10,000
// guesses; with five attempts per challenge that is a 1-in-2,000 chance of
// guessing it, which is not a login.
const OTP_LENGTH = 6;

// Message Central can be slow; a customer staring at a spinner for thirty
// seconds will tap "resend", which costs the salon a second SMS.
const TIMEOUT_MS = 10_000;

/** Crayora's own account: the logged, alerted fallback (RULES 7.1.3). */
export function platformCreds(): McCreds | null {
  const customerId = Deno.env.get('MESSAGE_CENTRAL_CUSTOMER_ID');
  const authToken = Deno.env.get('MESSAGE_CENTRAL_AUTH_KEY');
  if (!customerId || !authToken) return null;
  return { customerId, authToken };
}

async function call(url: string, init: RequestInit): Promise<{ status: number; body: any }> {
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
  let body: any = null;
  try {
    body = await res.json();
  } catch {
    // A non-JSON body from a provider is itself a failure, not a crash.
  }
  return { status: res.status, body };
}

export type SendResult =
  // timeoutSeconds is how long Message Central will accept the code. Measured
  // 2026-09-15: 60 seconds. It is returned so the app's countdown tells the
  // truth - our own challenge lives longer, but the code does not.
  | { ok: true; verificationId: string; timeoutSeconds: number }
  | { ok: false; reason: string };

export async function mcSend(creds: McCreds, mobile: string, countryCode = '91'): Promise<SendResult> {
  const q = new URLSearchParams({
    countryCode,
    customerId: creds.customerId,
    flowType: 'SMS',
    mobileNumber: mobile,
    otpLength: String(OTP_LENGTH),
  });

  try {
    const { status, body } = await call(`${BASE}/verification/v3/send?${q}`, {
      method: 'POST',
      headers: { authToken: creds.authToken },
    });
    const id = body?.data?.verificationId;
    if (status === 200 && body?.responseCode === 200 && id) {
      const t = Number(body?.data?.timeout);
      return { ok: true, verificationId: String(id), timeoutSeconds: Number.isFinite(t) && t > 0 ? t : 60 };
    }
    // The provider's own response code is safe to report; the body is not
    // echoed, because it can carry the mobile number.
    return { ok: false, reason: `http_${status}_mc_${body?.responseCode ?? 'none'}` };
  } catch (e) {
    return { ok: false, reason: e instanceof DOMException && e.name === 'TimeoutError' ? 'timeout' : 'network' };
  }
}

// `expired` is separated from every other failure on purpose. A customer who
// typed the RIGHT code a little too slowly must be told to resend, not that
// the code was wrong - otherwise they retype the same correct code and burn
// their attempts on a verification that can no longer succeed.
export type ValidateResult =
  | { ok: true }
  | { ok: false; expired: boolean; reason: string };

export async function mcValidate(
  creds: McCreds,
  verificationId: string,
  code: string,
): Promise<ValidateResult> {
  const q = new URLSearchParams({ verificationId, code, flowType: 'SMS' });

  try {
    const { status, body } = await call(`${BASE}/verification/v3/validateOtp?${q}`, {
      method: 'GET',
      headers: { authToken: creds.authToken },
    });
    // Only an explicit VERIFICATION_COMPLETED counts. A 200 with any other
    // status - or a 200 with no status at all - is a failure. Treating
    // "didn't error" as "verified" is how a login gets issued for a wrong code.
    if (status === 200 && body?.data?.verificationStatus === 'VERIFICATION_COMPLETED') {
      return { ok: true };
    }
    // Message Central reports a failed check in the TOP-LEVEL fields, not in
    // data.verificationStatus - found by asking it directly, 2026-09-15:
    //   { "responseCode": 705, "message": "VERIFICATION_EXPIRED" }
    // The code and message are status words, safe to log; the body is not.
    const message = String(body?.message ?? body?.data?.verificationStatus ?? '');
    const code = body?.responseCode ?? status;
    return {
      ok: false,
      expired: code === 705 || /EXPIRED/i.test(message),
      reason: `mc_${code}_${message || 'unknown'}`,
    };
  } catch (e) {
    return {
      ok: false,
      expired: false,
      reason: e instanceof DOMException && e.name === 'TimeoutError' ? 'timeout' : 'network',
    };
  }
}
