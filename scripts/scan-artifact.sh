#!/usr/bin/env bash
# Scan a BUILT app (APK or AAB) for credentials (PRD 20: "no secret keys in the
# APK", RULES 11.1).
#
#   ./scripts/scan-artifact.sh app/build/app/outputs/flutter-apk/app-release.apk
#
# The repository scan (secret-scan.sh) proves no secret is COMMITTED. This proves
# none was COMPILED IN - a --dart-define with the wrong variable, a config file
# bundled as an asset - which a source scan cannot see.
#
# Two checks:
#   1. credential SHAPES (a service-role JWT, a private key, a secret key id);
#   2. the LITERAL value of every secret-looking variable in .env - the
#      strongest test there is: if the real secret is in the binary, it is
#      found, whatever its shape.
#
# Prints variable NAMES and file names only, never a value: a scanner that
# leaks the secret it found is worse than none.
#
# Allowed in a client, by design, and therefore not searched for: the Supabase
# PUBLISHABLE key, the Supabase URL, the Sentry DSN, and the Firebase API key
# in google-services.json (an identifier, restricted by app signature).
set -uo pipefail
cd "$(dirname "$0")/.."

ARTIFACT="${1:?usage: scan-artifact.sh <apk|aab>}"
[ -f "$ARTIFACT" ] || { echo "No such file: $ARTIFACT"; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -qq -o "$ARTIFACT" -d "$WORK" || { echo "Not a zip: $ARTIFACT"; exit 2; }

fail=0

shapes=(
  'sb_secret_[A-Za-z0-9_-]{10,}'
  'BEGIN [A-Z ]*PRIVATE KEY'
  'eyJhbGciOi[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
  'postgres(ql)?://[^ ]*:[^ ]*@'
)
for p in "${shapes[@]}"; do
  hits=$(grep -rlaE "$p" "$WORK" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "CREDENTIAL SHAPE IN THE BUILD [$p]:"
    echo "$hits" | sed "s|$WORK/|  |"
    fail=1
  fi
done

# SCAN_ENV_FILE points the literal check at another env file - used only by the
# scanner's own negative control, with a fake secret (never a real one).
ENV_FILE="${SCAN_ENV_FILE:-.env}"
checked=0
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r name value; do
    [[ "$name" =~ ^[A-Z0-9_]+$ ]] || continue
    [[ "$name" =~ (SECRET|TOKEN|PASSWORD|PRIVATE|PEPPER|DATABASE_URL|DB_URL|ACCESS_KEY) ]] || continue
    [[ "$name" =~ PUBLISHABLE ]] && continue
    value="${value%\"}"; value="${value#\"}"; value="${value%$'\r'}"
    [ ${#value} -ge 12 ] || continue
    checked=$((checked + 1))
    if grep -rqaF -- "$value" "$WORK" 2>/dev/null; then
      echo "THE VALUE OF $name IS IN THE BUILD."
      fail=1
    fi
  done < "$ENV_FILE"
fi

if [ $fail -eq 0 ]; then
  echo "ARTIFACT CLEAN - $(basename "$ARTIFACT"): no credential shapes; none of $checked secret values from .env present."
else
  echo "ARTIFACT FAILED - do not distribute $(basename "$ARTIFACT")."
fi
exit $fail
