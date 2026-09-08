import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { listSalons } from '@/server/admin-db';
import { SalonRow } from './salon-row';

export const dynamic = 'force-dynamic';

function rupees(paise: string | null): string {
  if (paise === null) return '—';
  const n = Number(paise) / 100;
  // Indian grouping, as everywhere else money appears.
  return '₹' + n.toLocaleString('en-IN', { maximumFractionDigits: 0 });
}

export default async function Page() {
  const admin = await requireAdmin();
  const salons = await listSalons();

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/provision">Provision a salon</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Salons</h1>
        <p className="hint">
          {salons.length === 0
            ? 'No salons yet. Provisioning one creates the tenant, its join code and its owner in a single transaction.'
            : `${salons.length} salon${salons.length === 1 ? '' : 's'}. A salon in setup cannot bind customers, even if its QR has leaked.`}
        </p>

        {salons.length > 0 && (
          <div className="card">
            <table>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Code</th>
                  <th>Status</th>
                  <th>Setup fee</th>
                  <th>Integrations</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {salons.map((s) => (
                  <SalonRow key={s.id} salon={s} feeLabel={rupees(s.setup_fee_paise)} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </>
  );
}
