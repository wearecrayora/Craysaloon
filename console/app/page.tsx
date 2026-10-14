import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { listSalons } from '@/server/admin-db';
import { formatPaise } from '@/lib/money';
import { SalonRow } from './salon-row';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const admin = await requireAdmin();
  const salons = await listSalons();

  return (
    <>

      <ConsoleShell admin={admin} active="salons">
        <h1>Salons</h1>
        <p className="hint">
          {salons.length === 0
            ? 'No salons yet. Provisioning one creates the tenant, its join code and its owner in a single transaction.'
            : `${salons.length} salon${salons.length === 1 ? '' : 's'}. A salon in setup cannot bind customers, even if its QR has leaked.`}
        </p>

        <details className="card" open={salons.length === 0}>
          <summary style={{ cursor: 'pointer', fontWeight: 600 }}>How this console works</summary>
          <ol style={{ margin: '12px 0 0', paddingLeft: 20, lineHeight: 1.75 }}>
            <li>
              <strong>Provision</strong> the salon under <Link href="/provision">New salon</Link>: its
              names, the owner&rsquo;s name and mobile number, the plan and setup fee. It is created
              in <em>setup</em> - nobody can join it yet.
            </li>
            <li>
              Open the salon&rsquo;s <strong>Set up</strong> checklist (click its name below). It shows
              what is done, what is missing, and links to each page: branding and logo, the menu
              and stylists, Message Central and Razorpay, SMS/WhatsApp, the privacy contact and the
              setup fee.
            </li>
            <li>
              <strong>Switch it on</strong> under Billing and activation once the required steps are
              ticked. Then download the <strong>QR pack</strong> for the counter.
            </li>
            <li>
              The <strong>owner</strong> installs the app, enters the salon code, then their own
              number. Managers and stylists are added under the salon&rsquo;s <strong>Logins</strong>{' '}
              and sign in the same way.
            </li>
            <li>
              Any change made here - prices, stylists, branding, rules - reaches every phone within
              minutes. No app update is ever needed.
            </li>
          </ol>
          <p className="hint" style={{ marginBottom: 0 }}>
            Everything you do here is recorded against your name. Credentials can be replaced but
            never read back.
          </p>
        </details>

        {salons.length > 0 && (
          <div className="card">
            <table>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Code</th>
                  <th>Status</th>
                  <th>Setup fee</th>
                  <th>OTP &amp; integrations</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {salons.map((s) => (
                  <SalonRow key={s.id} salon={s} feeLabel={formatPaise(s.setup_fee_paise)} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </ConsoleShell>
    </>
  );
}
