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

[ $fail -eq 0 ] && echo "SECRET SCAN CLEAN" || echo "SECRET SCAN FAILED"
exit $fail
