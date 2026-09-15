'use client';

import { useActionState } from 'react';
import { generateQrPackAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

export function QrPackForm({ salonId, regenerate }: { salonId: string; regenerate: boolean }) {
  const [state, generate, pending] = useActionState(generateQrPackAction, empty);

  return (
    <form action={generate} className="card">
      <input type="hidden" name="salonId" value={salonId} />
      {state.error && <div className="error">{state.error}</div>}
      {state.ok && (
        <div className="notice">
          {state.ok}{' '}
          {state.url && (
            <a href={state.url}>
              <strong>Download the PDF</strong>
            </a>
          )}
        </div>
      )}
      <p className="hint" style={{ marginTop: 0 }}>
        {regenerate
          ? 'Regenerating keeps the previous pack; nothing is overwritten. The join code does not change, so packs already printed keep working.'
          : 'The pack is stored privately and handed out through a short-lived link, never a permanent one.'}
      </p>
      <div className="actions">
        <button disabled={pending}>
          {pending ? 'Rendering…' : regenerate ? 'Generate a fresh pack' : 'Generate QR pack'}
        </button>
      </div>
    </form>
  );
}
