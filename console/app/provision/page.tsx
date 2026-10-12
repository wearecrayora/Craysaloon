import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { ProvisionForm } from './form';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const admin = await requireAdmin();
  return (
    <>
      <ConsoleShell admin={admin} active="provision">
        <h1>Provision a salon</h1>
        <p className="hint">
          One transaction. If anything fails, nothing is created — no salon, no join code, no
          owner. The salon is created in <strong>setup</strong>; switching it on is a separate,
          deliberate action.
        </p>
        <ProvisionForm />
      </ConsoleShell>
    </>
  );
}
