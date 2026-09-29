'use client';

import { useActionState } from 'react';
import { accessSentAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

/** Produce the copy, send it, then say how - the customer reads that sentence. */
export function AccessForm({ requestId }: { requestId: string }) {
  const [state, save, saving] = useActionState(accessSentAction, empty);
  return (
    <form action={save} style={{ marginTop: 10 }}>
      <input type="hidden" name="requestId" value={requestId} />
      <p className="hint" style={{ margin: '0 0 8px' }}>
        <a href={`/data-rights/${requestId}/export`}>Download their data (JSON)</a>, send it to the
        customer - through the salon, which answers for it - then record how it reached them.
      </p>
      <label htmlFor={`sent-${requestId}`}>How it reached them</label>
      <input id={`sent-${requestId}`} name="howSent" placeholder="Emailed by the salon on 3 Jan" />
      {state.error && <div className="error">{state.error}</div>}
      {state.ok && <div className="notice">{state.ok}</div>}
      <div className="actions">
        <button className="secondary" disabled={saving}>
          {saving ? 'Saving…' : 'Mark as sent'}
        </button>
      </div>
    </form>
  );
}
