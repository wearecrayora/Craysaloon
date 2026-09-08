'use client';

import { createBrowserClient } from '@supabase/ssr';

/**
 * The browser half. Carries the PUBLISHABLE key only - never the secret key,
 * and never a database URL (RULES 6.6). Everything privileged happens in a
 * server action.
 */
export function browserSupabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    throw new Error('Supabase public environment variables are not configured.');
  }
  return createBrowserClient(url, key);
}
