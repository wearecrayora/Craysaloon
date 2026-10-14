// otp-verify (ADR-36)
//
// Checks the code with Message Central and, ONLY if Message Central says
// VERIFICATION_COMPLETED, binds the number to the salon (first login) and then
// issues a Supabase session.
//
//   POST { challenge_id, code, consents?: { promotional?, whatsapp? },
//          age?: { adult, guardian_name?, guardian_confirms? } }
//     ->  200 { outcome, access_token, refresh_token, ... }
//     ->  409 already_bound | account_conflict,  403 salon_unavailable
//
// The client names neither the phone nor the salon. Both come from the
// challenge the server issued, so a code cannot be checked against a
// verification the client did not start, and a login cannot be moved to a
// different salon by editing a request.

import { mcValidate, platformCreds, type McCreds } from '../_shared/message-central.ts';
import { admin, alert, json, serve } from '../_shared/runtime.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CODE = /^[0-9]{4,8}$/;

serve('otp', 'otp-verify', async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  let challengeId: unknown;
  let code: unknown;
  let rawConsents: unknown;
  let rawAge: unknown;
  try {
    ({ challenge_id: challengeId, code, consents: rawConsents, age: rawAge } = await req.json());
  } catch {
    return json(400, { error: 'invalid_request' });
  }
  // Age (0110). Under 18 needs a named parent or guardian who confirmed - and a
  // child is sent no marketing, whatever was ticked (DPDP s.9). Checked before
  // the code, so a refused declaration never costs an attempt.
  const a = (rawAge ?? null) as Record<string, unknown> | null;
  const age = a && typeof a.adult === 'boolean'
    ? {
        adult: a.adult,
        guardian_name: typeof a.guardian_name === 'string' ? a.guardian_name.trim().slice(0, 120) : null,
        guardian_confirms: a.guardian_confirms === true,
      }
    : null;
  if (age && !age.adult && (!age.guardian_name || age.guardian_name.length < 2 || !age.guardian_confirms)) {
    return json(400, { error: 'guardian_required' });
  }
  // Marketing consent is opt-in: only a literal `true` counts, anything else
  // (missing, "yes", 1) is a no. Service messages are the service itself and
  // photos are never asked for here, so neither is the client's to set.
  const c = (rawConsents ?? {}) as Record<string, unknown>;
  const child = age !== null && !age.adult;
  const consents = {
    promotional: !child && c.promotional === true,
    whatsapp: !child && c.whatsapp === true,
  };
  // Shape checks first: a malformed request never costs an attempt.
  if (typeof challengeId !== 'string' || !UUID.test(challengeId)) {
    return json(400, { error: 'expired' });
  }
  if (typeof code !== 'string' || !CODE.test(code)) {
    return json(400, { error: 'wrong_code' });
  }

  const db = admin();

  // 1. Count the attempt BEFORE checking, so a failure is always charged.
  const { data: att } = await db.rpc('otp_attempt', { p_challenge_id: challengeId });
  if (!att?.ok) {
    // expired | too_many_attempts. A decoy challenge id from otp-send lands
    // here as "expired", identical to a real one.
    return json(400, { error: att?.reason ?? 'expired' });
  }

  // 2. Validate with the SAME account that sent it. A code sent from
  //    Crayora's account - as a fallback, or under a messaging trial - can
  //    only be checked against Crayora's account.
  let creds: McCreds | null = null;
  if (att.sender === 'salon') {
    const { data: s } = await db.rpc('otp_salon_sender', { p_salon_id: att.salon_id });
    creds = s ? { customerId: s.customer_id, authToken: s.auth_token } : null;
  } else {
    creds = platformCreds();
  }
  if (!creds) {
    await alert('otp_verify_no_credentials', { salon_id: att.salon_id, sender: att.sender });
    return json(503, { error: 'verify_unavailable' });
  }

  const checked = await mcValidate(creds, att.verification_id, code);
  if (!checked.ok) {
    // Status word only - never the code, the token or the verification id.
    console.log(JSON.stringify({ otp_verify_failed: checked.reason }));
    if (checked.expired) {
      // Message Central's code has died (about 60 seconds). The app should
      // offer a resend, not ask the customer to retype a code that was right.
      return json(400, { error: 'expired' });
    }
    return json(400, { error: 'wrong_code', attempts_left: att.attempts_left });
  }

  // 3. Message Central confirmed. Consume the challenge - a second completion
  //    of the same verification must never produce a second session.
  const { data: done } = await db.rpc('otp_complete', { p_challenge_id: challengeId });
  if (!done?.ok) return json(400, { error: 'expired' });

  const identity: string = done.identity;
  let userId: string | null = done.auth_user_id ?? null;

  // 4. First login: create the account and record that WE created it.
  if (!userId) {
    const { data: created, error } = await db.auth.admin.createUser({
      email: identity,
      email_confirm: true,
      // Not `provider`: Supabase reserves that key and silently overwrites it
      // with 'email' - observed on the first live account, 2026-09-15.
      app_metadata: { signup_via: 'message_central_otp' },
    });

    if (error) {
      // An account already exists at this synthetic address, and we have no
      // record of creating it. That is what account pre-hijacking looks like
      // (0031): someone signed up at a customer's address first, with a
      // password they know. Never adopt it.
      await alert('otp_refused_unowned_identity', { salon_id: done.salon_id });
      return json(409, { error: 'account_conflict' });
    }

    userId = created.user.id;
    const { error: linkErr } = await db.rpc('otp_link_identity', {
      p_challenge_id: challengeId,
      p_auth_user_id: userId,
    });
    if (linkErr) {
      await alert('otp_identity_not_recorded', { salon_id: done.salon_id });
      return json(500, { error: 'internal' });
    }
  }

  // 5. Bind, in the same step as first login (RULES 4.3), BEFORE any session
  //    exists. A refused binding must never leave the customer holding a
  //    token, so this runs first and a refusal ends the request here.
  const { data: fin, error: finErr } = await db.rpc('otp_finish_login', {
    p_challenge_id: challengeId,
    p_auth_user_id: userId,
    p_consents: consents,
  });
  if (finErr || !fin) {
    await alert('otp_finish_login_failed', { salon_id: done.salon_id });
    return json(500, { error: 'internal' });
  }
  if (!fin.ok) {
    switch (fin.reason) {
      case 'already_bound':
        // RULES 4.4: the response names no salon. The app says only that
        // this number belongs to another salon, and to ask that salon or
        // Crayora support.
        return json(409, { error: 'already_bound' });
      case 'salon_unavailable':
        return json(403, { error: 'salon_unavailable' });
      default:
        await alert('otp_refused_account_conflict', { salon_id: done.salon_id });
        return json(409, { error: 'account_conflict' });
    }
  }

  // 5b. The age the person declared, against the customer just bound or
  //     returning (0110). Staff logins record nothing. A failure here is
  //     alerted, never a reason to refuse a login that has already bound.
  if (age && fin.outcome !== 'staff') {
    const { data: rec, error: recErr } = await db.rpc('record_age_declaration', {
      p_auth_user_id: userId,
      p_age: age,
    });
    if (recErr || !rec?.ok) await alert('otp_age_not_recorded', { salon_id: done.salon_id });
  }

  // 6. Mint the session. generateLink returns a single-use token and SENDS
  //    NOTHING; verifyOtp exchanges it. Verified single-use, 2026-09-15.
  const { data: link, error: linkError } = await db.auth.admin.generateLink({
    type: 'magiclink',
    email: identity,
  });
  if (linkError || !link?.properties?.hashed_token) {
    await alert('otp_session_link_failed', { salon_id: done.salon_id });
    return json(500, { error: 'internal' });
  }

  // Belt and braces: the account the link was issued for must be the one we
  // own. If these ever differ, something has rewritten the mapping.
  if (link.user?.id !== userId) {
    await alert('otp_identity_mismatch', { salon_id: done.salon_id });
    return json(409, { error: 'account_conflict' });
  }

  const { data: verified, error: verifyErr } = await db.auth.verifyOtp({
    token_hash: link.properties.hashed_token,
    type: 'magiclink',
  });
  if (verifyErr || !verified?.session) {
    await alert('otp_session_mint_failed', { salon_id: done.salon_id });
    return json(500, { error: 'internal' });
  }

  const s = verified.session;
  return json(200, {
    // bound | returning | staff - so the app knows whether to say welcome.
    outcome: fin.outcome,
    access_token: s.access_token,
    refresh_token: s.refresh_token,
    expires_in: s.expires_in,
    expires_at: s.expires_at,
    token_type: s.token_type,
  });
});
