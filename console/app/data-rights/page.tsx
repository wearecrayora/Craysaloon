import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { listDataRightsRequests } from '@/server/admin-db';
import { ErasureForm } from './erasure-form';

export const dynamic = 'force-dynamic';

const KIND: Record<string, string> = {
  access: 'A copy of their data',
  erasure: 'Erasure',
  grievance: 'A complaint about their data',
};

/**
 * Open data-rights requests, across every salon.
 *
 * The SALON is the Data Fiduciary and answers first. Crayora is the escalation
 * when a salon has not answered in 30 days (RULES 11.7a) - which is why this
 * page sorts by deadline and marks the overdue ones.
 *
 * There are no customer names or numbers on it, by design (0081). The operator
 * acts on the request; the database resolves whose it is.
 */
export default async function Page() {
  const admin = await requireAdmin();
  const requests = await listDataRightsRequests(admin.id);

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href="/customers/binding">Customer binding</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Data-rights requests</h1>
        <p className="hint">
          Customers ask from the app, under <strong>Your data</strong>. The salon owes an answer
          within 30 days; past that, it comes to us. Nothing here names the customer - you act on
          the request, and the database finds whose it is.
        </p>

        {requests.length === 0 ? (
          <div className="card">
            <p style={{ margin: 0 }}>No open requests.</p>
          </div>
        ) : (
          requests.map((r) => (
            <div key={r.request_id} className="card">
              <div style={{ display: 'flex', gap: 10, alignItems: 'baseline', flexWrap: 'wrap' }}>
                <h2 style={{ margin: 0 }}>{KIND[r.kind] ?? r.kind}</h2>
                <span className="hint" style={{ margin: 0 }}>{r.salon_name}</span>
                {r.overdue && <span className="pill suspended">overdue</span>}
              </div>
              <p className="hint" style={{ margin: '6px 0 0' }}>
                Asked {new Date(r.requested_at).toLocaleDateString('en-IN')} · due{' '}
                {new Date(r.due_at).toLocaleDateString('en-IN')} · {r.status}
              </p>

              {r.kind === 'erasure' ? (
                <ErasureForm requestId={r.request_id} />
              ) : (
                <p className="hint">
                  The salon answers this one. If it is overdue, contact the salon&rsquo;s privacy
                  contact (on its <strong>Privacy contact</strong> page) before anything else.
                </p>
              )}
            </div>
          ))
        )}
      </main>
    </>
  );
}
