import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, getAppConfig, listAnnouncements } from '@/server/admin-db';
import { ConsoleShell } from '@/app/shell';
import { AppConfigForm, AnnounceForm, EndAnnouncement } from './forms';

export const dynamic = 'force-dynamic';

/**
 * The salon's app, from here (0119): what the home screen shows and in what
 * order, which features are switched on, and the salon's announcements.
 * Customers' apps pick a change up within seconds if open, else on next open -
 * no app update.
 */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const config = await getAppConfig(admin.id, id);
  const announcements = await listAnnouncements(admin.id, id);

  return (
    <ConsoleShell admin={admin} salon={salon} active="app">
      <h1>App home &amp; announcements — {salon.display_name}</h1>
      <p className="hint">
        Changes here reach this salon&rsquo;s customers <strong>without an app update</strong>: within
        seconds for anyone with the app open, otherwise the next time they open it. Every save is in
        the audit log with its reason. What stays fixed: a bill to pay, today&rsquo;s booking and the
        next one always come first on the home screen, and <strong>Your data</strong> is always one
        tap away - those are not layout choices.
      </p>

      {config ? (
        <AppConfigForm salonId={id} config={config} />
      ) : (
        <div className="notice">This salon has no app config row - reload; it is created automatically.</div>
      )}

      <h2>Announcements</h2>
      <p className="hint">
        The salon&rsquo;s own news, on its customers&rsquo; home screen between the dates you set -
        &ldquo;Closed on Diwali&rdquo;, &ldquo;New: keratin treatment&rdquo;. Real news only: an offer
        the salon has not made is a promise the counter will not keep.
      </p>
      {announcements.length > 0 && (
        <div className="card">
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>From</th>
                <th>Until</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {announcements.map((a) => (
                <tr key={a.id}>
                  <td>{a.title}</td>
                  <td>{new Date(a.starts_at).toLocaleString('en-IN')}</td>
                  <td>{new Date(a.ends_at).toLocaleString('en-IN')}</td>
                  <td>{a.live ? 'Live' : a.ended_at ? 'Ended early' : 'Not live'}</td>
                  <td>{a.live && <EndAnnouncement id={a.id} salonId={id} />}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <AnnounceForm target={id} />
    </ConsoleShell>
  );
}
