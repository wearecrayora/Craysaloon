'use client';

import { useActionState, useState } from 'react';
import { addLoginAction, setLoginActiveAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

export function AddLoginForm({ salonId }: { salonId: string }) {
  const [state, save, saving] = useActionState(addLoginAction, empty);
  return (
    <form action={save} className="card">
      <input type="hidden" name="salonId" value={salonId} />
      <h2 style={{ marginTop: 0 }}>Add a manager or stylist</h2>
      {state.error && <div className="error">{state.error}</div>}
      {state.ok && <div className="notice">{state.ok}</div>}
      <div className="row">
        <div>
          <label htmlFor="login-name">Name</label>
          <input id="login-name" name="name" placeholder="Priya Sharma" required />
        </div>
        <div>
          <label htmlFor="login-phone">Their own mobile number</label>
          <input id="login-phone" name="phone" placeholder="98123 45678" inputMode="tel" required />
        </div>
      </div>
      <label htmlFor="login-role">Role</label>
      <select id="login-role" name="role" defaultValue="staff">
        <option value="staff">Stylist - their day and their bookings</option>
        <option value="manager">Manager - runs the salon day to day</option>
      </select>
      <p className="hint">
        One number signs in to one salon. If this person already has a login at another salon,
        switch that one off first.
      </p>
      <div className="actions">
        <button disabled={saving}>{saving ? 'Adding…' : 'Add login'}</button>
      </div>
    </form>
  );
}

export function LoginRow({
  salonId,
  login,
}: {
  salonId: string;
  login: {
    id: string;
    role: string;
    roleLabel: string;
    name: string;
    phone_last4: string;
    active: boolean;
    signed_in: boolean;
  };
}) {
  const [state, save, saving] = useActionState(setLoginActiveAction, empty);
  const [open, setOpen] = useState(false);
  return (
    <tr>
      <td>
        <strong>{login.name}</strong>
      </td>
      <td>{login.roleLabel}</td>
      <td style={{ fontFamily: 'ui-monospace, monospace' }}>••••••{login.phone_last4}</td>
      <td>
        <span className={`pill ${login.active ? 'active' : 'suspended'}`}>
          {login.active ? (login.signed_in ? 'signed in before' : 'not signed in yet') : 'switched off'}
        </span>
        {state.error && <div className="error">{state.error}</div>}
        {state.ok && <div className="notice">{state.ok}</div>}
      </td>
      <td style={{ textAlign: 'right' }}>
        {login.role !== 'owner' &&
          (open ? (
            <form action={save} style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <input type="hidden" name="salonId" value={salonId} />
              <input type="hidden" name="userId" value={login.id} />
              <input type="hidden" name="active" value={String(!login.active)} />
              <input name="reason" placeholder="Why (audited)" required style={{ maxWidth: 200 }} />
              <button disabled={saving}>{login.active ? 'Switch off' : 'Switch on'}</button>
            </form>
          ) : (
            <button type="button" className="secondary" onClick={() => setOpen(true)}>
              {login.active ? 'Switch off…' : 'Switch on…'}
            </button>
          ))}
      </td>
    </tr>
  );
}
