import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getMessagingStats, getSalon, getSetupFacts } from '@/server/admin-db';
import { formatPaise } from '@/lib/money';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

const CHANNEL: Record<string, string> = {
  push: 'Push (free)',
  whatsapp: 'WhatsApp',
  sms: 'SMS',
  rcs: 'RCS',
};

const SENDER: Record<string, string> = {
  salon: 'The salon’s own account',
  platform: 'Crayora’s account - a fallback',
  trial: 'Crayora’s account - messaging trial',
  grace: 'Crayora’s account - grace period',
  unknown: 'Unknown',
};

const pct = (part: number, whole: number) => (whole ? `${Math.round((part / whole) * 100)}%` : '—');

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const [stats, facts] = await Promise.all([getMessagingStats(id), getSetupFacts(id)]);

  const total = stats.channels.reduce((a, c) => a + c.attempts, 0);
  const cost = stats.channels.reduce((a, c) => a + c.cost_paise, 0);
  const push = stats.channels.find((c) => c.channel === 'push');
  const fallbacks = stats.otp.filter((o) => o.sender === 'platform').reduce((a, o) => a + o.n, 0);

  return (
    <ConsoleShell admin={admin} salon={salon} active="messaging">
      <h1>Messaging — {salon.display_name}</h1>
      <p className="hint">
        The last 30 days. Every message goes by push - it is free.
      </p>
      <p className="notice">
        <strong>The SMS and WhatsApp fallback is switched off for every salon</strong> (14 Oct 2026).
        Push is the only channel; a message that is not seen is not re-sent at the salon&rsquo;s cost.
        Login codes are separate and still go by SMS. Settings saved on{' '}
        <Link href={`/salon/${id}/credentials`}>Credentials</Link> are kept for when it is switched
        back on.
      </p>

      <div className="card" style={{ display: 'grid', gap: 16, gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))' }}>
        <div>
          <div className="hint" style={{ margin: 0 }}>Messages tried</div>
          <strong style={{ fontSize: 22 }}>{total}</strong>
        </div>
        <div>
          <div className="hint" style={{ margin: 0 }}>Pushes seen on the phone</div>
          <strong style={{ fontSize: 22 }}>{push ? pct(push.acked, push.sent) : '—'}</strong>
        </div>
        <div>
          <div className="hint" style={{ margin: 0 }}>Cost to the salon</div>
          <strong style={{ fontSize: 22, fontVariantNumeric: 'tabular-nums' }}>{formatPaise(String(cost))}</strong>
        </div>
        <div>
          <div className="hint" style={{ margin: 0 }}>Login codes on Crayora&rsquo;s account</div>
          <strong style={{ fontSize: 22, color: fallbacks ? 'var(--warn)' : undefined }}>{fallbacks}</strong>
        </div>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>By channel</h2>
        {stats.channels.length === 0 ? (
          <p className="hint" style={{ margin: 0 }}>No messages in the last 30 days.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Channel</th>
                <th>Tried</th>
                <th>Sent</th>
                <th>Seen</th>
                <th>Failed</th>
                <th style={{ textAlign: 'right' }}>Cost</th>
              </tr>
            </thead>
            <tbody>
              {stats.channels.map((c) => (
                <tr key={c.channel}>
                  <td><strong>{CHANNEL[c.channel] ?? c.channel}</strong></td>
                  <td>{c.attempts}</td>
                  <td>{c.sent}</td>
                  <td>{c.channel === 'push' ? `${c.acked} (${pct(c.acked, c.sent)})` : '—'}</td>
                  <td>{c.failed}</td>
                  <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{formatPaise(String(c.cost_paise))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="hint" style={{ marginBottom: 0 }}>
          &ldquo;Seen&rdquo; means the app confirmed the push arrived - Google accepting it is not enough.
          WhatsApp and SMS cannot be confirmed this way.
        </p>
      </div>

      {stats.failures.length > 0 && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Why messages failed</h2>
          <table>
            <tbody>
              {stats.failures.map((f) => (
                <tr key={f.reason}>
                  <td style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13 }}>{f.reason}</td>
                  <td style={{ textAlign: 'right' }}>{f.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="card">
        <h2 style={{ marginTop: 0 }}>Login codes (OTP)</h2>
        {stats.otp.length === 0 ? (
          <p className="hint" style={{ margin: 0 }}>No login codes sent in the last 30 days.</p>
        ) : (
          <table>
            <tbody>
              {stats.otp.map((o) => (
                <tr key={o.sender}>
                  <td>{SENDER[o.sender] ?? o.sender}</td>
                  <td style={{ textAlign: 'right' }}>{o.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {!facts?.mc_has_secret && (
          <div className="notice" style={{ marginBottom: 0 }}>
            This salon has no Message Central account of its own yet, so its login codes are sent
            from Crayora&rsquo;s. <Link href={`/salon/${id}/credentials`}>Add it on Credentials →</Link>
          </div>
        )}
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>Notifications by outcome</h2>
        {stats.notifications.length === 0 ? (
          <p className="hint" style={{ margin: 0 }}>None in the last 30 days.</p>
        ) : (
          <table>
            <tbody>
              {stats.notifications.map((n) => (
                <tr key={n.status}>
                  <td>{n.status.replace(/_/g, ' ')}</td>
                  <td style={{ textAlign: 'right' }}>{n.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </ConsoleShell>
  );
}
