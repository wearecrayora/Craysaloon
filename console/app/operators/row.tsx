'use client';

import { useActionState, useState } from 'react';
import { operatorActiveAction, type ActionState } from '@/app/actions';
import type { Operator } from '@/server/admin-db';

const empty: ActionState = {};

/** Switch one operator off or on, with a reason (0115). */
export function OperatorRow({ operator }: { operator: Operator }) {
  const [open, setOpen] = useState(false);
  const [state, save, saving] = useActionState(operatorActiveAction, empty);

  if (state.ok) return <span className="pill">{state.ok}</span>;
  if (!open) {
    return (
      <button type="button" className="secondary" onClick={() => setOpen(true)}>
        {operator.active ? 'Switch off' : 'Switch on'}
      </button>
    );
  }
  return (
    <form action={save} style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
      <input type="hidden" name="adminId" value={operator.id} />
      <input type="hidden" name="active" value={operator.active ? 'false' : 'true'} />
      <label htmlFor={`op-${operator.id}`} className="sr-only">Why</label>
      <input id={`op-${operator.id}`} name="reason" placeholder="Why (audited)" required style={{ maxWidth: 220 }} />
      <button type="submit" disabled={saving}>
        {saving ? 'Saving…' : operator.active ? 'Switch off now' : 'Switch on'}
      </button>
      <button type="button" className="secondary" onClick={() => setOpen(false)}>Cancel</button>
      {state.error && <div className="error">{state.error}</div>}
    </form>
  );
}
