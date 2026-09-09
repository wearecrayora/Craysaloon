import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import { getRules, getSalon, listAddOns, listServices, listStaff } from '@/server/admin-db';
import { AddOns, RulesForm, Services, Staff } from './editors';

export const dynamic = 'force-dynamic';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();

  const [services, addOns, staff, rules] = await Promise.all([
    listServices(id),
    listAddOns(id),
    listStaff(id),
    getRules(id),
  ]);

  return (
    <>
      <header className="bar">
        <div className="wrap">
          <strong>Crayora Console</strong>
          <Link href="/">Salons</Link>
          <Link href={`/salon/${id}/branding`}>Branding</Link>
          <Link href={`/salon/${id}/credentials`}>Credentials</Link>
          <span className="who">
            {admin.name} · {admin.email}
          </span>
        </div>
      </header>

      <main className="wrap">
        <h1>Catalogue &amp; rules — {salon.display_name}</h1>
        <p className="hint">
          Everything here is editable afterwards, by design — provisioning does not demand a
          finished catalogue. Prices are entered in rupees and stored in paise.
        </p>

        <Services salonId={id} rows={services} />
        <AddOns salonId={id} rows={addOns} />
        <Staff salonId={id} rows={staff} />
        <RulesForm salonId={id} rules={rules} />
      </main>
    </>
  );
}
