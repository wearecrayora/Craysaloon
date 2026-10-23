'use client';

import { useActionState, useState } from 'react';
import {
  appConfigAction,
  announceAction,
  endAnnouncementAction,
  type ActionState,
} from '@/app/actions';
import {
  APP_TILES,
  APP_SECTIONS,
  APP_SWITCHES,
  ANNOUNCEMENT_ICONS,
  TILE_LABELS,
  SECTION_LABELS,
  SWITCH_LABELS,
} from '@/lib/app-config';
import type { AppConfigRow } from '@/server/admin-db';

const empty: ActionState = {};

/**
 * An ordered list you tick and move: the ticked ones show, top to bottom, in
 * the order here. The order is posted as JSON in a hidden field.
 */
function OrderedPicker({
  name,
  all,
  labels,
  initial,
}: {
  name: string;
  all: readonly string[];
  labels: Record<string, string>;
  initial: string[];
}) {
  const known = initial.filter((x) => all.includes(x));
  const [items, setItems] = useState<string[]>([...known, ...all.filter((x) => !known.includes(x))]);
  const [on, setOn] = useState<Set<string>>(new Set(known));

  const move = (i: number, d: number) => {
    const j = i + d;
    if (j < 0 || j >= items.length) return;
    const next = [...items];
    const a = next[i]!;
    next[i] = next[j]!;
    next[j] = a;
    setItems(next);
  };

  return (
    <div>
      <input type="hidden" name={name} value={JSON.stringify(items.filter((x) => on.has(x)))} />
      <ol style={{ listStyle: 'none', padding: 0, margin: 0 }}>
        {items.map((x, i) => (
          <li
            key={x}
            style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0', borderBottom: '1px solid var(--line, #e5e5e5)' }}
          >
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, margin: 0 }}>
              <input
                type="checkbox"
                checked={on.has(x)}
                onChange={(e) => {
                  const next = new Set(on);
                  if (e.target.checked) next.add(x);
                  else next.delete(x);
                  setOn(next);
                }}
              />
              {labels[x] ?? x}
            </label>
            <button type="button" className="secondary" onClick={() => move(i, -1)} aria-label={`Move ${labels[x] ?? x} up`}>
              ↑
            </button>
            <button type="button" className="secondary" onClick={() => move(i, 1)} aria-label={`Move ${labels[x] ?? x} down`}>
              ↓
            </button>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function AppConfigForm({ salonId, config }: { salonId: string; config: AppConfigRow }) {
  const [state, save, saving] = useActionState(appConfigAction, empty);
  return (
    <form action={save} className="card">
      <input type="hidden" name="salonId" value={salonId} />

      <h2 style={{ marginTop: 0 }}>Home screen tiles</h2>
      <p className="hint" style={{ marginTop: 0 }}>
        Ticked tiles show in this order. A tile also hides itself where it cannot work - Refer &amp;
        Earn without the plan, Birthday for a child&rsquo;s account.
      </p>
      <OrderedPicker name="tiles" all={APP_TILES} labels={TILE_LABELS} initial={config.home_tiles} />

      <h2>Home screen sections</h2>
      <p className="hint" style={{ marginTop: 0 }}>Below the bill and today&rsquo;s booking, in this order.</p>
      <OrderedPicker name="sections" all={APP_SECTIONS} labels={SECTION_LABELS} initial={config.home_sections} />

      <h2>Switches</h2>
      <p className="hint" style={{ marginTop: 0 }}>
        Off hides the feature in the app. It is a display switch: the server&rsquo;s own rules for
        each feature still apply.
      </p>
      {APP_SWITCHES.map((k) => (
        <label key={k} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <input type="checkbox" name={`switch_${k}`} defaultChecked={config.switches?.[k] !== false} />
          {SWITCH_LABELS[k]}
        </label>
      ))}

      <label>
        Reason (the audit entry)
        <input name="reason" placeholder="e.g. Salon asked for bookings first" required />
      </label>

      <button type="submit" disabled={saving}>
        {saving ? 'Saving…' : 'Save the app home'}
      </button>
      {state.error && <p className="error">{state.error}</p>}
      {state.ok && <p className="ok">{state.ok}</p>}
    </form>
  );
}

/** `target` is a salon id, or 'all' for every salon (super-admins). */
export function AnnounceForm({ target }: { target: string }) {
  const [state, save, saving] = useActionState(announceAction, empty);
  return (
    <form action={save} className="card">
      <input type="hidden" name="salonId" value={target} />
      <h2 style={{ marginTop: 0 }}>{target === 'all' ? 'Announce to every salon' : 'New announcement'}</h2>
      <label>
        Title (up to 80)
        <input name="title" maxLength={80} placeholder="e.g. Closed on Diwali, 1 November" required />
      </label>
      <label>
        Details (optional, up to 280)
        <textarea name="body" maxLength={280} rows={2} placeholder="e.g. Back on the 2nd. Book ahead for the weekend." />
      </label>
      <label>
        Title in Hindi (optional)
        <input name="titleHi" maxLength={80} placeholder="जैसे: 1 नवंबर, दिवाली पर बंद" />
      </label>
      <label>
        Details in Hindi (optional)
        <textarea name="bodyHi" maxLength={280} rows={2} />
      </label>
      <label>
        Icon
        <select name="icon" defaultValue="campaign">
          {ANNOUNCEMENT_ICONS.map((i) => (
            <option key={i} value={i}>
              {i}
            </option>
          ))}
        </select>
      </label>
      <label>
        Shows from (India time; empty = now)
        <input name="startsAt" type="datetime-local" />
      </label>
      <label>
        Until (India time)
        <input name="endsAt" type="datetime-local" required />
      </label>
      <button type="submit" disabled={saving}>
        {saving ? 'Publishing…' : 'Publish announcement'}
      </button>
      {state.error && <p className="error">{state.error}</p>}
      {state.ok && <p className="ok">{state.ok}</p>}
    </form>
  );
}

export function EndAnnouncement({ id, salonId }: { id: string; salonId: string }) {
  const [state, end, ending] = useActionState(endAnnouncementAction, empty);
  return (
    <form action={end} style={{ margin: 0 }}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="salonId" value={salonId} />
      <button type="submit" className="secondary" disabled={ending}>
        {ending ? 'Ending…' : 'End now'}
      </button>
      {state.error && <span className="error"> {state.error}</span>}
    </form>
  );
}
