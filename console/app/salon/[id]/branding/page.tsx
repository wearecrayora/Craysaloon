import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getBranding, getSalon } from '@/server/admin-db';
import { Studio } from './studio';

export const dynamic = 'force-dynamic';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const branding = await getBranding(id);

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
      <main className="wrap" style={{ maxWidth: 1100 }}>
        <h1>Branding — {salon.display_name}</h1>
        <p className="hint">
          The operator picks four colours; everything else is computed at publish. Publishing
          bumps the version, which is what pushes a re-theme to every installed copy.
          {branding ? ` Currently at version ${branding.version}.` : ' Never published.'}
        </p>
        <Studio
          salonId={id}
          displayName={salon.display_name}
          initial={branding?.tokens ?? null}
        />
      </main>
    </>
  );
}
