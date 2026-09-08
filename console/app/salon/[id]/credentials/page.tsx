import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, listIntegrations } from '@/server/admin-db';
import { CredentialForm } from './form';

export const dynamic = 'force-dynamic';

const LABEL: Record<string, { name: string; what: string }> = {
  razorpay: {
    name: 'Razorpay',
    what: "The salon's OWN account. Customer money settles there, never to Crayora.",
  },
  message_central: {
    name: 'Message Central',
    what: 'Sends the OTP and SMS from the salon’s own account. Top-up-and-send; no DLT registration.',
  },
  whatsapp: {
    name: 'WhatsApp Business',
    what: 'Templates are authored in the Message Central dashboard and approved by Meta. Pending approval never blocks activation.',
  },
  rcs: {
    name: 'RCS',
    what: 'Verified agent, carrier-dependent. Tried above WhatsApp when the handset supports it.',
  },
};

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();
  const rows = await listIntegrations(id);

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href={`/salon/${id}/branding`}>Branding</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Credentials — {salon.display_name}</h1>
        <p className="hint">
          Every message and every rupee moves through the salon’s own provider accounts. These are
          stored encrypted and are <strong>write-only</strong>: there is no screen, endpoint or
          database function that reads one back. Rotation replaces; it never reveals.
        </p>

        <div className="notice">
          <strong>Test connection is not built yet.</strong> Verifying a credential means using it,
          and decryption is supposed to happen inside an Edge Function at the moment of use — those
          arrive with M3. Until then <code>status</code> stays <code>untested</code> after a save.
          Nothing here pretends otherwise.
        </div>

        {rows.map((row) => (
          <CredentialForm
            key={row.provider}
            salonId={id}
            row={row}
            label={LABEL[row.provider]?.name ?? row.provider}
            blurb={LABEL[row.provider]?.what ?? ''}
          />
        ))}
      </main>
    </>
  );
}
