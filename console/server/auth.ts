import 'server-only';
import { cookies } from 'next/headers';
import { createServerClient } from '@supabase/ssr';
import { redirect } from 'next/navigation';
import { findActivePlatformAdmin } from './admin-db';

/**
 * Console authentication. RULES 6.7: admin accounts require MFA and never
 * carry a salon_id claim.
 *
 * Three things must all hold before any admin action runs:
 *
 *   1. a valid Supabase session,
 *   2. MFA actually satisfied for THIS session (assurance level aal2), and
 *   3. an active row in platform_admins.
 *
 * (2) is the one that is easy to get wrong. Enrolling a factor is not the same
 * as having used it: a session that has never been challenged sits at aal1 even
 * though the account has TOTP configured. Checking enrolment instead of
 * assurance level would make MFA decorative.
 */

export async function supabaseServer() {
  const store = await cookies();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    throw new Error(
      'NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY are not set. ' +
        'See console/.env.local.example.',
    );
  }
  return createServerClient(url, key, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          for (const { name, value, options } of list) store.set(name, value, options);
        } catch {
          // Called from a Server Component, where cookies are read-only. The
          // middleware refreshes the session, so this is safe to ignore.
        }
      },
    },
  });
}

export type Admin = {
  id: string;
  name: string;
  email: string;
  isSuper: boolean;
};

/**
 * Returns the acting admin, or redirects. Every server action and privileged
 * page calls this FIRST - the actor id it returns is what gets written into
 * audit_log, so an unattributable action is impossible by construction.
 */
export async function requireAdmin(): Promise<Admin> {
  const supabase = await supabaseServer();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.currentLevel !== 'aal2') {
    // Enrolled but not challenged, or not enrolled at all. Both land on the
    // same screen; that screen decides which.
    redirect('/login/mfa');
  }

  const admin = await findActivePlatformAdmin(user.id);
  if (!admin) {
    // A real Supabase user who is not a Crayora operator. Not an error to
    // debug - just not an admin.
    redirect('/login?denied=1');
  }

  return {
    id: admin.id,
    name: admin.name,
    email: admin.email,
    isSuper: admin.is_super,
  };
}
