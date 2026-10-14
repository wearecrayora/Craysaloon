import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { listAudit, listSalonNames } from '@/server/admin-db';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

const KIND: Record<string, string> = {
  platform_admin: 'Crayora',
  owner: 'Owner',
  manager: 'Manager',
  staff: 'Stylist',
  system: 'System',
};

/** A short, readable summary of what changed - never a raw JSON dump. */
function summary(after: unknown): string {
  if (!after || typeof after !== 'object') return '';
  return Object.entries(after as Record<string, unknown>)
    .filter(([, v]) => v !== null && typeof v !== 'object')
    .slice(0, 4)
    .map(([k, v]) => `${k.replace(/_/g, ' ')}: ${String(v)}`)
    .join(' · ');
}

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ salon?: string; action?: string; actor?: string; days?: string }>;
}) {
  const admin = await requireAdmin();
  const q = await searchParams;
  const days = Number(q.days ?? 30) || 30;
  const [rows, salons] = await Promise.all([
    listAudit({
      salonId: q.salon || null,
      action: q.action?.trim() || null,
      actorKind: q.actor || null,
      days,
    }),
    listSalonNames(),
  ]);

  return (
    <ConsoleShell admin={admin} active="audit">
      <h1>Audit log</h1>
      <p className="hint">
        Everything recorded against a person: every console action, and the owner&rsquo;s own
        decisions in the app. Append-only - nothing here can be edited or removed. Newest first,
        200 at most; narrow it with the filters.
      </p>

      <form className="card" method="get" style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', alignItems: 'end' }}>
        <div>
          <label htmlFor="salon">Salon</label>
          <select id="salon" name="salon" defaultValue={q.salon ?? ''}>
            <option value="">All salons</option>
            {salons.map((s) => (
              <option key={s.id} value={s.id}>{s.display_name}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="actor">Who</label>
          <select id="actor" name="actor" defaultValue={q.actor ?? ''}>
            <option value="">Anyone</option>
            {Object.entries(KIND).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="action">Action contains</label>
          <input id="action" name="action" defaultValue={q.action ?? ''} placeholder="e.g. login, credential" />
        </div>
        <div>
          <label htmlFor="days">Period</label>
          <select id="days" name="days" defaultValue={String(days)}>
            <option value="1">Last 24 hours</option>
            <option value="7">Last 7 days</option>
            <option value="30">Last 30 days</option>
            <option value="90">Last 90 days</option>
            <option value="365">Last year</option>
          </select>
        </div>
        <div className="actions" style={{ margin: 0 }}>
          <button>Show</button>
          <Link href="/audit" style={{ alignSelf: 'center', fontSize: 13 }}>Clear</Link>
        </div>
      </form>

      <div className="card">
        {rows.length === 0 ? (
          <p className="hint" style={{ margin: 0 }}>Nothing recorded for these filters.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>Salon</th>
                <th>Who</th>
                <th>Action</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td style={{ whiteSpace: 'nowrap' }}>
                    {new Date(r.created_at).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}
                  </td>
                  <td>{r.salon_name ?? <span className="hint">platform</span>}</td>
                  <td>
                    {r.actor_name ?? '—'}
                    <br />
                    <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>{KIND[r.actor_kind] ?? r.actor_kind}</span>
                  </td>
                  <td style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13 }}>{r.action}</td>
                  <td style={{ fontSize: 13 }}>
                    {summary(r.after_state)}
                    {r.reason && (
                      <>
                        <br />
                        <em>Reason: {r.reason}</em>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </ConsoleShell>
  );
}
