import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/server/auth';
import {
  getRules,
  getSalon,
  listAddOns,
  listServiceAddOns,
  listServices,
  listStaff,
} from '@/server/admin-db';
import { AddOnLinks } from './addon-links';
import { AddOns, RulesForm, Services, Staff } from './editors';
import { ConsoleShell } from '@/app/shell';

export const dynamic = 'force-dynamic';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();
  const salon = await getSalon(id);
  if (!salon) notFound();

  const [services, addOns, staff, rules, links] = await Promise.all([
    listServices(id),
    listAddOns(id),
    listStaff(id),
    getRules(id),
    listServiceAddOns(id),
  ]);

  return (
    <>

      <ConsoleShell admin={admin} salon={salon} active="catalogue">
        <h1>Catalogue &amp; rules — {salon.display_name}</h1>
        <p className="hint">
          Everything here is editable afterwards, by design — provisioning does not demand a
          finished catalogue. Prices are entered in rupees and stored in paise.
        </p>

        <Services salonId={id} rows={services} />
        <AddOns salonId={id} rows={addOns} />
        <AddOnLinks salonId={id} services={services} addOns={addOns} links={links} />
        <Staff salonId={id} rows={staff} />
        <RulesForm salonId={id} rules={rules} />
      </ConsoleShell>
    </>
  );
}
