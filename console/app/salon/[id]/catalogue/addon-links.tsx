'use client';

import { useActionState } from 'react';
import type { AddOnRow, ServiceRow } from '@/server/admin-db';
import { setServiceAddOnAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

/**
 * Which add-ons are offered with which service.
 *
 * Without this, no add-on is offered with anything - and create_booking
 * REFUSES an add-on that is not linked to the service being booked. Add-ons
 * could be created here and never sold. The orphan check found it: the
 * function behind it had no caller anywhere.
 *
 * Offering is not the same as selecting: an add-on offered here still starts
 * UNTICKED for the customer, every time (RULES 9).
 */
export function AddOnLinks({
  salonId,
  services,
  addOns,
  links,
}: {
  salonId: string;
  services: ServiceRow[];
  addOns: AddOnRow[];
  links: { service_id: string; add_on_id: string }[];
}) {
  const liveServices = services.filter((s) => s.active);
  const liveAddOns = addOns.filter((a) => a.active);
  const linked = new Set(links.map((l) => `${l.service_id}:${l.add_on_id}`));

  return (
    <section className="card">
      <h2>Which add-ons go with which service</h2>
      <p className="hint" style={{ marginTop: 0 }}>
        A customer booking a service is offered only the add-ons ticked here - and they always
        start <strong>unticked</strong> for the customer. An add-on offered with nothing can never
        be sold.
      </p>

      {liveServices.length === 0 || liveAddOns.length === 0 ? (
        <p className="hint">Add at least one active service and one active add-on first.</p>
      ) : (
        liveServices.map((service) => (
          <div key={service.id} style={{ marginBottom: 16 }}>
            <strong>{service.name}</strong>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 6 }}>
              {liveAddOns.map((addOn) => (
                <LinkToggle
                  key={addOn.id}
                  salonId={salonId}
                  serviceId={service.id}
                  addOn={addOn}
                  initiallyLinked={linked.has(`${service.id}:${addOn.id}`)}
                />
              ))}
            </div>
          </div>
        ))
      )}
    </section>
  );
}

function LinkToggle({
  salonId,
  serviceId,
  addOn,
  initiallyLinked,
}: {
  salonId: string;
  serviceId: string;
  addOn: AddOnRow;
  initiallyLinked: boolean;
}) {
  const [state, save, saving] = useActionState(setServiceAddOnAction, empty);
  // What the server last confirmed, falling back to the page's copy.
  const isLinked = state.ok ? state.ok.startsWith('Offered') : initiallyLinked;

  return (
    <form action={save} style={{ margin: 0 }}>
      <input type="hidden" name="salonId" value={salonId} />
      <input type="hidden" name="serviceId" value={serviceId} />
      <input type="hidden" name="addOnId" value={addOn.id} />
      <input type="hidden" name="linked" value={String(!isLinked)} />
      <label style={{ display: 'flex', gap: 6, alignItems: 'center', cursor: 'pointer' }}>
        <input
          type="checkbox"
          checked={isLinked}
          disabled={saving}
          onChange={(e) => e.currentTarget.form?.requestSubmit()}
          style={{ width: 'auto' }}
        />
        <span>{addOn.name}</span>
      </label>
      {state.error && <span className="error">{state.error}</span>}
    </form>
  );
}
