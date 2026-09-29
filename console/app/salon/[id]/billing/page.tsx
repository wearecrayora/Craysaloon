import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import {
  getBillingOverview,
  getOffboardingFacts,
  getSalon,
  type BillingState,
} from '@/server/admin-db';
import { formatPaise } from '@/lib/money';
import { BillingForms } from './forms';
import { Offboarding } from './offboarding';

export const dynamic = 'force-dynamic';

const fmt = (iso: string | null | undefined) =>
  iso
    ? new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })
    : '—';

const STATE_WORDS: Record<BillingState, string> = {
  unbilled: 'Not billed yet',
  active: 'Paid up',
  grace: 'GRACE - read-only',
  suspended: 'SUSPENDED - read-only',
  purge_due: 'PURGE DUE',
};

const NOTICE_WORDS: Record<string, string> = {
  grace_started: 'Payment missed - the salon went read-only',
  suspended: 'Grace ended - suspended',
  retention_60: 'Day 60 of suspension - call the owner',
  retention_80: 'Day 80 of suspension - call the owner, last warning',
  purge_due: 'Day 90 - purge is due (offer the export, settle customer credit first)',
};

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const billing = await getBillingOverview(admin.id, id);
  if (!billing) notFound();

  const facts = await getOffboardingFacts(id);
  const state = billing.dates?.state ?? 'unbilled';
  const lapsed = state === 'grace' || state === 'suspended' || state === 'purge_due';

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href="/metrics">Metrics</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Billing — {salon.display_name}</h1>
        <p className="hint">
          Everything here is collected <strong>offline</strong> - cash or bank transfer - and
          recorded with its reference, which is the only evidence it was collected at all. The
          state below is computed by the database from the date the paid period ends; nothing here
          can disagree with what the salon&rsquo;s app actually allows.
        </p>

        <div className={lapsed ? 'error' : 'notice'}>
          <strong>{STATE_WORDS[state]}.</strong>{' '}
          {state === 'unbilled' &&
            'Set the plan and billing start date below. Until then the salon is never read-only for billing.'}
          {state === 'active' && `Paid until ${fmt(billing.dates?.renews_at)}.`}
          {state === 'grace' &&
            `Payment was due ${fmt(billing.dates?.renews_at)}. The owner and staff can read but not change anything, and nobody new can join. Suspended on ${fmt(billing.dates?.grace_ends_at)} unless paid.`}
          {state === 'suspended' &&
            `Suspended since ${fmt(billing.dates?.grace_ends_at)}. Notices at day 60 (${fmt(billing.dates?.notice_60_at)}) and day 80 (${fmt(billing.dates?.notice_80_at)}); purge is due ${fmt(billing.dates?.purge_after)}.`}
          {state === 'purge_due' &&
            'Purge is due. Nothing has been deleted - purging is a separate, deliberate act that first offers the owner an export and settles any customer credit.'}
          {lapsed &&
            ' Customers can still see their wallets and withdraw consent; payments Razorpay already captured still credit.'}
          {!billing.writable && !lapsed && salon.status !== 'setup' && (
            <> The salon is read-only for another reason (its status, or messaging).</>
          )}
        </div>

        <div className="card">
          <table>
            <tbody>
              <tr>
                <th style={{ textAlign: 'left' }}>Plan</th>
                <td>{billing.subscription.plan}</td>
                <th style={{ textAlign: 'left' }}>Agreed price</th>
                <td>{formatPaise(billing.subscription.monthly_price_paise)} / month</td>
              </tr>
              <tr>
                <th style={{ textAlign: 'left' }}>Billing started</th>
                <td>{fmt(billing.subscription.billing_starts_on)}</td>
                <th style={{ textAlign: 'left' }}>Paid until</th>
                <td>{fmt(billing.dates?.renews_at)}</td>
              </tr>
              <tr>
                <th style={{ textAlign: 'left' }}>Setup fee</th>
                <td>
                  {billing.subscription.setup_fee_status} ·{' '}
                  {formatPaise(billing.subscription.setup_fee_paise)}
                </td>
                <th style={{ textAlign: 'left' }}>Reference</th>
                <td>
                  {billing.subscription.setup_fee_reference ?? '—'}
                  {billing.subscription.setup_fee_paid_on &&
                    ` · ${fmt(billing.subscription.setup_fee_paid_on)}`}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        {billing.notices.length > 0 && (
          <>
            <h2>Notices</h2>
            <p className="hint">
              Each fires once, when it falls due. There is no automatic message to the owner yet -
              each one is a call to make. The owner&rsquo;s app shows the state every time it
              opens.
            </p>
            <div className="card">
              <table>
                <tbody>
                  {billing.notices.map((n) => (
                    <tr key={`${n.kind}-${n.cycle_renews_at}`}>
                      <td>{fmt(n.due_at)}</td>
                      <td>{NOTICE_WORDS[n.kind] ?? n.kind}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}

        <BillingForms salonId={id} billing={billing} salonStatus={salon.status} />

        {admin.isSuper && facts && (state === 'suspended' || state === 'purge_due' || facts.purged_at) && (
          <Offboarding
            salonId={id}
            displayName={salon.display_name}
            facts={facts}
            purgeDue={state === 'purge_due'}
            outstandingLabel={formatPaise(facts.outstanding_paise)}
          />
        )}

        <h2>Payments received</h2>
        {billing.payments.length === 0 ? (
          <p className="hint">None recorded yet.</p>
        ) : (
          <div className="card">
            <table>
              <thead>
                <tr>
                  <th>Paid on</th>
                  <th>Amount</th>
                  <th>Covers</th>
                  <th>Reference</th>
                  <th>Recorded by</th>
                </tr>
              </thead>
              <tbody>
                {billing.payments.map((p) => (
                  <tr key={p.id}>
                    <td>{fmt(p.paid_on)}</td>
                    <td>{formatPaise(p.amount_paise)}</td>
                    <td>
                      {p.months} month{p.months === 1 ? '' : 's'}: {fmt(p.period_start)} –{' '}
                      {fmt(p.period_end)}
                    </td>
                    <td className="code">{p.reference}</td>
                    <td>{p.recorded_by ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="hint">
          Payments are append-only and cannot be edited. There is no reversal action yet, so check
          the amount and the months before saving: a payment recorded twice moves the paid-until
          date twice.
        </p>
      </main>
    </>
  );
}
