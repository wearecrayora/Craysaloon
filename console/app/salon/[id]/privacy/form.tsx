'use client';

import { useActionState } from 'react';
import { grievanceAction, type ActionState } from '@/app/actions';

const empty: ActionState = {};

export function GrievanceForm({
  salonId,
  current,
}: {
  salonId: string;
  current: { grievance_name: string | null; grievance_email: string | null; grievance_phone: string | null } | null;
}) {
  const [state, save, saving] = useActionState(grievanceAction, empty);

  return (
    <form action={save} className="card">
      <input type="hidden" name="salonId" value={salonId} />

      <label>
        Name of the person
        <input
          name="name"
          defaultValue={current?.grievance_name ?? ''}
          placeholder="e.g. Sunita Rao"
          required
        />
      </label>
      <p className="hint" style={{ marginTop: 0 }}>
        A person, not a department. A customer who wants their data deleted needs someone to ask.
      </p>

      <label>
        Email
        <input
          name="email"
          type="email"
          defaultValue={current?.grievance_email ?? ''}
          placeholder="privacy@salon.example"
        />
      </label>

      <label>
        Phone
        <input
          name="phone"
          defaultValue={current?.grievance_phone ?? ''}
          placeholder="+91 98XXXXXXXX"
        />
      </label>
      <p className="hint" style={{ marginTop: 0 }}>
        At least one of the two. Both is better - this is the address a complaint arrives at, and
        the salon has 30 days to answer.
      </p>

      <button type="submit" disabled={saving}>
        {saving ? 'Saving…' : 'Save privacy contact'}
      </button>

      {state.error && <p className="error">{state.error}</p>}
      {state.ok && <p className="ok">{state.ok}</p>}
    </form>
  );
}
