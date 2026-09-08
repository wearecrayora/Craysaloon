import { LoginForm } from './form';

export const dynamic = 'force-dynamic';

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ denied?: string }>;
}) {
  const { denied } = await searchParams;
  return (
    <main className="wrap" style={{ maxWidth: 420, paddingTop: 80 }}>
      <h1>Crayora Console</h1>
      <p className="hint">
        Operator access only. Every action you take here is recorded against your name.
      </p>
      {denied && (
        <div className="error">
          That account is signed in but is not an active Crayora operator.
        </div>
      )}
      <div className="card">
        <LoginForm />
      </div>
    </main>
  );
}
