#!/usr/bin/env bash
# Fail the build if a credential reaches the repo (RULES.md 11.1, PRD 20).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# Known credential shapes. .env is gitignored, so scan only tracked files.
#
# Three files legitimately contain credential SHAPES and are excluded by name:
#   scripts/secret-scan.sh           - the patterns themselves
#   .env.example                     - documents the shape, holds no values
#   app/test/observability_test.dart - fixtures proving the scrubber redacts
#                                      them. Fixtures must be obviously fake.
patterns=(
  'sb_secret_[A-Za-z0-9_-]{10,}'
  # No bare 'service_role' pattern: that is a legitimate Postgres role name in
  # GRANT statements. The real legacy key is a JWT, caught by eyJ below.
  'rzp_live_[A-Za-z0-9]{10,}'
  'rzp_test_[A-Za-z0-9]{10,}'
  'BEGIN [A-Z ]*PRIVATE KEY'
  'AIza[0-9A-Za-z_-]{30,}'
  'eyJhbGciOi[A-Za-z0-9_-]{20,}'
)

# ---------------------------------------------------------------------------
# Phase 1: THE REPOSITORY
# ---------------------------------------------------------------------------

files=$(git ls-files 2>/dev/null || true)
[ -z "$files" ] && { echo "no tracked files yet - nothing to scan"; exit 0; }

for p in "${patterns[@]}"; do
  hits=$(echo "$files" | xargs grep -nEI "$p" 2>/dev/null \
         | grep -v '^scripts/secret-scan.sh:' \
         | grep -v '^\.env\.example:' \
         | grep -v '^app/test/observability_test.dart:' || true)
  if [ -n "$hits" ]; then
    echo "LEAK [$p]"; echo "$hits" | sed 's/^/  /'; fail=1
  fi
done

# ---------------------------------------------------------------------------
# Phase 2: BUILT ARTIFACTS
# ---------------------------------------------------------------------------
#
# RULES 12 asks for a scan of "the APK and the Vercel client bundle", not just
# the repository. Phase 1 above only sees tracked files, and a credential
# reaching users does not have to be committed to get there - it only has to be
# read at build time and inlined. NEXT_PUBLIC_* is exactly that mechanism, and
# a single mistyped variable name is all it takes.
#
# Scanned when present; skipped with a note when not, because a developer who
# has not built anything should still be able to run this.

artifacts=""
[ -d console/.next/static ] && artifacts="$artifacts console/.next/static"
for apk in app/build/app/outputs/flutter-apk/*.apk \
           app/build/app/outputs/apk/*/*/*.apk; do
  [ -f "$apk" ] && artifacts="$artifacts $apk"
done

if [ -z "$artifacts" ]; then
  echo "(no built artifacts to scan - build the console or the APK to include them)"
else
  for p in "${patterns[@]}"; do
    hits=$(grep -rlEI "$p" $artifacts 2>/dev/null || true)
    if [ -n "$hits" ]; then
      echo "LEAK IN BUILD OUTPUT [$p]"; echo "$hits" | sed 's/^/  /'; fail=1
    fi
  done

  # Shape patterns cannot catch a pepper or a database password - those have no
  # recognisable form. So when a local .env exists, check the literal VALUES of
  # everything that must stay server-side. In CI there is no .env and this part
  # is skipped, which is why the shape patterns above still matter.
  if [ -f .env ]; then
    set -a; . ./.env; set +a
    for name in SUPABASE_SECRET_KEY DATABASE_URL ADMIN_DATABASE_URL \
                PHONE_HASH_PEPPER R2_SECRET_ACCESS_KEY RAZORPAY_KEY_SECRET \
                MESSAGE_CENTRAL_AUTH_KEY; do
      val="${!name-}"
      # Ignore short or empty values: a two-character "secret" would match
      # everywhere and turn this into noise.
      [ -z "$val" ] && continue
      [ ${#val} -lt 12 ] && continue
      hits=$(grep -rlF -- "$val" $artifacts 2>/dev/null || true)
      if [ -n "$hits" ]; then
        echo "LEAK IN BUILD OUTPUT [value of $name]"; echo "$hits" | sed 's/^/  /'; fail=1
      fi
    done
  fi
fi

[ $fail -eq 0 ] && echo "SECRET SCAN CLEAN" || echo "SECRET SCAN FAILED"
exit $fail
