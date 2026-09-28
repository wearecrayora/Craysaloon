import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, getGrievanceContact } from '@/server/admin-db';
import { GrievanceForm } from './form';

export const dynamic = 'force-dynamic';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const current = await getGrievanceContact(id);
  const reachable = Boolean(current?.grievance_name && (current?.grievance_email || current?.grievance_phone));

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href={`/salon/${id}/credentials`}>Credentials</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Privacy contact — {salon.display_name}</h1>
        <p className="hint">
          Under the DPDP Act the <strong>salon</strong> is the Data Fiduciary - it decides why its
          customers&rsquo; data is collected, so the law asks it, not Crayora, to answer for it.
          Every customer must be told who to contact with a question or a complaint{' '}
          <strong>at the moment consent is asked for</strong>, which in this app is before they log
          in. So this contact is published with the salon&rsquo;s name and branding when someone
          scans its QR, and <strong>the salon cannot be activated without it</strong>.
        </p>

        <div className="notice">
          <strong>Crayora is the escalation, not the first line.</strong> If a salon does not answer
          a request within 30 days it comes to us - but the name below is the one its customers see.
        </div>

        {!reachable && (
          <div className="notice">
            {salon.status === 'setup' ? (
              <>
                <strong>This salon is still in setup and has no privacy contact.</strong>{' '}
                Activation will be refused until one is saved here.
              </>
            ) : (
              <>
                <strong>This salon is live and has no privacy contact.</strong> It was activated
                before one was required, so its customers are being shown an incomplete notice -
                they are told to ask at the counter. Fix this before it is asked about.
              </>
            )}
          </div>
        )}

        <GrievanceForm salonId={id} current={current} />
      </main>
    </>
  );
}
