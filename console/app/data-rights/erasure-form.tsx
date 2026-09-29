'use client';

import { useActionState } from 'react';
import { carryOutErasureAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

/**
 * Carrying out an erasure (DPDP s.12(3)).
 *
 * The consequence is stated BEFORE the button, not discovered after: erasure is
 * anonymisation. The person goes; the money stays - the salon's books are
 * required by law, and deleting them is not ours to do (RULES 11.8).
 */
export function ErasureForm({ requestId }: { requestId: string }) {
  const [state, erase, erasing] = useActionState(carryOutErasureAction, empty);

  if (state.ok) {
    return <div className="ok">{state.ok}</div>;
  }

  return (
    <form action={erase} style={{ marginTop: 12 }}>
      <input type="hidden" name="requestId" value={requestId} />
      <div className="notice" style={{ marginTop: 0 }}>
        <strong>This cannot be undone.</strong> Their name, number and birthday are removed and
        their login is cut. Every payment and wallet record stays, pointing at someone nobody can
        name. The salted fingerprint of their number stays too - it is what keeps one number to one
        salon after they are gone.
      </div>
      <label htmlFor={`reason-${requestId}`}>Why, for the audit log</label>
      <input
        id={`reason-${requestId}`}
        name="reason"
        placeholder="e.g. Salon did not answer within 30 days; customer confirmed by phone"
        required
      />
      {state.error && <div className="error">{state.error}</div>}
      <div className="actions">
        <button className="danger" disabled={erasing}>
          {erasing ? 'Erasing…' : 'Carry out erasure'}
        </button>
      </div>
    </form>
  );
}
