# Release build (Android, for Google Play)

**Written for: whoever builds the Play release at Crayora.** Do this on one trusted machine.

A release needs three things the repository deliberately does not hold: the **upload key**, the
build-time configuration in `.env`, and `google-services.json`. Everything else is in the repo.

## 1. The upload key - once, ever

Create it once and keep it for the life of the app. Lose it and Play's key-reset process is slow;
leak it and someone else can sign updates. Use the JDK's `keytool` (Android Studio ships one at
`C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`):

```
keytool -genkey -v -keystore D:\keys\craysalon-upload.jks -keyalg RSA -keysize 2048 ^
        -validity 10000 -alias upload
```

- Keep the `.jks` **outside the repository** (`*.jks` is gitignored anyway), and keep an
  offline backup with its passwords somewhere that is not this laptop.
- Enrol the app in **Play App Signing** when you create it in the Play Console. Google then holds
  the key that signs what customers install; yours only uploads. A lost upload key can then be
  reset - a lost app-signing key could not.

## 2. Point the build at it

Create `app/android/key.properties` (gitignored - never commit it):

```
storeFile=D:/keys/craysalon-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without this file, `scripts/build-apk.sh release` and `bundle` **refuse to run**: a debug-signed
"release" is exactly the artifact that must not reach a phone. (`ALLOW_DEBUG_SIGNED=1` builds one
for a local look; it is labelled as such in the output.)

## 3. Build and scan

```
./scripts/build-apk.sh bundle      # app-release.aab - what you upload to Play
./scripts/build-apk.sh release     # app-release.apk - for installing on a test phone
```

Both pass the Supabase URL, the **publishable** key and the Sentry DSN from `.env` as
`--dart-define`, and then run `scripts/scan-artifact.sh` on the result. It fails - and you do
not upload - if the build contains a credential shape (a secret key, a private key, a service-role
token, a database URL with a password) **or the literal value of any secret in `.env`**. It prints
variable names only, never a value.

The scanner was proven both ways on 12 Oct 2026: a real release APK passed; a copy with a planted
fake secret failed, naming the variable.

## 4. App Links (the QR opens the app)

After the first upload, Play Console → **App integrity** shows two SHA-256 certificate
fingerprints: the **app signing** key (Google's) and the **upload** key (yours). Both go into the
App Links file, or customers who installed from Play will have every QR open the website instead
of the app:

```
node scripts/join/assetlinks.mjs --fingerprint <APP-SIGNING SHA-256> --fingerprint <UPLOAD SHA-256>
cd join && npx wrangler deploy
```

Then check Google can read it (`join/README.md`, "assetlinks.json").

## 5. Before pressing "release"

- `docs/release/PRD20-audit.md` is green, or every open item is accepted in writing.
- The Play listing's privacy-policy URL is
  `https://craysalon-join.crayoratech.workers.dev/privacy`, and its account-deletion URL is
  `https://craysalon-join.crayoratech.workers.dev/privacy#delete`.
- The Data Safety form matches the policy: phone number, name, purchase history, app interactions
  (bookings), crash logs, device IDs (the push token); **no** location, contacts, photos library
  or advertising ID; data encrypted in transit; deletion can be requested.
