import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, getSetupFacts, type SetupFacts } from '@/server/admin-db';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

type Step = {
  title: string;
  why: string;
  done: boolean;
  /** Required before the salon can be switched on. */
  required?: boolean;
  /** Optional, but the salon works better with it. */
  optional?: boolean;
  href: string;
  action: string;
};

function steps(id: string, f: SetupFacts): Step[] {
  const base = `/salon/${id}`;
  return [
    {
      title: 'Branding published',
      why: 'The app wears the salon’s colours and fonts from the moment a customer enters the code.',
      done: (f.branding_version ?? 0) > 0,
      href: `${base}/branding`,
      action: 'Open the branding studio',
    },
    {
      title: 'Logo uploaded',
      why: 'Shown in the app, on every push notification and on the QR pack.',
      done: f.has_logo,
      href: `${base}/branding`,
      action: 'Upload the logo',
    },
    {
      title: 'Menu: at least one service',
      why: 'Customers book from this list. Prices are in rupees; add-ons are optional.',
      done: f.services > 0,
      href: `${base}/catalogue`,
      action: 'Add services',
    },
    {
      title: 'Team: at least one stylist',
      why: 'Every stylist starts on 10:00-17:00 every day; the owner can change hours in the app (Team → clock).',
      done: f.stylists > 0,
      href: `${base}/catalogue`,
      action: 'Add stylists',
    },
    {
      title: 'One-time codes from the salon’s own Message Central',
      why: 'Until this is set, customers’ login codes are sent from Crayora’s account, at Crayora’s cost, and each one raises an alert.',
      done: f.mc_has_secret && f.mc_status !== 'failing',
      href: `${base}/credentials`,
      action: 'Enter Message Central',
    },
    {
      title: 'Payments: the salon’s own Razorpay',
      why: 'Needed for wallet top-ups and paying bills in the app. Without it customers pay at the counter.',
      done: f.razorpay_has_secret,
      optional: true,
      href: `${base}/credentials`,
      action: 'Enter Razorpay',
    },
    {
      title: 'SMS or WhatsApp fallback',
      why: 'When a push is not seen, the reminder or confirmation goes by WhatsApp or SMS. Without it, push only.',
      done: f.sms_sender || f.whatsapp_approved,
      optional: true,
      href: `${base}/credentials`,
      action: 'Set SMS / WhatsApp',
    },
    {
      title: 'Privacy contact',
      why: 'Every customer is shown who to contact about their data (DPDP). The salon cannot be switched on without it.',
      done: f.grievance_set,
      required: true,
      href: `${base}/privacy`,
      action: 'Set the privacy contact',
    },
    {
      title: 'Setup fee recorded',
      why: 'Paid, or waived with a reason. There is no free trial - activation needs this.',
      done: f.fee_status === 'paid' || f.fee_status === 'waived',
      required: true,
      href: `${base}/billing`,
      action: 'Record the setup fee',
    },
    {
      title: 'Switched on',
      why: 'Until then, the salon code finds nothing and no customer can join - even from a leaked QR.',
      done: f.status !== 'setup',
      required: true,
      href: `${base}/billing`,
      action: 'Activate the salon',
    },
    {
      title: 'Managers and stylists can sign in',
      why: 'The owner can sign in already. Add anyone else who should open the salon’s screens.',
      done: f.logins > 0,
      optional: true,
      href: `${base}/logins`,
      action: 'Add logins',
    },
    {
      title: 'QR pack printed',
      why: 'The counter card, mirror sticker and poster customers scan to join.',
      done: false,
      optional: true,
      href: `${base}/qr`,
      action: 'Download the QR pack',
    },
  ];
}

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const facts = await getSetupFacts(id);
  if (!facts) notFound();

  const list = steps(id, facts);
  const core = list.filter((s) => !s.optional && s.title !== 'QR pack printed');
  const doneCore = core.filter((s) => s.done).length;
  const next = list.find((s) => !s.done && !s.optional);

  return (
    <ConsoleShell admin={admin} salon={salon} active="overview">
      <h1>Set up — {facts.display_name}</h1>
      <p className="hint">
        Work down this list. Each line says why it matters and links to where it is done. Required
        steps are marked; everything else can be added later.
      </p>

      <div className="card">
        <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap', alignItems: 'baseline' }}>
          <div>
            <div className="hint" style={{ margin: 0 }}>Salon code</div>
            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 24, letterSpacing: '.06em' }}>
              {facts.join_code}
            </div>
          </div>
          <div>
            <div className="hint" style={{ margin: 0 }}>Status</div>
            <span className={`pill ${facts.status === 'active' ? 'active' : facts.status === 'setup' ? 'setup' : 'suspended'}`}>
              {facts.status}
            </span>
          </div>
          <div>
            <div className="hint" style={{ margin: 0 }}>Progress</div>
            <strong>
              {doneCore} of {core.length} essential steps
            </strong>
          </div>
          <div>
            <div className="hint" style={{ margin: 0 }}>Customers joined</div>
            <strong>{facts.customers}</strong>
          </div>
        </div>
        {next && (
          <div className="notice" style={{ marginBottom: 0 }}>
            <strong>Next:</strong> {next.title}.{' '}
            <Link href={next.href}>{next.action} →</Link>
          </div>
        )}
      </div>

      <div className="card">
        <ol style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {list.map((s, i) => (
            <li
              key={s.title}
              style={{
                display: 'flex',
                gap: 14,
                padding: '12px 0',
                borderTop: i === 0 ? 'none' : '1px solid var(--border)',
              }}
            >
              <span
                aria-label={s.done ? 'done' : 'not done'}
                style={{
                  flex: '0 0 26px',
                  height: 26,
                  borderRadius: 13,
                  display: 'grid',
                  placeItems: 'center',
                  fontWeight: 700,
                  fontSize: 14,
                  color: s.done ? '#fff' : 'var(--ink-soft)',
                  background: s.done ? 'var(--success, #1f7a4d)' : 'transparent',
                  border: s.done ? 'none' : '1.5px solid var(--border-strong, #999)',
                }}
              >
                {s.done ? '✓' : i + 1}
              </span>
              <div style={{ flex: 1 }}>
                <div>
                  <strong>{s.title}</strong>{' '}
                  {s.required && !s.done && <span className="pill setup">required to switch on</span>}
                  {s.optional && <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>optional</span>}
                </div>
                <div className="hint" style={{ margin: '2px 0 0' }}>{s.why}</div>
              </div>
              <div style={{ alignSelf: 'center', whiteSpace: 'nowrap' }}>
                <Link href={s.href}>{s.done ? 'Review' : s.action} →</Link>
              </div>
            </li>
          ))}
        </ol>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>How people get in</h2>
        <ul style={{ margin: 0, paddingLeft: 18, lineHeight: 1.7 }}>
          <li>
            <strong>The owner</strong>{facts.owner_name ? ` (${facts.owner_name}, number ending ${facts.owner_phone_last4})` : ''}:
            install the app, enter <code>{facts.join_code}</code>, then their own number and the
            one-time code. The app opens on the salon&rsquo;s day view.
          </li>
          <li>
            <strong>Managers and stylists</strong>: add them under{' '}
            <Link href={`/salon/${id}/logins`}>Logins</Link>, then they sign in the same way with their
            own number.
          </li>
          <li>
            <strong>Customers</strong>: scan the salon&rsquo;s QR (or type <code>{facts.join_code}</code>)
            once the salon is switched on, then sign in with their number.
          </li>
        </ul>
      </div>
    </ConsoleShell>
  );
}
