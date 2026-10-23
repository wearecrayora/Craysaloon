import Link from 'next/link';

/**
 * The console's frame (Claude Design K1-K16): a sidebar in three groups -
 * every salon, the salon you are in, and the platform - over the soft glass
 * background, with the operator's name always visible. Every action in the
 * console is recorded against that name; showing it is a reminder, not a
 * decoration.
 */

type Item = { key: string; href: string; label: string; icon: keyof typeof ICONS };

const SALONS: Item[] = [
  { key: 'salons', href: '/', label: 'Salons', icon: 'store' },
  { key: 'provision', href: '/provision', label: 'New salon', icon: 'plus' },
];

const salonItems = (id: string): Item[] => [
  { key: 'overview', href: `/salon/${id}`, label: 'Set up (checklist)', icon: 'check' },
  { key: 'branding', href: `/salon/${id}/branding`, label: 'Branding studio', icon: 'palette' },
  { key: 'catalogue', href: `/salon/${id}/catalogue`, label: 'Catalogue & rules', icon: 'scissors' },
  { key: 'credentials', href: `/salon/${id}/credentials`, label: 'Credentials', icon: 'key' },
  { key: 'messaging', href: `/salon/${id}/messaging`, label: 'Messaging', icon: 'chat' },
  { key: 'privacy', href: `/salon/${id}/privacy`, label: 'Privacy contact', icon: 'shield' },
  { key: 'app', href: `/salon/${id}/app`, label: 'App home & announcements', icon: 'phone' },
  { key: 'qr', href: `/salon/${id}/qr`, label: 'QR pack', icon: 'qr' },
  { key: 'billing', href: `/salon/${id}/billing`, label: 'Billing and activation', icon: 'receipt' },
  { key: 'logins', href: `/salon/${id}/logins`, label: 'Logins (owner, staff)', icon: 'users' },
  { key: 'support', href: `/salon/${id}/support`, label: 'Support mode', icon: 'headset' },
];

const PLATFORM: Item[] = [
  { key: 'binding', href: '/customers/binding', label: 'Customer binding', icon: 'link' },
  { key: 'data-rights', href: '/data-rights', label: 'Data-rights requests', icon: 'shield' },
  { key: 'metrics', href: '/metrics', label: 'Metrics', icon: 'chart' },
  { key: 'audit', href: '/audit', label: 'Audit log', icon: 'list' },
  { key: 'operators', href: '/operators', label: 'Operators', icon: 'users' },
  { key: 'app-versions', href: '/app-versions', label: 'App versions & broadcast', icon: 'phone' },
];

export function ConsoleShell({
  admin,
  salon,
  active,
  children,
}: {
  admin: { name: string; email: string };
  salon?: { id: string; display_name: string } | null;
  active: string;
  children: React.ReactNode;
}) {
  const group = (title: string, items: Item[]) => (
    <div className="nav-group">
      <div className="nav-title">{title}</div>
      {items.map((i) => (
        <Link
          key={i.key}
          href={i.href}
          className={i.key === active ? 'nav-item on' : 'nav-item'}
          aria-current={i.key === active ? 'page' : undefined}
        >
          <Icon name={i.icon} />
          {i.label}
        </Link>
      ))}
    </div>
  );

  return (
    <div className="shell">
      <aside className="side" aria-label="Console">
        <div className="brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="brand-logo" src="/icon-64.png" alt="" width={32} height={32} />
          <span>
            <strong>Crayora</strong>
            <small>Salon console</small>
          </span>
        </div>
        <nav>
          {group('Salons', SALONS)}
          {salon && group(salon.display_name, salonItems(salon.id))}
          {group('Platform', PLATFORM)}
        </nav>
        <div className="who" title="Every action here is recorded against this name">
          <strong>{admin.name}</strong>
          <small>{admin.email}</small>
        </div>
      </aside>
      <main className="content">{children}</main>
    </div>
  );
}

const ICONS = {
  store: 'M3 9l1.5-5h15L21 9M3 9h18M3 9v11h18V9M9 20v-6h6v6',
  plus: 'M12 5v14M5 12h14',
  palette:
    'M12 3a9 9 0 100 18c1 0 1.5-.8 1.5-1.5 0-.4-.2-.8-.4-1.1-.3-.3-.4-.7-.4-1.1 0-.8.7-1.5 1.5-1.5H16a5 5 0 005-5c0-4.4-4-7.8-9-7.8zM7.5 11.5h.01M10.5 7.5h.01M15.5 8.5h.01',
  scissors: 'M6 6a3 3 0 100 .01M6 18a3 3 0 100 .01M8.5 7.5L20 18M8.5 16.5L20 6',
  key: 'M15 7a4 4 0 11-4 4l-7 7v3h3v-2h2v-2h2l1.5-1.5A4 4 0 0115 7zM16.5 8.5h.01',
  shield: 'M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6l8-3z',
  qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2',
  receipt: 'M6 3h12v18l-3-2-3 2-3-2-3 2V3zM9 8h6M9 12h6',
  headset: 'M4 14v-2a8 8 0 0116 0v2M4 14h3v6H4zM17 14h3v6h-3zM20 20a3 3 0 01-3 2h-3',
  link: 'M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7l-1 1M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7l1-1',
  chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  check: 'M4 12l5 5L20 6',
  chat: 'M4 5h16v11H9l-5 4V5zM8 9h8M8 12h5',
  list: 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
  phone: 'M7 2h10v20H7zM11 18h2',
  users: 'M9 11a4 4 0 100-8 4 4 0 000 8zM2 21v-1a6 6 0 0112 0v1M16 3.5a4 4 0 010 7.5M22 21v-1a6 6 0 00-4-5.7',
};

function Icon({ name }: { name: keyof typeof ICONS }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d={ICONS[name]} />
    </svg>
  );
}
