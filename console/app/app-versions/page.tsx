import { redirect } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { ConsoleShell } from '@/app/shell';
import { AnnounceForm } from '@/app/salon/[id]/app/forms';
import { VersionsForm } from './form';

export const dynamic = 'force-dynamic';

/**
 * Which app builds may still run, for every salon at once, and announcements
 * to every salon (0119). A super-admin's page: a forced update stops every
 * older app until it is updated.
 */
export default async function Page() {
  const admin = await requireAdmin();
  if (!admin.isSuper) redirect('/');

  return (
    <ConsoleShell admin={admin} active="app-versions">
      <h1>App versions &amp; broadcast</h1>
      <p className="hint">
        The build number is the <code>+N</code> in the app&rsquo;s version (pubspec{' '}
        <code>version: 1.0.0+N</code>). <strong>Lowest allowed</strong>: an app below it shows only
        &ldquo;Please update&rdquo; and does nothing else - use it for a broken release. <strong>Newest
        </strong>: an app below it shows a dismissible &ldquo;A new version is ready&rdquo;. The update
        link is where Update goes - the Play Store page once the app is listed; until then, wherever
        the APK is shared.
      </p>
      <VersionsForm />
      <AnnounceForm target="all" />
    </ConsoleShell>
  );
}
