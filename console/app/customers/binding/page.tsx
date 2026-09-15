import Link from 'next/link';
import { requireAdmin } from '@/server/auth';
import { listTransferDestinations } from '@/server/admin-db';
import { BindingDesk } from './desk';

export const dynamic = 'force-dynamic';

/**
 * K12 - Customer binding. The support desk for RULES 4.5 and 4.6: a customer
 * who scanned the wrong salon's QR, or who genuinely wants to move salons,
 * calls Crayora. There is no way to do either from the app, on purpose.
 */
export default async function Page() {
  const admin = await requireAdmin();
  const destinations = admin.isSuper ? await listTransferDestinations() : [];

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
        <h1>Customer binding</h1>
        <p className="hint">
          Each phone number belongs to exactly one salon. Only Crayora can change that, and only
          when the customer asks: <strong>unbind</strong> when they scanned the wrong salon’s QR
          and have done nothing there yet; <strong>transfer</strong> when they want to move.
          A transfer moves the customer and <strong>nothing else</strong> - their wallet, visits,
          loyalty and packages stay with the old salon, because the money was paid into that
          salon’s own account and cannot follow them.
        </p>

        {admin.isSuper ? (
          <BindingDesk destinations={destinations} />
        ) : (
          <div className="notice">
            <strong>This desk is for a Crayora super-admin.</strong> A binding change moves a
            customer between two businesses, so an operator account cannot make one - the
            database refuses it whatever this screen shows. Pass the request to a super-admin.
          </div>
        )}
      </main>
    </>
  );
}
