#!/usr/bin/env bash
# Structural gates from RULES.md. These fail the build, not a review comment.
#   1. Tenant scope    - no raw Supabase access outside data/remote  (RULES 3.7)
#   2. Design tokens   - no raw Color(0x..) outside the token layer  (RULES 12A.8)
#   3. Domain purity   - domain/ must not import supabase            (ARCH 9.1)
#   4. Spacing scale   - flag off-scale EdgeInsets                   (DESIGN 4.1)
#   5. .env untracked  - a secret must never enter the index         (RULES 8.1)
#   6. CI pipefail     - a piped CI step must be able to fail        (RULES 12)
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
note() { printf '  %s\n' "$1"; }
gate() { printf '\n[%s] %s\n' "$1" "$2"; }

APP=app/lib

if [ -d "$APP" ] && [ -n "$(find "$APP" -name '*.dart' -print -quit 2>/dev/null)" ]; then

  gate GATE-1 "no .from( / .rpc( outside data/remote"
  hits=$(grep -rn --include='*.dart' -E '\.(from|rpc)\(' "$APP" \
         | grep -v "^$APP/data/remote/" || true)
  if [ -n "$hits" ]; then note "$hits"; fail=1; else note "ok"; fi

  gate GATE-2 "no raw Color(0x..) outside core/theme"
  hits=$(grep -rn --include='*.dart' -E 'Color\(0x[0-9a-fA-F]{8}\)' "$APP" \
         | grep -v "^$APP/core/theme/" || true)
  if [ -n "$hits" ]; then note "$hits"; fail=1; else note "ok"; fi

  gate GATE-3 "domain/ imports no supabase"
  hits=$(grep -rn --include='*.dart' -E "import .*supabase" "$APP/domain" 2>/dev/null || true)
  if [ -n "$hits" ]; then note "$hits"; fail=1; else note "ok"; fi

  gate GATE-4 "spacing values come from the 4dp scale"
  # Permitted: 4 8 12 16 20 24 32 40 48 64 (and 0).
  # -h not -n: with -o, the line-number prefix gets scraped as a spacing value.
  hits=$(grep -rh --include='*.dart' -oE 'EdgeInsets\.(all|symmetric|only)\([^)]*\)' "$APP" \
         | grep -oE '[0-9]+(\.[0-9]+)?' \
         | sort -u \
         | grep -vxE '0|4|8|12|16|20|24|32|40|48|64' || true)
  if [ -n "$hits" ]; then note "off-scale values: $(echo "$hits" | tr '\n' ' ')"; fail=1; else note "ok"; fi

else
  printf '\n(no Dart sources yet - gates 1-4 wired and will run from M0 onward)\n'
fi

printf '\n[GATE-5] .env must never be tracked\n'
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  note ".env IS TRACKED - remove it from the index immediately"; fail=1
else note "ok"; fi

printf '\n[GATE-6] CI must run steps under pipefail\n'
# Three times in M1 a check reported success while doing nothing: a leak test
# that never switched role, a grant assertion that named four of twenty tables,
# and `gates | tee log` taking tee's exit code. Only the last is mechanical
# enough to gate, so gate it. Without pipefail in the workflow's shell default,
# every piped step in CI is a gate that cannot fail.
WF=.github/workflows/ci.yml
if [ -f "$WF" ]; then
  if grep -qE '^\s*shell:\s+bash\s+-e[a-z]*o\s+pipefail' "$WF"; then
    note "ok"
  else
    note "$WF has no 'shell: bash -eo pipefail {0}' default - every piped"
    note "step in CI would report success regardless of result"
    fail=1
  fi
else
  note "no workflow yet"
fi

printf '\n%s\n' "$([ $fail -eq 0 ] && echo 'ALL GATES PASS' || echo 'GATES FAILED')"
exit $fail
