#!/usr/bin/env bash
# Build the Android app with the build-time configuration it needs.
#
# The Sentry DSN and Supabase keys are NOT committed - they are passed as
# --dart-define at build time. Forgetting them does not break the build, it
# silently ships an app with no crash reporting, so this script exists to make
# forgetting hard.
#
#   ./scripts/build-apk.sh              debug APK
#   ./scripts/build-apk.sh release      release APK, production environment
#   ./scripts/build-apk.sh bundle       release App Bundle (.aab) - what Play takes
#
# A release or bundle build REFUSES to run without the upload key
# (app/android/key.properties, docs/runbooks/release-build.md): a debug-signed
# "release" is exactly the artifact that must never reach a phone. Set
# ALLOW_DEBUG_SIGNED=1 to build one anyway for a local look - it is labelled.
#
# Every release artifact is then scanned for credentials (scan-artifact.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
[ -f .env ] || { echo "No .env - copy .env.example and fill it."; exit 1; }
set -a; . ./.env; set +a

case "$MODE" in
  debug)   FLUTTER=(apk --debug);   OUT=app/build/app/outputs/flutter-apk/app-debug.apk ;;
  release) FLUTTER=(apk --release); OUT=app/build/app/outputs/flutter-apk/app-release.apk ;;
  bundle)  FLUTTER=(appbundle --release); OUT=app/build/app/outputs/bundle/release/app-release.aab ;;
  *) echo "Unknown mode: $MODE (debug | release | bundle)"; exit 1 ;;
esac

APP_ENV="development"
if [ "$MODE" != "debug" ]; then
  APP_ENV="production"
  if [ ! -f app/android/key.properties ]; then
    if [ "${ALLOW_DEBUG_SIGNED:-}" = "1" ]; then
      echo "WARNING: no upload key - this $MODE build is DEBUG-signed. Not for Play, not for customers."
    else
      echo "No app/android/key.properties - refusing to build a $MODE artifact with the debug key."
      echo "See docs/runbooks/release-build.md, or set ALLOW_DEBUG_SIGNED=1 for a local look."
      exit 1
    fi
  fi
fi

if [ -z "${SENTRY_DSN:-}" ]; then
  echo "WARNING: SENTRY_DSN is empty - building with crash reporting DISABLED."
fi

(cd app && flutter build "${FLUTTER[@]}" \
  --dart-define=SENTRY_DSN="${SENTRY_DSN:-}" \
  --dart-define=APP_ENV="$APP_ENV" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}")

if [ "$MODE" != "debug" ]; then
  ./scripts/scan-artifact.sh "$OUT"
fi
