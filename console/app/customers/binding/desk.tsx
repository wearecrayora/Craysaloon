'use client';

import { useActionState, useEffect, useState } from 'react';
import {
  lookupBindingAction,
  transferAction,
  unbindAction,
  type BindingState,
} from '@/app/actions';

const empty: BindingState = {};

/** Paise -> ₹1,20,500 or ₹550.50. Tabular, Indian grouping, never animated. */
function inr(paise: number): string {
  const whole = Math.trunc(paise / 100);
  const rest = paise % 100;
  return (
    '₹' +
    whole.toLocaleString('en-IN') +
    (rest ? '.' + String(rest).padStart(2, '0') : '')
  );
}

/** The screen never repeats the whole number back. */
function masked(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  return '••••••' + digits.slice(-4);
}

const money = { fontVariantNumeric: 'tabular-nums' } as const;

export function BindingDesk({
  destinations,
}: {
  destinations: { id: string; display_name: string; join_code: string }[];
}) {
  const [found, lookup, looking] = useActionState(lookupBindingAction, empty);
  const [unbound, unbind, unbinding] = useActionState(unbindAction, empty);
  const [moved, transfer, transferring] = useActionState(transferAction, empty);

  // A completed action retires the lookup it acted on: the figures shown are
  // no longer true, and must not be acted on twice. A new lookup clears it.
  const [done, setDone] = useState<string | null>(null);
  useEffect(() => setDone(null), [found]);
  useEffect(() => {
    if (unbound.ok) setDone(unbound.ok);
  }, [unbound]);
  useEffect(() => {
    if (moved.ok) setDone(moved.ok);
  }, [moved]);

  const r = done ? undefined : found.result;
  const number = found.phone ?? '';

  return (
    <>
      <form action={lookup} className="card">
        <h2>1 · Look the number up</h2>
        <p className="hint" style={{ marginTop: 0 }}>
          One complete number, from the customer on the phone. This is not a search: there is no
          partial match and no list, and every lookup - found or not - is recorded against your
          name with the reason you give.
        </p>
        <div className="row">
          <div>
            <label htmlFor="lk-phone">Customer’s mobile number</label>
            <input
              id="lk-phone"
              name="phone"
              inputMode="numeric"
              autoComplete="off"
              placeholder="10 digits"
              required
            />
          </div>
          <div>
            <label htmlFor="lk-reason">Why you are looking it up</label>
            <input
              id="lk-reason"
              name="reason"
              autoComplete="off"
              placeholder="e.g. Customer called: scanned the wrong salon’s QR"
              required
            />
          </div>
        </div>
        {found.error && <div className="error">{found.error}</div>}
        <div className="actions">
          <button disabled={looking}>{looking ? 'Looking up…' : 'Look up'}</button>
        </div>
      </form>

      {done && <div className="notice">{done}</div>}

      {r && !r.bound && (
        <div className="card">
          <h2>{masked(number)} is not bound to any salon</h2>
          <p className="hint" style={{ margin: 0 }}>
            Nothing to change. The customer can join a salon themselves by scanning its QR or
            entering its code, and verifying their number.
          </p>
        </div>
      )}

      {r && r.bound && (
        <>
          <div className="card">
            <h2>
              {masked(number)} belongs to {r.salon_name}{' '}
              <span style={{ fontFamily: 'ui-monospace, monospace', fontWeight: 400 }}>
                {r.join_code}
              </span>
            </h2>
            <table>
              <tbody>
                <tr>
                  <th>Since</th>
                  <td>
                    {new Date(r.bound_at).toLocaleDateString('en-IN', {
                      day: 'numeric', month: 'short', year: 'numeric',
                    })}
                  </td>
                </tr>
                <tr>
                  <th>Wallet balance</th>
                  <td style={money}>
                    <strong>{inr(r.balance_paise)}</strong>
                    {r.balance_paise > 0 && (
                      <span className="hint">
                        {' '}
                        - paid {inr(r.paid_paise)}, bonus {inr(r.bonus_paise)}
                      </span>
                    )}
                  </td>
                </tr>
                <tr>
                  <th>History here</th>
                  <td style={money}>
                    {r.wallet_transactions} wallet entries · {r.bookings} bookings · {r.visits} visits
                  </td>
                </tr>
                <tr>
                  <th>Salon</th>
                  <td>{r.salon_status}</td>
                </tr>
              </tbody>
            </table>
          </div>

          {r.can_unbind ? (
            <form action={unbind} className="card">
              <h2>2 · Unbind</h2>
              <p className="hint" style={{ marginTop: 0 }}>
                For a customer who scanned the wrong salon’s QR. They have no wallet entries,
                bookings or visits at {r.salon_name}, so nothing is lost. They are signed out
                everywhere and can then join the right salon by entering its code.
              </p>
              <input type="hidden" name="phone" value={number} />
              <label htmlFor="ub-reason">Reason - this is the audit entry</label>
              <textarea
                id="ub-reason"
                name="reason"
                rows={2}
                required
                minLength={10}
                placeholder="e.g. Scanned Salon A’s QR at the mall; meant to join Salon B"
              />
              {unbound.error && <div className="error">{unbound.error}</div>}
              <div className="actions">
                <button disabled={unbinding}>{unbinding ? 'Unbinding…' : 'Unbind this number'}</button>
              </div>
            </form>
          ) : (
            <div className="notice">
              <strong>Unbind is not available.</strong> This customer has history at{' '}
              {r.salon_name}, which unbinding would orphan. If they want to leave, transfer them
              below.
            </div>
          )}

          <form action={transfer} className="card">
            <h2>{r.can_unbind ? '3' : '2'} · Transfer to another salon</h2>
            <p className="hint" style={{ marginTop: 0 }}>
              Before you do this, tell the customer - in these words or your own - that{' '}
              <strong style={money}>{inr(r.balance_paise)}</strong> stays with {r.salon_name}.
              It was paid into that salon’s own account; Crayora never held it and cannot move or
              refund it. Their visits, loyalty and packages stay there too. At the new salon they
              start from zero.
            </p>
            <input type="hidden" name="phone" value={number} />

            <label htmlFor="tr-to">Moving to</label>
            <select id="tr-to" name="toSalonId" required defaultValue="">
              <option value="" disabled>
                Choose a salon
              </option>
              {destinations
                .filter((d) => d.id !== r.salon_id)
                .map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.display_name} · {d.join_code}
                  </option>
                ))}
            </select>

            <div className="row">
              <div>
                <label htmlFor="tr-balance">Balance you told the customer (₹)</label>
                <input
                  id="tr-balance"
                  name="acknowledged"
                  inputMode="decimal"
                  autoComplete="off"
                  placeholder="Type the figure you said out loud"
                  required
                  style={money}
                />
              </div>
              <div>
                <label htmlFor="tr-reason">Reason - this is the audit entry</label>
                <input
                  id="tr-reason"
                  name="reason"
                  autoComplete="off"
                  required
                  minLength={10}
                  placeholder="e.g. Moved to Pune; asked to join Salon B"
                />
              </div>
            </div>

            <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontWeight: 400 }}>
              <input type="checkbox" name="told" style={{ width: 'auto', marginTop: 4 }} />
              <span>
                I have told the customer that their balance stays with {r.salon_name} and cannot be
                moved or refunded, and they still want to transfer.
              </span>
            </label>

            <p className="hint">
              The figure you type must match what they hold right now. If a top-up lands between
              the lookup and this transfer, it will be refused: look the number up again and tell
              them the new amount.
            </p>

            {moved.error && <div className="error">{moved.error}</div>}
            <div className="actions">
              <button disabled={transferring || destinations.length === 0}>
                {transferring ? 'Transferring…' : 'Transfer this customer'}
              </button>
              {destinations.length === 0 && (
                <span className="hint" style={{ margin: 0 }}>
                  No other salon can take a new customer today.
                </span>
              )}
            </div>
          </form>
        </>
      )}
    </>
  );
}
