'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserSupabase } from '@/server/supabase-browser';

type Stage =
  | { kind: 'loading' }
  | { kind: 'enrol'; factorId: string; qr: string; secret: string }
  | { kind: 'challenge'; factorId: string }
  | { kind: 'signedout' };

/**
 * TOTP enrolment and challenge.
 *
 * Two states look similar and are not: an account with no factor needs to
 * enrol, and an account with a verified factor needs to be challenged. Both
 * end in the same place - a session at aal2 - but only the second one happens
 * on every sign-in.
 */
export function MfaFlow() {
  const router = useRouter();
  const supabase = browserSupabase();
  const [stage, setStage] = useState<Stage>({ kind: 'loading' });
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) {
        setStage({ kind: 'signedout' });
        return;
      }

      // `listFactors().totp` is already filtered to VERIFIED factors; anything
      // half-enrolled only appears in `all`. Reading the wrong one would send
      // an operator who never finished enrolment into a challenge they cannot
      // answer.
      const { data: factors } = await supabase.auth.mfa.listFactors();
      const verified = factors?.totp?.[0];
      if (verified) {
        setStage({ kind: 'challenge', factorId: verified.id });
        return;
      }

      // Clear an abandoned enrolment rather than piling up a new factor on
      // every visit to this page.
      const pending = factors?.all?.find(
        (f) => f.factor_type === 'totp' && f.status === 'unverified',
      );
      if (pending) {
        await supabase.auth.mfa.unenroll({ factorId: pending.id });
      }

      const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp' });
      if (error || !data) {
        setError('Could not start two-factor enrolment.');
        return;
      }
      setStage({
        kind: 'enrol',
        factorId: data.id,
        qr: data.totp.qr_code,
        secret: data.totp.secret,
      });
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    if (stage.kind !== 'enrol' && stage.kind !== 'challenge') return;
    setBusy(true);
    setError(null);

    const factorId = stage.factorId;
    const { data: challenge, error: cErr } = await supabase.auth.mfa.challenge({ factorId });
    if (cErr || !challenge) {
      setError('Could not start the challenge. Try again.');
      setBusy(false);
      return;
    }

    const { error: vErr } = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code: code.trim(),
    });
    if (vErr) {
      setError('That code was not accepted. Codes expire every 30 seconds.');
      setBusy(false);
      return;
    }

    router.push('/');
    router.refresh();
  }

  if (stage.kind === 'loading') return <p className="hint">Checking your account…</p>;

  if (stage.kind === 'signedout') {
    return (
      <>
        <div className="error">You are not signed in.</div>
        <div className="actions">
          <button type="button" onClick={() => router.push('/login')}>
            Back to sign in
          </button>
        </div>
      </>
    );
  }

  return (
    <form onSubmit={verify}>
      {error && <div className="error">{error}</div>}

      {stage.kind === 'enrol' && (
        <>
          <p className="hint" style={{ marginTop: 0 }}>
            Scan this with an authenticator app, then enter the six-digit code it shows.
          </p>
          {/* Supabase returns the QR as an SVG data URI. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={stage.qr} alt="Two-factor QR code" width={200} height={200} />
          <p className="hint">
            Can’t scan? Enter this key manually:{' '}
            <code style={{ fontFamily: 'ui-monospace, monospace' }}>{stage.secret}</code>
          </p>
        </>
      )}

      <label htmlFor="code">Six-digit code</label>
      <input
        id="code"
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9]{6}"
        maxLength={6}
        required
        value={code}
        onChange={(e) => setCode(e.target.value)}
      />
      <div className="actions">
        <button disabled={busy || code.trim().length !== 6}>
          {busy ? 'Verifying…' : stage.kind === 'enrol' ? 'Enable two-factor' : 'Verify'}
        </button>
      </div>
    </form>
  );
}
