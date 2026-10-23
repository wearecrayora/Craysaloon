'use client';

import { useActionState } from 'react';
import { appVersionsAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

export function VersionsForm() {
  const [state, save, saving] = useActionState(appVersionsAction, empty);
  return (
    <form action={save} className="card">
      <h2 style={{ marginTop: 0 }}>App builds</h2>
      <label>
        Lowest build allowed to run (0 = any)
        <input name="minBuild" type="number" min={0} step={1} defaultValue={0} required />
      </label>
      <label>
        Newest build (suggest updating below this)
        <input name="latestBuild" type="number" min={0} step={1} defaultValue={0} required />
      </label>
      <label>
        Update link (https, optional)
        <input name="updateUrl" type="url" placeholder="https://play.google.com/store/apps/details?id=com.crayora.craysalon" />
      </label>
      <label>
        Reason (the audit entry)
        <input name="reason" placeholder="e.g. 1.0.3 fixes a booking crash" required />
      </label>
      <button type="submit" disabled={saving}>
        {saving ? 'Saving…' : 'Save for every salon'}
      </button>
      {state.error && <p className="error">{state.error}</p>}
      {state.ok && <p className="ok">{state.ok}</p>}
    </form>
  );
}
