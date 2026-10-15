import { redirect } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { listOperators } from '@/server/admin-db';
import { ConsoleShell } from '@/app/shell';
import { OperatorRow } from './row';

export const dynamic = 'force-dynamic';

/**
 * Who can use this console (0115). Switching someone off ends their sessions
 * at once: RUNBOOK-BREACH.md 3, "console access by someone who should not have
 * it". Remove them from the Cloudflare Access policy too
 * (docs/runbooks/console-access.md) - that is the door in front of this one.
 */
export default async function Page() {
  const admin = await requireAdmin();
  if (!admin.isSuper) redirect('/');
  const operators = await listOperators(admin.id);

  return (
    <ConsoleShell admin={admin} active="operators">
      <h1>Operators</h1>
      <p className="hint">
        Everyone who can sign in to this console. Switching someone off ends their sessions
        immediately and is recorded in the audit log with your reason. Also remove them from the
        Cloudflare Access policy, which is the door in front of this console.
      </p>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {operators.map((o) => (
              <tr key={o.id}>
                <td>{o.name}</td>
                <td className="code">{o.email}</td>
                <td>{o.is_super ? 'Super-admin' : 'Operator'}</td>
                <td>
                  <span className="pill">{o.active ? 'Active' : 'Switched off'}</span>
                </td>
                <td>{o.id === admin.id ? <span className="hint">You</span> : <OperatorRow operator={o} />}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </ConsoleShell>
  );
}
