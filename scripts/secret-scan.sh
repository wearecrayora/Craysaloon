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
# Phase 0: THE WORKING TREE - files that are neither tracked nor ignored
# ---------------------------------------------------------------------------
#
# Phase 1 scans TRACKED files, which is correct and insufficient. A credential
# that has been downloaded into the repo and not yet committed is not tracked,
# so it passes - and it is exactly one `git add -A` from being published.
#
# That is not hypothetical: a Firebase service-account key (a real RSA private
# key) was saved into the repo root on 2026-09-28, and this script called the
# repository clean. The ignore rules did not cover it either, because they were
# written for the files anyone thought to name.
#
# So: anything git would pick up on a broad `add` gets the same patterns applied.
# Putting the file in .gitignore is the fix that silences this, which is the
# correct fix - an ignored credential is a local file, like .env.

untracked=$(git ls-files --others --exclude-standard 2>/dev/null || true)

if [ -n "$untracked" ]; then
  for p in "${patterns[@]}"; do
    # -l, not -n: file NAMES only. The first version of this printed the
    # matching line, which put 120 characters of a live RSA private key into the
    # build log - a scanner that leaks the secret it found is worse than none.
    hits=$(echo "$untracked" | xargs grep -lEI "$p" 2>/dev/null || true)
    if [ -n "$hits" ]; then
      echo "CREDENTIAL IN THE WORKING TREE, NOT IGNORED [$p]"
      echo "$hits" | sed 's/^/  /'
      echo "  ^ untracked and unignored: one 'git add -A' from being published."
      echo "    Move it outside the repo, or add it to .gitignore."
      fail=1
    fi
  done
fi

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
# RULES 12 asks for a scan of "the APK and the console client bundle", not just
# the repository. Phase 1 above only sees tracked files, and a credential
# reaching users does not have to be committed to get there - it only has to be
# read at build time and inlined. NEXT_PUBLIC_* is exactly that mechanism, and
# a single mistyped variable name is all it takes.
#
# Scanned when present; skipped with a note when not, because a developer who
# has not built anything should still be able to run this.

artifacts=""
[ -d console/.next/static ] && artifacts="$artifacts console/.next/static"
# The console on Cloudflare (vinext): everything under assets/ is served to browsers.
[ -d console/.cloudflare/output/v0/workers/default/assets ] &&   artifacts="$artifacts console/.cloudflare/output/v0/workers/default/assets"
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
    # R2 and the Cloudflare token were added 2026-09-15. The token is
    # ACCOUNT-WIDE (create/delete on every bucket), so it is the single most
    # damaging value that could reach a browser bundle.
    for name in SUPABASE_SECRET_KEY DATABASE_URL ADMIN_DATABASE_URL \
                PHONE_HASH_PEPPER R2_SECRET_ACCESS_KEY R2_ACCESS_KEY_ID \
                CLOUDFLARE_API_TOKEN RAZORPAY_KEY_SECRET \
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
