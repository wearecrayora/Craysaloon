import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getSalon, getWebhookToken, listIntegrations } from '@/server/admin-db';
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
  const webhookToken = await getWebhookToken(id);
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const webhookUrl = webhookToken
    ? `${supabaseUrl}/functions/v1/rzp-webhook/${webhookToken}`
    : null;

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
          database function that reads one back. Rotation replaces; it never reveals.{' '}
          <strong>Only Crayora can set or change these.</strong> The salon owner cannot see or
          change them anywhere in the app - the database refuses every path, and CI fails if one
          is ever added.
        </p>

        <div className="notice">
          <strong>Message Central is checked on save:</strong> the pair is verified with Message
          Central before it is stored - no SMS is sent - and shows <code>ok</code> if it passes.{' '}
          <strong>Razorpay, WhatsApp and RCS are not tested yet</strong>: they stay{' '}
          <code>untested</code> after a save until their Test connection is built. Nothing here
          pretends otherwise.
        </div>

        {webhookUrl && (
          <div className="card">
            <h2>This salon&rsquo;s Razorpay webhook URL</h2>
            <p className="hint" style={{ marginTop: 0 }}>
              Paste this into the salon&rsquo;s Razorpay dashboard (Settings &rarr; Webhooks),
              with the <code>payment.captured</code> event and the webhook secret you entered
              below. <strong>The URL is per salon</strong>: it is how a notification is tied to
              this salon without trusting anything in its body.
            </p>
            <p
              style={{
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                fontSize: 13,
                wordBreak: 'break-all',
                background: 'var(--bg-soft)',
                padding: 12,
                borderRadius: 6,
                margin: 0,
              }}
            >
              {webhookUrl}
            </p>
          </div>
        )}

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
