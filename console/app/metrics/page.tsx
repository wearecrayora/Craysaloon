import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { getPlatformMetrics } from '@/server/admin-db';
import { formatPaise } from '@/lib/money';

export const dynamic = 'force-dynamic';

function Tile({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="card" style={{ margin: 0 }}>
      <div style={{ color: 'var(--ink-soft)', fontSize: 13 }}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
        {value}
      </div>
      {note && <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>{note}</div>}
    </div>
  );
}

export default async function Page() {
  const admin = await requireAdmin();
  const m = await getPlatformMetrics(admin.id);

  const billing = m.billing ?? {};
  const lapsed = (billing.grace ?? 0) + (billing.suspended ?? 0) + (billing.purge_due ?? 0);
  const push = m.sends_30d.push ?? 0;
  const paid = Object.entries(m.sends_30d)
    .filter(([channel]) => channel !== 'push')
    .reduce((sum, [, n]) => sum + n, 0);

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Platform</h1>
        <p className="hint">
          Computed live from the database. Revenue counts only salons paid up today; a salon in
          grace has not paid, so it is not recurring revenue until it does.
        </p>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
            gap: 12,
            marginBottom: 24,
          }}
        >
          <Tile
            label="MRR"
            value={formatPaise(m.mrr_paise)}
            note={`${billing.active ?? 0} paid-up salon${billing.active === 1 ? '' : 's'}`}
          />
          <Tile
            label="Subscription received, last 30 days"
            value={formatPaise(m.subscription_revenue_30d_paise)}
          />
          <Tile label="Setup fees collected, all time" value={formatPaise(m.setup_fees_paise)} />
          <Tile
            label="Lapsed now"
            value={String(lapsed)}
            note={`grace ${billing.grace ?? 0} · suspended ${billing.suspended ?? 0} · purge due ${billing.purge_due ?? 0}`}
          />
          <Tile label="Activations, last 30 days" value={String(m.activations_30d)} />
          <Tile
            label="Churned, last 30 days"
            value={String(m.churned_30d)}
            note="Grace ended unpaid in the last 30 days"
          />
          <Tile
            label="Push : paid messages, last 30 days"
            value={paid === 0 ? `${push} : 0` : `${(push / paid).toFixed(1)} : 1`}
            note={`${push} push · ${paid} WhatsApp/SMS/RCS - billed to the salons`}
          />
          <Tile
            label="Median time to first customer"
            value={
              m.median_hours_to_first_bind === null
                ? 'not yet'
                : m.median_hours_to_first_bind < 48
                  ? `${m.median_hours_to_first_bind} h`
                  : `${Math.round(m.median_hours_to_first_bind / 24)} days`
            }
            note={`${m.salons_never_bound} activated salon${m.salons_never_bound === 1 ? '' : 's'} with no customer yet`}
          />
        </div>

        <h2>Salons by status</h2>
        <div className="card">
          <table>
            <tbody>
              {Object.entries(m.salons ?? {}).map(([status, n]) => (
                <tr key={status}>
                  <td>
                    <span className={`pill ${status}`}>{status}</span>
                  </td>
                  <td style={{ fontVariantNumeric: 'tabular-nums' }}>{n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </>
  );
}
