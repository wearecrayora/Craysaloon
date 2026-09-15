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

      {row.provider === 'message_central' && (
        <div className="notice" style={{ marginTop: 0 }}>
          <strong>This is the account the salon’s customers get their OTP from, and it pays
          for every one.</strong> Both values are in the salon’s own Message Central dashboard.
          They are checked with Message Central before saving - no SMS is sent - and a pair that
          does not belong together is refused.
          {!row.has_secret && (
            <>
              {' '}
              <strong>Until this is filled in, this salon’s customers get their OTP from
              Crayora’s account, at Crayora’s cost</strong>, and every one raises an alert.
            </>
          )}
          <br />
          The customer sees no difference either way: the text arrives under Message
          Central’s registered sender with Message Central’s wording, which cannot be
          changed.
        </div>
      )}

      {state.error && <div className="error">{state.error}</div>}
      {state.ok && <div className="notice">{state.ok}</div>}

      <div className="row">
        <div>
          <label htmlFor={`secret-${row.provider}`}>
            {row.provider === 'message_central'
              ? row.has_secret
                ? 'Replace the auth token'
                : 'Auth token'
              : row.provider === 'razorpay'
                ? row.has_secret
                  ? 'Replace the key secret'
                  : 'Key secret'
                : row.has_secret
                  ? 'Replace the secret'
                  : 'Secret'}
          </label>
          <input
            id={`secret-${row.provider}`}
            name="secret"
            ref={secretRef}
            type="password"
            autoComplete="off"
            spellCheck={false}
            placeholder={
              row.provider === 'message_central'
                ? 'The long value starting eyJ…'
                : row.has_secret
                  ? 'Paste a new value to rotate'
                  : 'Paste the credential'
            }
          />
        </div>
        <div>
          <label htmlFor={`pk-${row.provider}`}>
            {row.provider === 'razorpay'
              ? 'Key id'
              : row.provider === 'message_central'
                ? 'Customer ID'
                : 'Public identifier'}
          </label>
          <input
            id={`pk-${row.provider}`}
            name="publicKeyId"
            defaultValue={row.public_key_id ?? ''}
            autoComplete="off"
            placeholder={
              row.provider === 'message_central'
                ? 'C-…  (not secret)'
                : 'Not a secret - displayed and editable'
            }
            required={row.provider === 'message_central'}
          />
        </div>
      </div>

      {(row.provider === 'whatsapp' || row.provider === 'rcs') && (
        <>
          <label htmlFor={`sender-${row.provider}`}>Sender</label>
          <input
            id={`sender-${row.provider}`}
            name="senderId"
            defaultValue={row.sender_id ?? ''}
            autoComplete="off"
            placeholder="Sender / agent id"
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
