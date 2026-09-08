'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { browserSupabase } from '@/server/supabase-browser';

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    const { error } = await browserSupabase().auth.signInWithPassword({ email, password });
    if (error) {
      // Deliberately not distinguishing "no such account" from "wrong
      // password" - that difference tells an attacker which emails are
      // operators.
      setError('Those credentials were not accepted.');
      setBusy(false);
      return;
    }

    // A password alone is aal1. MFA is mandatory for operators (RULES 6.7), so
    // the session is not usable until it has been challenged.
    router.push('/login/mfa');
    router.refresh();
  }

  return (
    <form onSubmit={submit}>
      {error && <div className="error">{error}</div>}
      <label htmlFor="email">Email</label>
      <input
        id="email"
        type="email"
        autoComplete="username"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
      />
      <label htmlFor="password">Password</label>
      <input
        id="password"
        type="password"
        autoComplete="current-password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      <div className="actions">
        <button disabled={busy}>{busy ? 'Signing in…' : 'Continue'}</button>
      </div>
    </form>
  );
}
