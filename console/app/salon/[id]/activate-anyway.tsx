'use client';

import { useActionState } from 'react';
import { activateAnywayAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

/**
 * Switch the salon on before its setup is complete - super-admins only, with a
 * reason, and everything still missing listed first (0116).
 */
export function ActivateAnyway({ salonId, missing }: { salonId: string; missing: string[] }) {
  const [state, save, saving] = useActionState(activateAnywayAction, empty);

  if (state.ok) return <div className="notice">{state.ok}</div>;
  return (
    <form action={save} className="card">
      <h2 style={{ marginTop: 0 }}>Activate anyway</h2>
      <p className="hint" style={{ marginTop: 0 }}>
        Switches the salon on now, before its setup is complete. Customers can join from today.
        {missing.length > 0 && <> Still missing, and recorded as skipped in the audit log:</>}
      </p>
      {missing.length > 0 && (
        <ul style={{ margin: '0 0 12px', paddingLeft: 18 }}>
          {missing.map((m) => (
            <li key={m}>{m}</li>
          ))}
        </ul>
      )}
      <input type="hidden" name="salonId" value={salonId} />
      <label htmlFor="anyway-reason">Reason (required, audited)</label>
      <input id="anyway-reason" name="reason" required placeholder="Pilot salon - fee and contact this week" />
      {state.error && <div className="error">{state.error}</div>}
      <div className="actions">
        <button disabled={saving}>{saving ? 'Activating…' : 'Activate anyway'}</button>
      </div>
    </form>
  );
}
