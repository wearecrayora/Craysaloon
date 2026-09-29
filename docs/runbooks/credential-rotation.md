# Credential rotation

## When

A key appeared anywhere it should not (a chat, a screenshot, a commit, a log), a person with
access left, or **launch day** - every development credential is rotated before the first real
salon.

## Per-salon provider credentials (Message Central, Razorpay, WhatsApp, RCS)

Console → salon → **Credentials** → *Replace*, then *Test connection*. Write-only: nothing can be
read back, so there is nothing to compare - replace and test. For Razorpay also rotate the
**webhook secret** in the salon's Razorpay dashboard and enter the new one here.

## Platform credentials

| Credential | Rotate in | Then update |
|---|---|---|
| Supabase secret key (`sb_secret_…`) | Supabase → Project Settings → API keys | Vercel env, GitHub secret `CRAY_SECRET_KEY`, Edge Function secrets, `.env` |
| Database password | Supabase → Database | `.env` `DATABASE_URL`, Vercel `ADMIN_DATABASE_URL`, GitHub `RESTORE_DRILL_DB_URL` |
| FCM service account | Firebase → Service accounts → new key; delete the old | `supabase secrets set FCM_SERVICE_ACCOUNT=…` (from a file outside the repo) |
| Crayora's Message Central account | Message Central dashboard | Edge Function secrets |
| Sentry DSN | Sentry → Client keys | app build config, Edge Function secrets |
| Cloudflare R2 token | Cloudflare → R2 → API tokens | Vercel env |

The publishable key (`sb_publishable_…`) ships in the app. Rotating it needs a new app build.

## The phone-hash pepper - do NOT rotate

Every stored phone hash is computed with it. A new pepper makes every existing customer and staff
member unable to log in. It is not a credential to rotate; it is data to protect: keep it offline
in two places, and see [restore.md](restore.md).

## Never

- Paste a secret into chat, a ticket or a terminal that is being recorded.
- Commit one. `scripts/secret-scan.sh` runs in CI; do not work around it.
