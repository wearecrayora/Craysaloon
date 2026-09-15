import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon } from '@/server/admin-db';
import { latestUnder, signedUrl } from '@/server/r2';
import { QrPackForm } from './form';

export const dynamic = 'force-dynamic';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();

  // The newest pack, if any. Signed fresh on every page load: a link embedded
  // in the page must not outlive the page by much.
  const latestKey = await latestUnder(`salons/${id}/qr-pack/`);
  const latestUrl = latestKey ? await signedUrl(latestKey, 600) : null;

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href={`/salon/${id}/branding`}>Branding</Link>
          <Link href={`/salon/${id}/catalogue`}>Catalogue</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>QR pack — {salon.display_name}</h1>
        <p className="hint">
          Three printable pieces in one PDF: a counter card (A5), a mirror sticker (100 mm), and a
          reception poster (A4). Every QR is checked to decode to this salon’s join link, and the
          code is printed large beneath it for anyone whose camera will not focus.
        </p>

        {salon.status !== 'active' && (
          <div className="notice">
            This salon is in <strong>{salon.status}</strong>. Its code will not resolve until it is
            activated, so a pack printed now is safe to hand over early — scanning it does nothing
            yet.
          </div>
        )}

        <div className="card">
          {latestKey ? (
            <p style={{ margin: 0 }}>
              Latest pack:{' '}
              <a href={latestUrl ?? '#'}>download</a>{' '}
              <span style={{ color: 'var(--ink-soft)', fontSize: 13 }}>
                ({latestKey.split('/').pop()}) · link valid for 10 minutes
              </span>
            </p>
          ) : (
            <p className="hint" style={{ margin: 0 }}>
              No pack has been generated for this salon yet.
            </p>
          )}
        </div>

        <QrPackForm salonId={id} regenerate={!!latestKey} />
      </main>
    </>
  );
}
