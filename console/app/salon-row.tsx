'use client';

import { useActionState, useState } from 'react';
import Link from 'next/link';
import type { SalonRow as Row } from '@/server/admin-db';
import {
  activateAction,
  setGraceAction,
  setTrialAction,
  suspendAction,
  type ActionState,
} from './actions';

const empty: ActionState = {};

export function SalonRow({ salon, feeLabel }: { salon: Row; feeLabel: string }) {
  const [open, setOpen] = useState(false);
  const [activateState, activate, activating] = useActionState(activateAction, empty);
  const [suspendState, suspend, suspending] = useActionState(suspendAction, empty);
  const [trialState, setTrial, settingTrial] = useActionState(setTrialAction, empty);

  // Days left in the messaging trial, rounded UP: a trial ending this evening
  // still has "1 day" on it, not 0.
  const trialEnds = salon.messaging_trial_ends_at ? new Date(salon.messaging_trial_ends_at) : null;
  const trialDaysLeft =
    trialEnds && trialEnds.getTime() > Date.now()
      ? Math.ceil((trialEnds.getTime() - Date.now()) / 86_400_000)
      : 0;

  const [graceState, setGrace, settingGrace] = useActionState(setGraceAction, empty);
  const graceEnds = salon.messaging_grace_ends_at ? new Date(salon.messaging_grace_ends_at) : null;
  const graceDaysLeft =
    graceEnds && graceEnds.getTime() > Date.now()
      ? Math.ceil((graceEnds.getTime() - Date.now()) / 86_400_000)
      : 0;
  const fmt = (d: Date) =>
    d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });

  // The DATABASE decides the state (app.salon_messaging_state). The console
  // only displays it, so what the operator sees can never disagree with what
  // RLS and the OTP functions actually enforce.
  const ms = salon.messaging_state;

  const state = activateState.error
    ? activateState
    : trialState.error
      ? trialState
      : graceState.error
        ? graceState
        : suspendState;

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
          {ms === 'own' ? (
            <span style={{ color: 'var(--ok)', fontWeight: 600 }}>OTP: own account</span>
          ) : ms === 'trial' ? (
            <span style={{ color: 'var(--warn)', fontWeight: 600 }}>
              OTP: trial, {trialDaysLeft} day{trialDaysLeft === 1 ? '' : 's'} left
            </span>
          ) : ms === 'grace' ? (
            <span style={{ color: 'var(--danger)', fontWeight: 600 }}>
              GRACE: {graceDaysLeft} day{graceDaysLeft === 1 ? '' : 's'}, then blocked
            </span>
          ) : ms === 'blocked' ? (
            <span className="pill suspended">BLOCKED</span>
          ) : (
            // Never sponsored and no own account: every OTP is a fault fallback.
            <span style={{ color: 'var(--danger)', fontWeight: 600 }}>OTP: Crayora pays</span>
          )}
          {salon.otp_trial_sends_7d > 0 && (
            <>
              <br />
              <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                {salon.otp_trial_sends_7d} trial OTP{salon.otp_trial_sends_7d === 1 ? '' : 's'} this week
              </span>
            </>
          )}
          {salon.otp_fallbacks_7d > 0 && (
            <>
              <br />
              <span style={{ color: 'var(--danger)', fontSize: 12 }}>
                {salon.otp_fallbacks_7d} fallback{salon.otp_fallbacks_7d === 1 ? '' : 's'} this week
              </span>
            </>
          )}
          <br />
          <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            {salon.integrations_ok}/{salon.integrations_total} tested
          </span>
        </td>
        <td style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
          <Link href={`/salon/${salon.id}/branding`} style={{ fontSize: 13, marginRight: 10 }}>
            Branding
          </Link>
          <Link href={`/salon/${salon.id}/catalogue`} style={{ fontSize: 13, marginRight: 10 }}>
            Catalogue
          </Link>
          <Link href={`/salon/${salon.id}/credentials`} style={{ fontSize: 13, marginRight: 10 }}>
            Credentials
          </Link>
          <Link href={`/salon/${salon.id}/qr`} style={{ fontSize: 13, marginRight: 10 }}>
            QR pack
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

            <form action={setTrial} style={{ marginBottom: 18 }}>
              <input type="hidden" name="salonId" value={salon.id} />
              <strong style={{ fontSize: 14 }}>Messaging trial</strong>
              <p className="hint" style={{ margin: '4px 0 8px' }}>
                {salon.otp_own_account
                  ? 'This salon has its own Message Central account, so its OTPs already use it - a trial would change nothing.'
                  : trialDaysLeft > 0
                    ? `Running until ${trialEnds!.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}. Crayora pays for this salon’s OTPs until then. Enter a new length to extend it, or 0 to end it now.`
                    : 'Until the trial ends, this salon’s customer OTPs are sent from Crayora’s Message Central account, so it can go live before setting up its own. Counted from today. The setup fee and subscription are not affected.'}
              </p>
              {trialState.ok && <div className="notice">{trialState.ok}</div>}
              <div className="row">
                <div>
                  <label htmlFor={`td-${salon.id}`}>Trial length (days from today)</label>
                  <input
                    id={`td-${salon.id}`}
                    name="days"
                    type="number"
                    min={0}
                    max={365}
                    defaultValue={trialDaysLeft > 0 ? trialDaysLeft : 14}
                  />
                </div>
                <div>
                  <label htmlFor={`tr-${salon.id}`}>Reason (required, audited)</label>
                  <input id={`tr-${salon.id}`} name="reason" placeholder="Pilot salon - launch month" />
                </div>
              </div>
              <div className="actions">
                <button className="secondary" disabled={settingTrial}>
                  {settingTrial ? 'Saving…' : trialDaysLeft > 0 ? 'Update trial' : 'Grant trial'}
                </button>
              </div>
            </form>

            {ms === 'blocked' && (
              <div className="error" style={{ marginTop: 0 }}>
                <strong>This salon is blocked.</strong> Its trial and grace period have ended and it
                still has no Message Central account of its own. New customers cannot join, no OTP
                is sent - so nobody new can log in - and the owner and staff cannot change
                anything. People already logged in can still <em>see</em> their data, including
                wallet balances the salon owes them, and can still withdraw consent.
                <br />
                <strong>To unblock:</strong> enter the salon’s own Message Central account under
                Credentials - it lifts immediately - or grant more grace below.
              </div>
            )}

            {ms !== 'own' && (
              <form action={setGrace} style={{ marginBottom: 18 }}>
                <input type="hidden" name="salonId" value={salon.id} />
                <strong style={{ fontSize: 14 }}>Grace period</strong>
                <p className="hint" style={{ margin: '4px 0 8px' }}>
                  {ms === 'grace' && graceEnds
                    ? `Running until ${fmt(graceEnds)}. Crayora still sends this salon’s OTPs until then; after that it is blocked unless you have entered its own Message Central account under Credentials. Enter a new length to change it, or 0 to end it now.`
                    : ms === 'trial'
                      ? 'Extra days after the trial ends - granted now, it starts when the trial finishes. When grace ends, the salon is blocked unless you have entered its own Message Central account under Credentials.'
                      : 'Extra days, from today, during which Crayora still sends this salon’s OTPs. When they end, the salon is blocked unless you have entered its own Message Central account under Credentials.'}
                </p>
                {graceState.ok && <div className="notice">{graceState.ok}</div>}
                <div className="row">
                  <div>
                    <label htmlFor={`gd-${salon.id}`}>Grace length (days)</label>
                    <input
                      id={`gd-${salon.id}`}
                      name="days"
                      type="number"
                      min={0}
                      max={365}
                      defaultValue={graceDaysLeft > 0 ? graceDaysLeft : 7}
                    />
                  </div>
                  <div>
                    <label htmlFor={`gr-${salon.id}`}>Reason (required, audited)</label>
                    <input
                      id={`gr-${salon.id}`}
                      name="reason"
                      placeholder="Salon is setting up Message Central"
                    />
                  </div>
                </div>
                <div className="actions">
                  <button className="secondary" disabled={settingGrace}>
                    {settingGrace ? 'Saving…' : ms === 'grace' ? 'Update grace' : 'Grant grace'}
                  </button>
                </div>
              </form>
            )}

            {salon.status === 'setup' ? (
              <form action={activate}>
                <input type="hidden" name="salonId" value={salon.id} />
                <p className="hint" style={{ margin: '4px 0 8px' }}>
                  Activation is a deliberate act. Nothing else can do it — no payment, no timer.
                  {ms === 'fallback' && (
                    <>
                      {' '}
                      <strong>
                        No Message Central account yet: every customer OTP will be sent and paid
                        for by Crayora, and each one raises an alert.
                      </strong>{' '}
                      Customers can still log in - that is what the fallback is for. Either add
                      the salon’s own account under Credentials, or grant a messaging trial above
                      so the OTPs are covered on purpose rather than as a fault.
                    </>
                  )}
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
