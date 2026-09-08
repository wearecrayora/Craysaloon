'use client';

import { useActionState, useState } from 'react';
import Link from 'next/link';
import type { SalonRow as Row } from '@/server/admin-db';
import { activateAction, suspendAction, type ActionState } from './actions';

const empty: ActionState = {};

export function SalonRow({ salon, feeLabel }: { salon: Row; feeLabel: string }) {
  const [open, setOpen] = useState(false);
  const [activateState, activate, activating] = useActionState(activateAction, empty);
  const [suspendState, suspend, suspending] = useActionState(suspendAction, empty);

  const state = activateState.error ? activateState : suspendState;

  return (
    <>
      <tr>
        <td>
          <strong>{salon.display_name}</strong>
          <br />
          <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>{salon.legal_name}</span>
        </td>
        <td className="code">{salon.join_code}</td>
        <td>
          <span className={`pill ${salon.status}`}>{salon.status}</span>
        </td>
        <td>
          {feeLabel}
          <br />
          <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>{salon.setup_fee_status}</span>
        </td>
        <td>
          {salon.integrations_ok}/{salon.integrations_total} tested
        </td>
        <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
          <Link href={`/salon/${salon.id}/branding`} style={{ fontSize: 13, marginRight: 10 }}>
            Branding
          </Link>
          <Link href={`/salon/${salon.id}/credentials`} style={{ fontSize: 13, marginRight: 10 }}>
            Credentials
          </Link>
          <button type="button" className="secondary" onClick={() => setOpen((v) => !v)}>
            {open ? 'Close' : 'Manage'}
          </button>
        </td>
      </tr>

      {open && (
        <tr>
          <td colSpan={6} style={{ background: 'var(--bg-soft)' }}>
            {state.error && <div className="error">{state.error}</div>}
            {(activateState.ok || suspendState.ok) && (
              <div className="notice">{activateState.ok ?? suspendState.ok}</div>
            )}

            {salon.status === 'setup' ? (
              <form action={activate}>
                <input type="hidden" name="salonId" value={salon.id} />
                <p className="hint" style={{ margin: '4px 0 8px' }}>
                  Activation is a deliberate act. Nothing else can do it — no payment, no timer.
                  {salon.setup_fee_status !== 'paid' && (
                    <>
                      {' '}
                      <strong>The setup fee is not recorded as paid.</strong> That is a warning,
                      not a block — you may have a reason, and it will be captured below.
                    </>
                  )}
                </p>
                <label htmlFor={`r-${salon.id}`}>Reason (optional, recorded in the audit log)</label>
                <input id={`r-${salon.id}`} name="reason" placeholder="Fee received in cash, receipt #1042" />
                <div className="actions">
                  <button disabled={activating}>
                    {activating ? 'Activating…' : 'Activate this salon'}
                  </button>
                </div>
              </form>
            ) : (
              <form action={suspend}>
                <input type="hidden" name="salonId" value={salon.id} />
                <label htmlFor={`s-${salon.id}`}>Move to</label>
                <select id={`s-${salon.id}`} name="status" defaultValue="grace">
                  <option value="grace">Grace — read-only, salon can still be seen</option>
                  <option value="suspended">Suspended — the salon stops operating</option>
                </select>
                <label htmlFor={`sr-${salon.id}`}>Reason (required)</label>
                <input id={`sr-${salon.id}`} name="reason" placeholder="Non-payment, 30 days overdue" />
                <div className="actions">
                  <button className="secondary" disabled={suspending}>
                    {suspending ? 'Applying…' : 'Change status'}
                  </button>
                </div>
              </form>
            )}
          </td>
        </tr>
      )}
    </>
  );
}
