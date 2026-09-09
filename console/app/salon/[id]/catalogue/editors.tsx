'use client';

import { useActionState, useState } from 'react';
import type { AddOnRow, SalonRules, ServiceRow, StaffRow } from '@/server/admin-db';
import {
  setRulesAction,
  upsertAddOnAction,
  upsertServiceAction,
  upsertStaffAction,
  type ActionState,
} from '@/app/actions';

const empty: ActionState = {};

const rupees = (paise: string) =>
  '₹' + (Number(paise) / 100).toLocaleString('en-IN', { maximumFractionDigits: 2 });

function Feedback({ state }: { state: ActionState }) {
  if (state.error) return <div className="error">{state.error}</div>;
  if (state.ok) return <div className="notice">{state.ok}</div>;
  return null;
}

/** Shared shell: a list of existing rows, and one form that adds or edits. */
function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="card">
      <h2>{title}</h2>
      {hint && (
        <p className="hint" style={{ marginTop: 0 }}>
          {hint}
        </p>
      )}
      {children}
    </div>
  );
}

export function Services({ salonId, rows }: { salonId: string; rows: ServiceRow[] }) {
  const [state, save, saving] = useActionState(upsertServiceAction, empty);
  const [editing, setEditing] = useState<ServiceRow | null>(null);

  return (
    <Section
      title="Services"
      hint="Changing a price here does not rewrite history: a booking snapshots what it cost at the time, so past revenue and every dashboard number stay as they were."
    >
      <Feedback state={state} />

      {rows.length > 0 && (
        <table style={{ marginBottom: 16 }}>
          <thead>
            <tr>
              <th>Name</th>
              <th>Price</th>
              <th>Duration</th>
              <th>Repeat cycle</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} style={{ opacity: r.active ? 1 : 0.55 }}>
                <td>
                  {r.name}
                  {!r.active && <span style={{ color: 'var(--ink-soft)' }}> · inactive</span>}
                  {r.category && (
                    <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}> · {r.category}</span>
                  )}
                </td>
                <td style={{ fontVariantNumeric: 'tabular-nums' }}>{rupees(r.price_paise)}</td>
                <td>{r.duration_minutes} min</td>
                <td>{r.repeat_cycle_days ? `${r.repeat_cycle_days} days` : '—'}</td>
                <td style={{ textAlign: 'right' }}>
                  <button type="button" className="secondary" onClick={() => setEditing(r)}>
                    Edit
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <form action={save} key={editing?.id ?? 'new'}>
        <input type="hidden" name="salonId" value={salonId} />
        <input type="hidden" name="id" value={editing?.id ?? ''} />
        <div className="row">
          <div>
            <label htmlFor="svc-name">Name</label>
            <input id="svc-name" name="name" defaultValue={editing?.name ?? ''} required />
          </div>
          <div>
            <label htmlFor="svc-cat">Category</label>
            <input id="svc-cat" name="category" defaultValue={editing?.category ?? ''} />
          </div>
        </div>
        <div className="row">
          <div>
            <label htmlFor="svc-price">Price (₹)</label>
            <input
              id="svc-price"
              name="priceRupees"
              type="number"
              min={0}
              step="0.01"
              defaultValue={editing ? Number(editing.price_paise) / 100 : ''}
              required
            />
          </div>
          <div>
            <label htmlFor="svc-dur">Duration (minutes)</label>
            <input
              id="svc-dur"
              name="durationMinutes"
              type="number"
              min={5}
              step={5}
              defaultValue={editing?.duration_minutes ?? 30}
              required
            />
          </div>
        </div>
        <div className="row">
          <div>
            <label htmlFor="svc-cycle">Repeat cycle (days)</label>
            <input
              id="svc-cycle"
              name="repeatCycleDays"
              type="number"
              min={1}
              defaultValue={editing?.repeat_cycle_days ?? ''}
              placeholder="Blank if it does not repeat"
            />
          </div>
          <div>
            <label htmlFor="svc-active">Active</label>
            <input
              id="svc-active"
              name="active"
              type="checkbox"
              defaultChecked={editing ? editing.active : true}
              style={{ width: 'auto' }}
            />
          </div>
        </div>
        <div className="actions">
          <button disabled={saving}>
            {saving ? 'Saving…' : editing ? 'Save changes' : 'Add service'}
          </button>
          {editing && (
            <button type="button" className="secondary" onClick={() => setEditing(null)}>
              Cancel
            </button>
          )}
        </div>
      </form>
    </Section>
  );
}

