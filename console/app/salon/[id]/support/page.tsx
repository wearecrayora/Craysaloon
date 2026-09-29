import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import {
  getSalon,
  listSupportSessions,
  supportCustomers,
  type SupportCustomer,
} from '@/server/admin-db';
import { formatPaise } from '@/lib/money';
import { EndSession, StartSession, Unmask } from './forms';

export const dynamic = 'force-dynamic';

const time = (iso: string) =>
  new Date(iso).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });

/**
 * Support mode (RULES 6.8, ARCHITECTURE 14.2): time-boxed, reason required,
 * the phone masked to its last four digits, un-masking a separate logged act.
 * Customer data appears ONLY while this operator has a live session - the
 * database refuses the query otherwise, so this page cannot show more than it
 * is allowed to even if it tried.
 */
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ q?: string }>;
}) {
  const { id } = await params;
  const { q } = await searchParams;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();

  const sessions = await listSupportSessions(admin.id, id);
  const mine = sessions.find((s) => s.live && s.mine) ?? null;

  let customers: SupportCustomer[] = [];
  if (mine) customers = await supportCustomers(admin.id, id, q?.trim() || null);

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href={`/salon/${id}/billing`}>Billing</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      {mine && (
        <div className="error" style={{ margin: 0, borderRadius: 0, textAlign: 'center' }}>
          <strong>Support mode</strong> · {salon.display_name} · ends {time(mine.ends_at)} ·
          reason: {mine.reason}
        </div>
      )}

      <main className="wrap">
        <h1>Support — {salon.display_name}</h1>
        <p className="hint">
          Customer data is visible only inside a session you start with a reason, for at most two
          hours. Numbers are masked to their last four digits; seeing a whole number is a separate
          action with its own reason. Every start, end and un-mask is in the audit log.
        </p>

        {mine ? (
          <>
            <EndSession salonId={id} sessionId={mine.id} />

            <form method="get" className="card" style={{ display: 'flex', gap: 8 }}>
              <input name="q" defaultValue={q ?? ''} placeholder="Name starts with… or last 4 digits" />
              <button className="secondary">Search</button>
            </form>

            <div className="card">
              <table>
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Phone</th>
                    <th>Wallet</th>
                    <th>Last visit</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {customers.length === 0 && (
                    <tr>
                      <td colSpan={5} className="hint">
                        No customers match.
                      </td>
                    </tr>
                  )}
                  {customers.map((c) => (
                    <tr key={c.customer_id}>
                      <td>{c.anonymised ? <em>anonymised</em> : c.name ?? '—'}</td>
                      <td className="code">{c.phone_last4 ? `•••••• ${c.phone_last4}` : '—'}</td>
                      <td>{formatPaise(c.balance_paise)}</td>
                      <td>{c.last_visit_at ? time(c.last_visit_at) : '—'}</td>
                      <td>{!c.anonymised && <Unmask customerId={c.customer_id} />}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        ) : (
          <StartSession salonId={id} />
        )}

        <h2>Recent sessions</h2>
        {sessions.length === 0 ? (
          <p className="hint">None.</p>
        ) : (
          <div className="card">
            <table>
              <tbody>
                {sessions.map((s) => (
                  <tr key={s.id}>
                    <td>{time(s.started_at)}</td>
                    <td>{s.admin}</td>
                    <td>{s.reason}</td>
                    <td>
                      {s.live
                        ? `live until ${time(s.ends_at)}`
                        : s.ended_at
                          ? `ended ${time(s.ended_at)}`
                          : `expired ${time(s.ends_at)}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </>
  );
}
