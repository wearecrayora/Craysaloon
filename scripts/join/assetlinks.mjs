// Generates join/public/.well-known/assetlinks.json - the file that makes
// https://join.craysalon.in/s/<code> an Android App Link.
//
//   node scripts/join/assetlinks.mjs --debug
//   node scripts/join/assetlinks.mjs --fingerprint AA:BB:...:FF [--fingerprint ...]
//
// It is generated, never committed (see join/README.md): the fingerprint must be
// the one the APK is really signed with, and a placeholder would fail
// verification SILENTLY - every customer's link quietly opening the website
// instead of the app, with nothing in any log to explain it.
//
// More than one fingerprint is normal and expected: Play App Signing re-signs
// the app, so the upload certificate AND the Play signing certificate both have
// to be listed, or links break for everyone who installed from the Store.

import { mkdir, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const ROOT = path.resolve(import.meta.dirname, '../..');
const OUT = path.join(ROOT, 'join/public/.well-known/assetlinks.json');
const PACKAGE = 'com.crayora.craysalon';

/// keytool lives in the JDK. Android Studio bundles one (JBR) and most machines
/// here have no separate JDK on PATH, so look where it actually is.
function keytool() {
  const exe = process.platform === 'win32' ? 'keytool.exe' : 'keytool';
  const candidates = [
    process.env.JAVA_HOME && path.join(process.env.JAVA_HOME, 'bin', exe),
    process.platform === 'win32' && 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool',
    '/usr/lib/jvm/default/bin/keytool',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return exe; // On PATH, or the caller gets a clear message below.
}

const args = process.argv.slice(2);
const fingerprints = [];

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--fingerprint') fingerprints.push(args[++i]);
}

if (args.includes('--debug')) {
  // The debug keystore Android Studio and `flutter run` use. Good for testing
  // App Links on your own device; useless for the Play build.
  const keystore = path.join(os.homedir(), '.android/debug.keystore');
  if (!existsSync(keystore)) {
    console.error(`No debug keystore at ${keystore}. Run the app once, or pass --fingerprint.`);
    process.exit(1);
  }
  let output;
  try {
    output = execFileSync(
      keytool(),
      ['-list', '-v', '-keystore', keystore, '-alias', 'androiddebugkey',
       '-storepass', 'android', '-keypass', 'android'],
      { encoding: 'utf8' },
    );
  } catch (e) {
    console.error(
      `Could not run keytool (${e.code ?? e.message}).\n` +
      'It ships inside the JDK, not on PATH by default. Set JAVA_HOME, or read the\n' +
      'fingerprint yourself and pass --fingerprint:\n' +
      '  keytool -list -v -keystore ~/.android/debug.keystore ' +
      '-alias androiddebugkey -storepass android',
    );
    process.exit(1);
  }
  const match = /SHA256:\s*([0-9A-F:]{95})/i.exec(output);
  if (!match) {
    console.error('Could not read a SHA-256 fingerprint from keytool output.');
    process.exit(1);
  }
  fingerprints.push(match[1]);
  console.log('Using the DEBUG fingerprint. Never deploy this for release.');
}

if (fingerprints.length === 0) {
  console.error(
    'Nothing to write. Pass --debug for local testing, or --fingerprint <SHA-256>\n' +
    'for the release and Play App Signing certificates (usually both).',
  );
  process.exit(1);
}

const shape = /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/i;
for (const fingerprint of fingerprints) {
  if (!shape.test(fingerprint.trim())) {
    console.error(`Not a SHA-256 certificate fingerprint: ${fingerprint}`);
    process.exit(1);
  }
}

const document = [
  {
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: PACKAGE,
      sha256_cert_fingerprints: fingerprints.map((f) => f.trim().toUpperCase()),
    },
  },
];

await mkdir(path.dirname(OUT), { recursive: true });
await writeFile(OUT, `${JSON.stringify(document, null, 2)}\n`);
console.log(`Wrote ${path.relative(ROOT, OUT)} with ${fingerprints.length} fingerprint(s).`);
console.log(
  'After deploying, confirm Google can read it:\n' +
  '  https://digitalassetlinks.googleapis.com/v1/statements:list' +
  '?source.web.site=https://join.craysalon.in' +
  '&relation=delegate_permission/common.handle_all_urls',
);
