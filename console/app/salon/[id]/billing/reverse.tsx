'use client';

import { useActionState, useState } from 'react';
import { reversePaymentAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

/**
 * Reverse one payment recorded by mistake (0112). A new row, never an edit:
 * the original stays on the record, and the reversal says why.
 */
export function ReversePayment({ salonId, paymentId }: { salonId: string; paymentId: number }) {
  const [open, setOpen] = useState(false);
  const [state, save, saving] = useActionState(reversePaymentAction, empty);

  if (state.ok) return <span className="pill">{state.ok}</span>;
  if (!open) {
    return (
      <button type="button" className="secondary" onClick={() => setOpen(true)}>
        Reverse
      </button>
    );
  }
  return (
    <form action={save} style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
      <input type="hidden" name="salonId" value={salonId} />
      <input type="hidden" name="paymentId" value={paymentId} />
      <label htmlFor={`rev-${paymentId}`} className="sr-only">Why</label>
      <input id={`rev-${paymentId}`} name="reason" placeholder="Why (audited)" required style={{ maxWidth: 220 }} />
      <button type="submit" disabled={saving}>{saving ? 'Reversing…' : 'Reverse payment'}</button>
      <button type="button" className="secondary" onClick={() => setOpen(false)}>Cancel</button>
      {state.error && <div className="error">{state.error}</div>}
    </form>
  );
}