export function AddOns({ salonId, rows }: { salonId: string; rows: AddOnRow[] }) {
  const [state, save, saving] = useActionState(upsertAddOnAction, empty);
  const [editing, setEditing] = useState<AddOnRow | null>(null);

  return (
    <Section
      title="Add-ons"
      hint="Offered alongside a service. They are never pre-selected anywhere in the app — an add-on the customer did not choose is a charge they did not agree to."
    >
      <Feedback state={state} />

      {rows.length > 0 && (
        <table style={{ marginBottom: 16 }}>
          <thead>
            <tr>
              <th>Name</th>
              <th>Price</th>
              <th>Extra time</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} style={{ opacity: r.active ? 1 : 0.55 }}>
                <td>
                  {r.name}
                  {!r.active && <span style={{ color: 'var(--ink-soft)' }}> · inactive</span>}
                </td>
                <td style={{ fontVariantNumeric: 'tabular-nums' }}>{rupees(r.price_paise)}</td>
                <td>{r.extra_duration_minutes} min</td>
                <td style={{ textAlign: 'right' }}>
                  <button type="button" className="secondary" onClick={() => setEditing(r)}>
                    Edit
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <form action={save} key={editing?.id ?? 'new'}>
        <input type="hidden" name="salonId" value={salonId} />
        <input type="hidden" name="id" value={editing?.id ?? ''} />
        <div className="row">
          <div>
            <label htmlFor="ao-name">Name</label>
            <input id="ao-name" name="name" defaultValue={editing?.name ?? ''} required />
          </div>
          <div>
            <label htmlFor="ao-price">Price (₹)</label>
            <input
              id="ao-price"
              name="priceRupees"
              type="number"
              min={0}
              step="0.01"
              defaultValue={editing ? Number(editing.price_paise) / 100 : ''}
              required
            />
          </div>
        </div>
        <div className="row">
          <div>
            <label htmlFor="ao-extra">Extra time (minutes)</label>
            <input
              id="ao-extra"
              name="extraDurationMinutes"
              type="number"
              min={0}
              step={5}
              defaultValue={editing?.extra_duration_minutes ?? 0}
            />
          </div>
          <div>
            <label htmlFor="ao-active">Active</label>
            <input
              id="ao-active"
              name="active"
              type="checkbox"
              defaultChecked={editing ? editing.active : true}
              style={{ width: 'auto' }}
            />
          </div>
        </div>
        <div className="actions">
          <button disabled={saving}>
            {saving ? 'Saving…' : editing ? 'Save changes' : 'Add add-on'}
          </button>
          {editing && (
            <button type="button" className="secondary" onClick={() => setEditing(null)}>
              Cancel
            </button>
          )}
        </div>
      </form>
    </Section>
  );
}

export function Staff({ salonId, rows }: { salonId: string; rows: StaffRow[] }) {
  const [state, save, saving] = useActionState(upsertStaffAction, empty);
  const [editing, setEditing] = useState<StaffRow | null>(null);

  return (
    <Section
      title="Staff"
      hint="Working hours and time off are set per person once the salon is running; a staff row here is what a booking can be assigned to."
    >
      <Feedback state={state} />

      {rows.length > 0 && (
        <table style={{ marginBottom: 16 }}>
          <thead>
            <tr>
              <th>Name</th>
              <th>Skills</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} style={{ opacity: r.active ? 1 : 0.55 }}>
                <td>
                  {r.name}
                  {!r.active && <span style={{ color: 'var(--ink-soft)' }}> · inactive</span>}
                </td>
                <td>{r.skills?.length ? r.skills.join(', ') : '—'}</td>
                <td style={{ textAlign: 'right' }}>
                  <button type="button" className="secondary" onClick={() => setEditing(r)}>
                    Edit
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <form action={save} key={editing?.id ?? 'new'}>
        <input type="hidden" name="salonId" value={salonId} />
        <input type="hidden" name="id" value={editing?.id ?? ''} />
        <div className="row">
          <div>
            <label htmlFor="st-name">Name</label>
            <input id="st-name" name="name" defaultValue={editing?.name ?? ''} required />
          </div>
          <div>
            <label htmlFor="st-skills">Skills (comma separated)</label>
            <input
              id="st-skills"
              name="skills"
              defaultValue={editing?.skills?.join(', ') ?? ''}
              placeholder="colour, keratin"
            />
          </div>
        </div>
        <label htmlFor="st-active">Active</label>
        <input
          id="st-active"
          name="active"
          type="checkbox"
          defaultChecked={editing ? editing.active : true}
          style={{ width: 'auto' }}
        />
        <div className="actions">
          <button disabled={saving}>
            {saving ? 'Saving…' : editing ? 'Save changes' : 'Add staff'}
          </button>
          {editing && (
            <button type="button" className="secondary" onClick={() => setEditing(null)}>
              Cancel
            </button>
          )}
        </div>
      </form>
    </Section>
  );
}

export function RulesForm({ salonId, rules }: { salonId: string; rules: SalonRules | null }) {
  const [state, save, saving] = useActionState(setRulesAction, empty);

  const wallet = (rules?.wallet_rule ?? {}) as { topup_paise?: number; bonus_paise?: number };

  return (
    <Section title="Rules">
      <Feedback state={state} />

      <form action={save}>
        <input type="hidden" name="salonId" value={salonId} />

        <div className="row">
          <div>
            <label htmlFor="topup">Wallet top-up threshold (₹)</label>
            <input
              id="topup"
              name="walletTopupRupees"
              type="number"
              min={1}
              step="1"
              defaultValue={wallet.topup_paise ? wallet.topup_paise / 100 : 500}
              required
            />
          </div>
          <div>
            <label htmlFor="bonus">Bonus credited (₹)</label>
            <input
              id="bonus"
              name="walletBonusRupees"
              type="number"
              min={0}
              step="1"
              defaultValue={wallet.bonus_paise ? wallet.bonus_paise / 100 : 50}
              required
            />
          </div>
        </div>

        <div className="notice">
          <strong>Bonus expiry is not set here.</strong> It belongs to the owner, in the app, and
          is captured onto each lot at the moment it is issued — so changing it later can never
          reach back and expire credit a customer was already given. Paid credit never expires at
          all; there is no field for it anywhere. The database refuses a rules payload that so
          much as mentions expiry.
        </div>

        <div className="row">
          <div>
            <label htmlFor="cycle">Default reminder cycle (days)</label>
            <input
              id="cycle"
              name="reminderCycleDays"
              type="number"
              min={1}
              defaultValue={rules?.default_reminder_cycle_days ?? 30}
              required
            />
          </div>
          <div>
            <label htmlFor="cancel">Cancellation policy</label>
            <input
              id="cancel"
              name="cancellationPolicy"
              defaultValue={rules?.cancellation_policy ?? ''}
              placeholder="Free until 4 hours before"
            />
          </div>
        </div>

        <div className="actions">
          <button disabled={saving}>{saving ? 'Saving…' : 'Save rules'}</button>
        </div>
      </form>
    </Section>
  );
}
