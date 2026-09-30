'use client';

import { useActionState } from 'react';
import { salonGstAction, type ActionState } from '@/app/actions';
import { GST_RATES_BP } from '@/lib/gst';

const empty: ActionState = {};

/**
 * GST registration, per salon. A GSTIN and a rate, both or neither: with both,
 * every paid visit gets a TAX INVOICE with GST carved out of the price; with
 * neither, a BILL OF SUPPLY. Top-ups always get a receipt, never an invoice
 * (RULES 11.12). The rate is never defaulted - it is the CA's answer (0094).
 */
export function GstForm({
  salonId,
  gstNumber,
  rateBp,
}: {
  salonId: string;
  gstNumber: string | null;
  rateBp: number | null;
}) {
  const [state, save, saving] = useActionState(salonGstAction, empty);
  const registered = gstNumber != null && rateBp != null;

  return (
    <>
      <h2>GST</h2>
      <p className="hint">
        {registered
          ? `Registered: ${gstNumber}, at ${rateBp! / 100}%. Paid visits get tax invoices; prices are treated as GST-inclusive.`
          : gstNumber
            ? `A GSTIN is on file (${gstNumber}) but no rate - paid visits get bills of supply until a rate is set.`
            : 'Not registered: paid visits get bills of supply, with no GST.'}{' '}
        Confirm the rate with a CA before setting it - salon services are not all taxed alike.
      </p>
      <form action={save} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        {state.error && <div className="error">{state.error}</div>}
        {state.ok && <div className="notice">{state.ok}</div>}
        <div className="row">
          <div>
            <label htmlFor="gstNumber">GSTIN</label>
            <input
              id="gstNumber"
              name="gstNumber"
              defaultValue={gstNumber ?? ''}
              placeholder="29ABCDE1234F1Z5 - blank to unregister"
              spellCheck={false}
              style={{ fontFamily: 'ui-monospace, monospace', textTransform: 'uppercase' }}
            />
          </div>
          <div>
            <label htmlFor="rate">Rate</label>
            <select id="rate" name="rate" defaultValue={rateBp ?? ''}>
              <option value="">Not charging GST</option>
              {GST_RATES_BP.map((r) => (
                <option key={r} value={r}>
                  {r / 100}%
                </option>
              ))}
            </select>
          </div>
        </div>
        <label htmlFor="gst-reason">Reason (audited)</label>
        <input id="gst-reason" name="reason" placeholder="e.g. CA confirmed 5% without ITC" required />
        <div className="actions">
          <button disabled={saving}>{saving ? 'Saving…' : 'Save GST'}</button>
        </div>
      </form>
    </>
  );
}
