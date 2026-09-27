# `join.craysalon.in`

The domain every printed QR points at (`ARCHITECTURE.md` 5.6). Three jobs, in order
of how often they matter:

1. **`/.well-known/assetlinks.json`** — makes `/s/<code>` an Android **App Link**, so a
   phone that already has the app opens it directly, with no chooser. This file is
   **not in the repo**: see below.
2. **`/s/<code>`** — what a phone sees when the app is *not* installed: the code, in
   large type, and a Play link carrying `referrer=code=CRAY-XXXXXX` so a fresh install
   can open on the right salon.
3. **`/`** — for someone who typed the domain. It names no salon and lists none.

Static, no framework, no analytics, no fonts. It is opened on salon wifi.

## Deploying

A separate Vercel project from `console/`, with this directory as the root. It is
public and holds no secret, which is exactly why it must stay separate from the
console: nothing here should sit behind the console's authentication, and nothing
here should be able to reach the console's environment.

```
vercel --cwd join
```

Then point `join.craysalon.in` at it, and add the same domain to
`console/server/qr-pack.ts`'s expectations only if the URL shape ever changes — every
QR already printed encodes `https://join.craysalon.in/s/<code>`, and those cards are
on salon counters. **The path shape is now permanent.**

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
https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://join.craysalon.in&relation=delegate_permission/common.handle_all_urls
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
