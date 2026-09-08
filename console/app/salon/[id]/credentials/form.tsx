'use client';

import { useActionState, useRef } from 'react';
import type { IntegrationRow } from '@/server/admin-db';
import { setSecretAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

const STATUS_NOTE: Record<IntegrationRow['status'], string> = {
  missing: 'No credential stored.',
  untested: 'Stored, never verified against the provider.',
  ok: 'Last test succeeded.',
  failing: 'Last test failed. Payments or messages on this channel will fail closed.',
};

export function CredentialForm({
  salonId,
  row,
  label,
  blurb,
}: {
  salonId: string;
  row: IntegrationRow;
  label: string;
  blurb: string;
}) {
  const [state, save, saving] = useActionState(setSecretAction, empty);
  const secretRef = useRef<HTMLInputElement>(null);

  return (
    <form
      action={(fd) => {
        save(fd);
        // Clear the field the moment it is submitted. Leaving a credential
        // sitting in a DOM node after it has been stored is a screen-share or
        // a devtools tab away from being read, and there is no reason to keep
        // it: the value can never be shown again anyway.
        if (secretRef.current) secretRef.current.value = '';
      }}
      className="card"
    >
      <input type="hidden" name="salonId" value={salonId} />
      <input type="hidden" name="provider" value={row.provider} />

      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <h2 style={{ margin: 0 }}>{label}</h2>
        <span className={`pill ${row.status === 'ok' ? 'active' : row.status === 'failing' ? 'suspended' : 'setup'}`}>
          {row.status}
        </span>
        {row.has_secret && row.last4 && (
          <span style={{ color: 'var(--ink-soft)', fontSize: 13, fontFamily: 'ui-monospace, monospace' }}>
            ••••{row.last4}
          </span>
        )}
        {row.last_tested_at && (
          <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            tested {new Date(row.last_tested_at).toLocaleDateString('en-IN')}
          </span>
        )}
      </div>
      <p className="hint" style={{ margin: '6px 0 0' }}>{blurb}</p>
      <p className="hint" style={{ margin: '2px 0 12px' }}>{STATUS_NOTE[row.status]}</p>

      {state.error && <div className="error">{state.error}</div>}
      {state.ok && <div className="notice">{state.ok}</div>}

      <div className="row">
        <div>
          <label htmlFor={`secret-${row.provider}`}>
            {row.has_secret ? 'Replace the secret' : 'Secret'}
          </label>
          <input
            id={`secret-${row.provider}`}
            name="secret"
            ref={secretRef}
            type="password"
            autoComplete="off"
            spellCheck={false}
            placeholder={row.has_secret ? 'Paste a new value to rotate' : 'Paste the credential'}
          />
        </div>
        <div>
          <label htmlFor={`pk-${row.provider}`}>
            {row.provider === 'razorpay' ? 'Key id' : 'Public identifier'}
          </label>
          <input
            id={`pk-${row.provider}`}
            name="publicKeyId"
            defaultValue={row.public_key_id ?? ''}
            autoComplete="off"
            placeholder="Not a secret - displayed and editable"
          />
        </div>
      </div>

      {(row.provider === 'message_central' ||
        row.provider === 'whatsapp' ||
        row.provider === 'rcs') && (
        <>
          <label htmlFor={`sender-${row.provider}`}>Sender</label>
          <input
            id={`sender-${row.provider}`}
            name="senderId"
            defaultValue={row.sender_id ?? ''}
            autoComplete="off"
            placeholder={
              row.provider === 'message_central'
                ? 'Message Central owns the OTP sender and template - this is for other messages'
                : 'Sender / agent id'
            }
          />
        </>
      )}

      <div className="actions">
        <button disabled={saving}>
          {saving ? 'Saving…' : row.has_secret ? 'Rotate credential' : 'Save credential'}
        </button>
        {row.has_secret && (
          <span style={{ fontSize: 13, color: 'var(--ink-soft)' }}>
            Rotating writes a new secret and flips the reference. The previous one survives a short
            grace window so in-flight webhooks still verify.
          </span>
        )}
      </div>
    </form>
  );
}
