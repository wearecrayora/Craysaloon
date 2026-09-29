'use client';

import { useActionState, useState } from 'react';
import { endSupportAction, startSupportAction, unmaskAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

export function StartSession({ salonId }: { salonId: string }) {
  const [state, start, starting] = useActionState(startSupportAction, empty);
  return (
    <form action={start} className="card">
      <input type="hidden" name="salonId" value={salonId} />
      <div className="row">
        <div>
          <label htmlFor="reason">Reason (required, audited)</label>
          <input id="reason" name="reason" placeholder="Ticket 41: customer cannot see their wallet" />
        </div>
        <div>
          <label htmlFor="minutes">Minutes</label>
          <input id="minutes" name="minutes" type="number" min={5} max={120} defaultValue={60} />
        </div>
      </div>
      {state.error && <div className="error">{state.error}</div>}
      <div className="actions">
        <button disabled={starting}>{starting ? 'Starting…' : 'Start support session'}</button>
      </div>
    </form>
  );
}

export function EndSession({ salonId, sessionId }: { salonId: string; sessionId: string }) {
  const [state, end, ending] = useActionState(endSupportAction, empty);
  return (
    <form action={end} style={{ marginBottom: 12 }}>
      <input type="hidden" name="salonId" value={salonId} />
      <input type="hidden" name="sessionId" value={sessionId} />
      {state.error && <div className="error">{state.error}</div>}
      <button className="secondary" disabled={ending}>
        {ending ? 'Ending…' : 'End session now'}
      </button>
    </form>
  );
}

/** Un-masking one number: its own reason, its own audit entry. */
export function Unmask({ customerId }: { customerId: string }) {
  const [open, setOpen] = useState(false);
  const [state, unmask, unmasking] = useActionState(unmaskAction, empty);

  if (state.ok) return <span className="code">{state.ok}</span>;
  if (!open) {
    return (
      <button type="button" className="secondary" onClick={() => setOpen(true)}>
        Show number
      </button>
    );
  }
  return (
    <form action={unmask} style={{ display: 'flex', gap: 6 }}>
      <input type="hidden" name="customerId" value={customerId} />
      <input name="reason" placeholder="Why do you need it?" required />
      <button className="secondary" disabled={unmasking}>
        Show
      </button>
      {state.error && <span className="error">{state.error}</span>}
    </form>
  );
}
