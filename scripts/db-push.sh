#!/usr/bin/env bash
# Apply migrations to the HOSTED dev project (PHASES.md option A).
# There is no local stack; `db reset` is deliberately not used here because it
# would wipe shared data.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env - copy .env.example and fill it."; exit 1; }
set -a; . ./.env; set +a
: "${SUPABASE_PROJECT_REF:?}"
echo "Pushing migrations to ${SUPABASE_PROJECT_REF} ..."
npx -y supabase@latest link --project-ref "$SUPABASE_PROJECT_REF"
npx -y supabase@latest db push
