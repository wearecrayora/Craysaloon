'use client';

import { useActionState } from 'react';
import {
  extendAction,
  featureFlagAction,
  setBillingAction,
  setupFeeAction,
  subscriptionPaymentAction,
  type ActionState,
} from '@/app/actions';
import type { BillingOverview, Feature } from '@/server/admin-db';

const empty: ActionState = {};

const FEATURE_WORDS: Record<Feature, string> = {
  dashboard: "Owner's dashboard",
  referrals: 'Refer & Earn',
};

function Result({ state }: { state: ActionState }) {
  if (state.error) return <div className="error">{state.error}</div>;
  if (state.ok) return <div className="notice">{state.ok}</div>;
  return null;
}

export function BillingForms({
  salonId,
  billing,
  salonStatus,
}: {
  salonId: string;
  billing: BillingOverview;
  salonStatus: string;
}) {
  const [feeState, saveFee, savingFee] = useActionState(setupFeeAction, empty);
  const [planState, savePlan, savingPlan] = useActionState(setBillingAction, empty);
  const [payState, savePay, savingPay] = useActionState(subscriptionPaymentAction, empty);
  const [extState, saveExt, savingExt] = useActionState(extendAction, empty);
  const [flagState, saveFlag, savingFlag] = useActionState(featureFlagAction, empty);

  const s = billing.subscription;
  const billed = billing.dates?.renews_at != null;

  return (
    <>
      <h2>Setup fee</h2>
      <form action={saveFee} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        <p className="hint" style={{ marginTop: 0 }}>
          {salonStatus === 'setup'
            ? 'The salon cannot be activated until this is paid, or waived with a reason. There is no free trial.'
            : 'Recorded for the books. Changing it does not change the salon’s status.'}
        </p>
        <div className="row">
          <div>
            <label htmlFor="fee-status">Status</label>
            <select id="fee-status" name="status" defaultValue={s.setup_fee_status}>
              <option value="unpaid">Unpaid</option>
              <option value="paid">Paid</option>
              <option value="waived">Waived</option>
            </select>
          </div>
          <div>
            <label htmlFor="fee-amount">Amount (₹)</label>
            <input
              id="fee-amount"
              name="amount"
              inputMode="decimal"
              defaultValue={s.setup_fee_paise ? String(s.setup_fee_paise / 100) : ''}
              placeholder="15000"
            />
          </div>
          <div>
            <label htmlFor="fee-ref">Reference, or the reason for a waiver</label>
            <input
              id="fee-ref"
              name="reference"
              defaultValue={s.setup_fee_reference ?? ''}
              placeholder="NEFT UTR / receipt no."
            />
          </div>
          <div>
            <label htmlFor="fee-date">Paid on</label>
            <input id="fee-date" name="paidOn" type="date" defaultValue={s.setup_fee_paid_on ?? ''} />
          </div>
        </div>
        <Result state={feeState} />
        <div className="actions">
          <button disabled={savingFee}>{savingFee ? 'Saving…' : 'Save setup fee'}</button>
        </div>
      </form>

      <h2>Plan and price</h2>
      <form action={savePlan} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        <p className="hint" style={{ marginTop: 0 }}>
          {billed
            ? 'Changing the plan or price does not move the paid-until date - it never forgives a debt. Only a payment or an extension does.'
            : 'The first month is due on the billing start date. Record the payment when it arrives; if it does not, the salon goes read-only that day.'}
        </p>
        <div className="row">
          <div>
            <label htmlFor="plan">Plan</label>
            <select id="plan" name="plan" defaultValue={s.plan}>
              <option value="starter">Starter</option>
              <option value="growth">Growth</option>
              <option value="pro">Pro</option>
            </select>
          </div>
          <div>
            <label htmlFor="price">Agreed price per month (₹)</label>
            <input
              id="price"
              name="price"
              inputMode="decimal"
              defaultValue={s.monthly_price_paise ? String(s.monthly_price_paise / 100) : ''}
              placeholder="799"
              required
            />
          </div>
          <div>
            <label htmlFor="starts">Billing starts on</label>
            <input
              id="starts"
              name="startsOn"
              type="date"
              defaultValue={s.billing_starts_on ?? ''}
              disabled={billed}
            />
          </div>
          <div>
            <label htmlFor="plan-reason">Reason (audited)</label>
            <input id="plan-reason" name="reason" placeholder="Signed on the Growth plan" />
          </div>
        </div>
        <Result state={planState} />
        <div className="actions">
          <button disabled={savingPlan}>{savingPlan ? 'Saving…' : 'Save plan'}</button>
        </div>
      </form>

      {billed && (
        <>
          <h2>Record a payment</h2>
          <form action={savePay} className="card">
            <input type="hidden" name="salonId" value={salonId} />
            <p className="hint" style={{ marginTop: 0 }}>
              The period runs on from where the last one ended, even if that was weeks ago: a
              salon that pays late pays for the time it had. It becomes writable again only if
              the payment covers today.
            </p>
            <div className="row">
              <div>
                <label htmlFor="pay-amount">Amount received (₹)</label>
                <input
                  id="pay-amount"
                  name="amount"
                  inputMode="decimal"
                  defaultValue={s.monthly_price_paise ? String(s.monthly_price_paise / 100) : ''}
                  required
                />
              </div>
              <div>
                <label htmlFor="pay-months">Months it covers</label>
                <input id="pay-months" name="months" type="number" min={1} max={24} defaultValue={1} />
              </div>
              <div>
                <label htmlFor="pay-ref">Reference (required)</label>
                <input id="pay-ref" name="reference" placeholder="NEFT UTR / UPI ref" required />
              </div>
              <div>
                <label htmlFor="pay-date">Paid on</label>
                <input id="pay-date" name="paidOn" type="date" />
              </div>
            </div>
            <Result state={payState} />
            <div className="actions">
              <button disabled={savingPay}>{savingPay ? 'Saving…' : 'Record payment'}</button>
            </div>
          </form>

          <h2>Extend (comp)</h2>
          <form action={saveExt} className="card">
            <input type="hidden" name="salonId" value={salonId} />
            <p className="hint" style={{ marginTop: 0 }}>
              Days given away - for an outage, a goodwill gesture, a slow month. Audited with the
              reason.
            </p>
            <div className="row">
              <div>
                <label htmlFor="ext-days">Days</label>
                <input id="ext-days" name="days" type="number" min={1} max={90} defaultValue={7} />
              </div>
              <div>
                <label htmlFor="ext-reason">Reason (required)</label>
                <input id="ext-reason" name="reason" placeholder="Outage on 12 Oct" required />
              </div>
            </div>
            <Result state={extState} />
            <div className="actions">
              <button className="secondary" disabled={savingExt}>
                {savingExt ? 'Saving…' : 'Extend'}
              </button>
            </div>
          </form>
        </>
      )}

      <h2>Features</h2>
      <p className="hint">
        What the plan includes, and any override for this salon. The server enforces it - the
        app hides the button only as a courtesy. Which plan carries which feature is still open
        (PRD 21 Q-A), so today every plan carries every built feature.
      </p>
      <form action={saveFlag} className="card">
        <input type="hidden" name="salonId" value={salonId} />
        <table>
          <thead>
            <tr>
              <th>Feature</th>
              <th>In the plan</th>
              <th>Override</th>
              <th>Effective</th>
            </tr>
          </thead>
          <tbody>
            {(Object.keys(billing.features) as Feature[]).map((f) => {
              const row = billing.features[f];
              return (
                <tr key={f}>
                  <td>{FEATURE_WORDS[f]}</td>
                  <td>{row.plan ? 'Yes' : 'No'}</td>
                  <td>{row.override === null ? '—' : row.override ? 'On' : 'Off'}</td>
                  <td>
                    <strong style={{ color: row.effective ? 'var(--ok)' : 'var(--danger)' }}>
                      {row.effective ? 'On' : 'Off'}
                    </strong>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        <div className="row">
          <div>
            <label htmlFor="flag">Feature</label>
            <select id="flag" name="flag">
              <option value="dashboard">{FEATURE_WORDS.dashboard}</option>
              <option value="referrals">{FEATURE_WORDS.referrals}</option>
            </select>
          </div>
          <div>
            <label htmlFor="flag-value">Set to</label>
            <select id="flag-value" name="value" defaultValue="plan">
              <option value="plan">Follow the plan</option>
              <option value="on">On</option>
              <option value="off">Off</option>
            </select>
          </div>
          <div>
            <label htmlFor="flag-reason">Reason (required)</label>
            <input id="flag-reason" name="reason" placeholder="Comped for the pilot" required />
          </div>
        </div>
        <Result state={flagState} />
        <div className="actions">
          <button className="secondary" disabled={savingFlag}>
            {savingFlag ? 'Saving…' : 'Save override'}
          </button>
        </div>
      </form>
    </>
  );
}
