import { MfaFlow } from './flow';

export const dynamic = 'force-dynamic';

export default function Page() {
  return (
    <main className="wrap" style={{ maxWidth: 420, paddingTop: 80 }}>
      <h1>Two-factor</h1>
      <p className="hint">
        Operator accounts require a second factor. A password alone leaves the session at
        assurance level 1, and the console refuses to act at that level — so this is not a
        setting that can be skipped.
      </p>
      <div className="card">
        <MfaFlow />
      </div>
    </main>
  );
}
