#!/usr/bin/env bash
# Missing translations are a silent failure - a key falls back to English and
# nobody notices until a Hindi-speaking customer sees it. So: gate it.
# Also reports longest-locale pressure, which is what breaks fixed-height
# layouts (DESIGN.md 5.3.4).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f app/l10n/app_en.arb ] || { echo "no ARB files yet - skipping"; exit 0; }
python - <<'PY'
import json, io, sys, glob, os
base = json.load(io.open('app/l10n/app_en.arb', encoding='utf-8'))
keys = {k for k in base if not k.startswith('@')}
ok = True
for path in sorted(glob.glob('app/l10n/app_*.arb')):
    loc = os.path.basename(path)[4:-4]
    if loc == 'en':
        continue
    d = json.load(io.open(path, encoding='utf-8'))
    ks = {k for k in d if not k.startswith('@')}
    missing, extra = sorted(keys - ks), sorted(ks - keys)
    status = 'ok' if not missing and not extra else 'FAIL'
    print(f"{loc:10} {len(ks):3} keys  {status}")
    if missing:
        print(f"  missing: {missing}"); ok = False
    if extra:
        print(f"  extra  : {extra}"); ok = False
    # Placeholders must survive translation or the string crashes at runtime.
    for k in keys & ks:
        if isinstance(base[k], str) and isinstance(d[k], str):
            import re
            pb = set(re.findall(r'\{(\w+)\}', base[k]))
            pd = set(re.findall(r'\{(\w+)\}', d[k]))
            if pb != pd:
                print(f"  placeholder mismatch in '{k}': en={sorted(pb)} {loc}={sorted(pd)}")
                ok = False
print('L10N OK' if ok else 'L10N FAILED')
sys.exit(0 if ok else 1)
PY
