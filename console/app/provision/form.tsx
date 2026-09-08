'use client';

import { useActionState } from 'react';
import Link from 'next/link';
import { provisionAction, type ActionState } from '../actions';

const empty: ActionState = {};

export function ProvisionForm() {
  const [state, action, pending] = useActionState(provisionAction, empty);

  if (state.joinCode) {
    return (
      <div className="card">
        <h2>{state.ok}</h2>
        <p className="hint">
          The join code below is what the customer types, and what the QR encodes. It avoids 0, 1,
          I, L and O so it survives being read off a printed sticker.
        </p>
        <p style={{ fontFamily: 'ui-monospace, monospace', fontSize: 28, letterSpacing: '.06em' }}>
          {state.joinCode}
        </p>
        <div className="notice">
          Not yet built: the printable QR pack, the owner’s SMS invite, branding, and the
          catalogue. The salon exists and is isolated; it just has nothing in it yet.
        </div>
        <div className="actions">
          <Link href="/">
            <button type="button" className="secondary">Back to salons</button>
          </Link>
        </div>
      </div>
    );
  }

  return (
    <form action={action} className="card">
      {state.error && <div className="error">{state.error}</div>}

      <h2>Identity</h2>
      <div className="row">
        <div>
          <label htmlFor="legalName">Legal name</label>
          <input id="legalName" name="legalName" required placeholder="Sharma Hair & Beauty Pvt Ltd" />
        </div>
        <div>
          <label htmlFor="displayName">Display name</label>
          <input id="displayName" name="displayName" required placeholder="Sharma Salon" />
        </div>
      </div>
      <p className="hint">
        The display name appears in every message the customer receives and in the app itself.
      </p>

      <div className="row">
        <div>
          <label htmlFor="phone">Salon phone</label>
          <input id="phone" name="phone" placeholder="Optional" />
        </div>
        <div>
          <label htmlFor="email">Email</label>
          <input id="email" name="email" type="email" placeholder="Optional" />
        </div>
      </div>
      <div className="row">
        <div>
          <label htmlFor="gstNumber">GST number</label>
          <input id="gstNumber" name="gstNumber" placeholder="Optional" />
        </div>
        <div>
          <label htmlFor="timezone">Timezone</label>
          <input id="timezone" name="timezone" defaultValue="Asia/Kolkata" />
        </div>
      </div>
      <label htmlFor="address">Address</label>
      <input id="address" name="address" placeholder="Optional" />

      <h2 style={{ marginTop: 28 }}>Owner</h2>
      <div className="row">
        <div>
          <label htmlFor="ownerName">Owner name</label>
          <input id="ownerName" name="ownerName" required />
        </div>
        <div>
          <label htmlFor="ownerPhone">Owner mobile</label>
          <input id="ownerPhone" name="ownerPhone" required placeholder="98765 43210" />
        </div>
      </div>
      <p className="hint">
        The owner signs into the same Android app with this number. There is no separate owner app
        and no self-signup.
      </p>

      <h2 style={{ marginTop: 28 }}>Commercials</h2>
      <div className="row">
        <div>
          <label htmlFor="plan">Plan</label>
          <input id="plan" name="plan" required defaultValue="starter" />
        </div>
        <div>
          <label htmlFor="setupFeeRupees">Setup fee (₹)</label>
          <input id="setupFeeRupees" name="setupFeeRupees" type="number" min={0} defaultValue={15000} />
        </div>
      </div>
      <p className="hint">
        Recorded as unpaid. The fee is collected offline — cash or bank transfer — and marked paid
        separately, with a reference.
      </p>

      <div className="actions">
        <button disabled={pending}>{pending ? 'Provisioning…' : 'Provision salon'}</button>
        <Link href="/" style={{ fontSize: 14 }}>Cancel</Link>
      </div>
    </form>
  );
}
