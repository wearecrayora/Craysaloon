'use client';

import { useActionState } from 'react';
import {
  creditSettledAction,
  exportOfferedAction,
  purgeAction,
  type ActionState,
} from '@/app/actions';
import type { OffboardingFacts } from '@/server/admin-db';

const empty: ActionState = {};

function Result({ state }: { state: ActionState }) {
  if (state.error) return <div className="error">{state.error}</div>;
  if (state.ok) return <div className="notice">{state.ok}</div>;
  return null;
}

const fmt = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : null;

/**
 * Offboarding, in the order PRD 16A.6 requires it: offer the export, settle the
 * customers' credit, then purge. Each step is refused by the DATABASE until the
 * one before it is recorded; this page only lays them out in order.
 */
export function Offboarding({
  salonId,
  displayName,
  facts,
  purgeDue,
  outstandingLabel,
}: {
  salonId: string;
  displayName: string;
  facts: OffboardingFacts;
  purgeDue: boolean;
  outstandingLabel: string;
}) {
  const [exportState, saveExport, savingExport] = useActionState(exportOfferedAction, empty);
  const [creditState, saveCredit, savingCredit] = useActionState(creditSettledAction, empty);
  const [purgeState, purge, purging] = useActionState(purgeAction, empty);

  if (facts.purged_at) {
    return (
      <>
        <h2>Offboarding</h2>
        <div className="notice">
          <strong>Purged on {fmt(facts.purged_at)}.</strong> Customers and staff are anonymised and
          cannot log in; the salon&rsquo;s credentials are deleted. Its payments and ledgers are
          kept, anonymised, for the books - reachable only from this console.
        </div>
      </>
    );
  }

  return (
    <>
      <h2>Offboarding</h2>
      <p className="hint">
        Super-admins only. Three steps, in order: the owner is offered their data, the
        customers&rsquo; credit is settled, then personal data is purged. Financial records are
        never deleted - they stay, anonymised, for the statutory period.
      </p>

      <div className="card">
        <strong>1. Offer the owner their data</strong>
        <p className="hint">
          <a href={`/salon/${salonId}/export`}>Download the salon&rsquo;s export (JSON)</a> - then
          send it to the owner and record how.{' '}
          {facts.export_offered_at &&
            `Recorded ${fmt(facts.export_offered_at)}: “${facts.export_offered_note}”.`}
        </p>
        <form action={saveExport}>
          <input type="hidden" name="salonId" value={salonId} />
          <label htmlFor="export-note">How it was offered</label>
          <input id="export-note" name="note" placeholder="Emailed to the owner on 2 Jan" />
          <Result state={exportState} />
          <div className="actions">
            <button className="secondary" disabled={savingExport}>
              {savingExport ? 'Saving…' : 'Record export offered'}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <strong>2. Settle the customers&rsquo; credit</strong>
        <p className="hint">
          Customers hold <strong>{outstandingLabel}</strong> at this salon. A salon cannot keep money
          for services it will never provide: record how it paid them back. The ledger is not
          changed - the balances stay in the books beside your note.{' '}
          {facts.credit_settled_at &&
            `Recorded ${fmt(facts.credit_settled_at)}: “${facts.credit_settled_note}”.`}
        </p>
        <form action={saveCredit}>
          <input type="hidden" name="salonId" value={salonId} />
          <label htmlFor="credit-note">How it was settled</label>
          <input
            id="credit-note"
            name="note"
            placeholder="Refunded in cash at the counter; list signed by the owner"
          />
          <Result state={creditState} />
          <div className="actions">
            <button className="secondary" disabled={savingCredit}>
              {savingCredit ? 'Saving…' : 'Record settlement'}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <strong>3. Purge</strong>
        <p className="hint">
          {purgeDue
            ? 'Due now. This anonymises every customer and staff member, releases their bindings so they can join another salon, deletes messages, tokens and credentials, and closes the salon for good. It cannot be undone.'
            : 'Not due yet - purge comes 90 days after suspension. The database refuses it before then.'}
        </p>
        <form action={purge}>
          <input type="hidden" name="salonId" value={salonId} />
          <div className="row">
            <div>
              <label htmlFor="purge-reason">Reason (audited)</label>
              <input id="purge-reason" name="reason" placeholder="Owner closed the business" />
            </div>
            <div>
              <label htmlFor="purge-name">
                Type <strong>{displayName}</strong> to confirm
              </label>
              <input id="purge-name" name="typedName" autoComplete="off" />
            </div>
          </div>
          <Result state={purgeState} />
          <div className="actions">
            <button disabled={purging || !purgeDue}>{purging ? 'Purging…' : 'Purge personal data'}</button>
          </div>
        </form>
      </div>
    </>
  );
}
