import { LoginForm } from './form';

export const dynamic = 'force-dynamic';

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ denied?: string }>;
}) {
  const { denied } = await searchParams;
  return (
    <main className="wrap" style={{ maxWidth: 440, paddingTop: 96 }}>
      <div className="card login-card">
        <div className="login-head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon-64.png" alt="" width={52} height={52} />
          <div>
            <h1>Crayora Console</h1>
            <p>Set up and run every Cray Salon</p>
          </div>
        </div>
        {denied && (
          <div className="error">
            That account is signed in but is not an active Crayora operator.
          </div>
        )}
        <LoginForm />
        <p className="hint" style={{ marginBottom: 0 }}>
          Operator access only. Every action you take here is recorded against your name.
        </p>
      </div>
    </main>
  );
}
