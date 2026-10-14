import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, getSetupFacts, listSalonLogins } from '@/server/admin-db';
import { ConsoleShell } from '@/app/shell';
import { AddLoginForm, LoginRow } from './forms';

export const dynamic = 'force-dynamic';

const ROLE: Record<string, string> = { owner: 'Owner', manager: 'Manager', staff: 'Stylist' };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const [logins, facts] = await Promise.all([listSalonLogins(id), getSetupFacts(id)]);

  return (
    <ConsoleShell admin={admin} salon={salon} active="logins">
      <h1>Logins — {salon.display_name}</h1>
      <p className="hint">
        Who can open this salon&rsquo;s own screens in the app - the day view, walk-ins, customers,
        the menu, the team and the dashboard. Everyone signs in the same way: open the app, enter
        the salon code <strong style={{ fontFamily: 'ui-monospace, monospace' }}>{facts?.join_code}</strong>,
        then <strong>their own mobile number</strong> and the one-time code it receives.
      </p>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>What each role can do</h2>
        <table>
          <tbody>
            <tr>
              <td><strong>Owner</strong></td>
              <td>Everything in the app: the day, bills, the menu and prices, the team and their hours, rules, the dashboard. Set when the salon was provisioned.</td>
            </tr>
            <tr>
              <td><strong>Manager</strong></td>
              <td>The same day-to-day work as the owner, including the menu, the team and their hours. Not the owner&rsquo;s own settings, such as bonus expiry.</td>
            </tr>
            <tr>
              <td><strong>Stylist</strong></td>
              <td>The day view: their bookings, starting a service with the customer&rsquo;s code, marking it done. Cannot change prices, the menu or anyone&rsquo;s hours.</td>
            </tr>
          </tbody>
        </table>
        <p className="hint" style={{ marginBottom: 0 }}>
          A <em>stylist</em> on the Catalogue page is someone customers can book. A <em>login</em> here is
          someone who can open the salon&rsquo;s screens. Give a stylist both if they should see their
          own bookings.
        </p>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>People who can sign in</h2>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Role</th>
              <th>Number</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {logins.map((l) => (
              <LoginRow
                key={l.id}
                salonId={id}
                login={{ ...l, roleLabel: ROLE[l.role] ?? l.role }}
              />
            ))}
          </tbody>
        </table>
      </div>

      <AddLoginForm salonId={id} />
    </ConsoleShell>
  );
}
