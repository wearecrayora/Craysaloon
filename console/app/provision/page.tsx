import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { ProvisionForm } from './form';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const admin = await requireAdmin();
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
      <main className="wrap">
        <h1>Provision a salon</h1>
        <p className="hint">
          One transaction. If anything fails, nothing is created — no salon, no join code, no
          owner. The salon is created in <strong>setup</strong>; switching it on is a separate,
          deliberate action.
        </p>
        <ProvisionForm />
      </main>
    </>
  );
}
