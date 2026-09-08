#!/usr/bin/env bash
# Build the Android app with the build-time configuration it needs.
#
# The Sentry DSN and Supabase keys are NOT committed - they are passed as
# --dart-define at build time. Forgetting them does not break the build, it
# silently ships an app with no crash reporting, so this script exists to make
# forgetting hard.
#
#   ./scripts/build-apk.sh              debug
#   ./scripts/build-apk.sh release      release, production environment
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
[ -f .env ] || { echo "No .env - copy .env.example and fill it."; exit 1; }
set -a; . ./.env; set +a

APP_ENV="development"
[ "$MODE" = "release" ] && APP_ENV="production"

if [ -z "${SENTRY_DSN:-}" ]; then
  echo "WARNING: SENTRY_DSN is empty - building with crash reporting DISABLED."
fi

cd app
exec flutter build apk --"$MODE" \
  --dart-define=SENTRY_DSN="${SENTRY_DSN:-}" \
  --dart-define=APP_ENV="$APP_ENV" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
