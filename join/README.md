# The join site - `craysalon-join.crayoratech.workers.dev`

The address every printed QR points at (`ARCHITECTURE.md` 5.6). Three jobs, in order
of how often they matter:

1. **`/.well-known/assetlinks.json`** — makes `/s/<code>` an Android **App Link**, so a
   phone that already has the app opens it directly, with no chooser. This file is
   **not in the repo**: see below.
2. **`/s/<code>`** — what a phone sees when the app is *not* installed: the code, in
   large type, and a Play link carrying `referrer=code=CRAY-XXXXXX` so a fresh install
   can open on the right salon.
3. **`/`** — for someone who typed the address. It names no salon and lists none.

Static, no framework, no analytics, no fonts. It is opened on salon wifi.

One exception to "static": **`/brand/logos/<salon>/<sha-256>.<ext>`** serves salon logos from the
`craysalon-brand` R2 bucket (`src/worker.ts`). They must be public - FCM pulls the logo onto every
push - and this is the only public origin there is. Only that exact key shape is served, GET/HEAD
only, immutable, as an image with a sandboxing CSP. `run_worker_first` sends only `/brand/*` to
the script; every other path is plain static assets.

## Deploying

**Cloudflare Pages** (moved from Vercel, 29 Sep 2026), a separate project from the
console. It is public and holds no secret, which is exactly why it must stay separate
from the console: nothing here should sit behind the console's authentication, and
nothing here should be able to reach the console's environment.

```
cd join
npx wrangler deploy              # static assets from ./public (wrangler.jsonc)
npx wrangler dev --ip 127.0.0.1  # local check
```

Cloudflare has folded Pages into Workers: "Pages" is now a Worker that serves static assets and
runs no script, and `_redirects` / `_headers` still apply. Live (29 Sep 2026) at
`https://craysalon-join.crayoratech.workers.dev`, **and that is the permanent address**: no custom domain is being
bought (30 Sep 2026), and every QR the console prints encodes this origin. If a domain is
attached one day, it is **added** - to the Worker, to `JoinLink.hosts` in the app, to the
Android intent filter and to `assetlinks.json` - and this address stays live, because cards
already on salon counters point at it.

Routing lives in `public/_redirects` (`/s/<code>` is a rewrite to `s.html`, so the address
bar keeps the code the page reads) and headers in `public/_headers`. Pages serves
`/privacy` for `privacy.html` on its own. Checked locally on Cloudflare's Pages server:
`/s/CRAY-7KQ2MX` 200 with the code intact, `/privacy` 200, `/privacy.html` 308 to `/privacy`.

The origin lives in exactly two constants: `JOIN_ORIGIN` in `console/server/qr-pack.ts` and
`JoinLink.origin` in the app. Every QR printed encodes `https://craysalon-join.crayoratech.workers.dev/s/<code>`,
and those cards are on salon counters. **The origin and the path shape are now permanent.**

## `/privacy` — the published policy

`public/privacy.html`, served at `https://craysalon-join.crayoratech.workers.dev/privacy`. It is the
URL the Play listing points at, the URL the in-app consent notice links to, and the document a
customer is entitled to under DPDP s.5. It is linked from `/` and from `/s/<code>`.

**The page is already reachable** (the site is live). **Two things must happen before this URL
is given to Play, linked from a printed card, or a salon goes live:**

1. **Fill the placeholders.** Every `[SQUARE-BRACKET]` item is one of Crayora's own registered
   details — legal name, registered address, the named privacy contact and its email. Grep for
   `[` before deploying:

   ```
   grep -n "\[[A-Z ]\+\]" join/public/privacy.html
   ```

   No hits means it is ready. A published policy naming nobody is worse than no policy: it is
   evidence that the obligation was noticed and skipped.

2. **Have a lawyer read it.** It is written to be accurate about what the software does — every
   claim in it can be checked against a migration, a gate or an Edge Function — but accuracy is
   not the same as legal sufficiency, and Crayora's own corporate details are not something code
   review can verify.

**When the software changes, this page changes in the same commit.** If it says photos need
separate consent, or that credentials cannot be read back, those are statements about the
system that a regulator is entitled to test. Hindi and Hinglish translations are still owed
(the app ships `en`/`hi`/`hi_Latn`).

## assetlinks.json — why it is not committed

The file must carry the **SHA-256 fingerprint of the certificate the release APK is
actually signed with**. Committing a placeholder would be worse than committing
nothing: Android fetches the file, fails verification silently, and the link quietly
opens the website for every customer instead of the app — with nothing in any log to
say why.

Release signing belongs to M13. Until then:

```bash
# Debug key, for testing App Links on your own device only:
node scripts/join/assetlinks.mjs --debug

# Release, at M13, from the upload/release keystore:
node scripts/join/assetlinks.mjs --fingerprint AA:BB:CC:...
```

The script writes `join/public/.well-known/assetlinks.json`, which is gitignored.
`scripts/lint-gates.sh` (GATE-8) fails the build if a committed copy ever appears, or
if the generated file contains anything but real fingerprints.

Verify after deploying:

```
https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://craysalon-join.crayoratech.workers.dev&relation=delegate_permission/common.handle_all_urls
```

## What is still missing

**Play Install Referrer is only half-built.** The link here carries the code, and
`JoinLink.parse` already reads `?code=`, but nothing in the app reads the *install
referrer* yet — that needs a Play Console listing to test against. Until it does, a
customer installing from this page sees the code on screen and types it. That is the
fallback working as intended, not a bug.

**iOS.** No Apple App Site Association file, because iOS ships later (`RULES.md` 15b)
and the file needs a real Apple Developer team id. `apple-app-site-association` goes
next to `assetlinks.json` when that exists.
