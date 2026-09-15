import 'server-only';
import {
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

/**
 * Cloudflare R2, over its S3-compatible API.
 *
 * The bucket is PRIVATE - r2.dev public access is off and no custom domain is
 * attached, which was verified when this was built: an unsigned GET returns
 * 400. Every object the console hands out is therefore a short-lived signed
 * URL, never a permanent link. A QR pack carries a salon's join code, and an
 * invoice carries a customer's name; neither should be fetchable forever by
 * anyone who once saw the address.
 *
 * `server-only`: these keys can write to every bucket on the account (the
 * token was issued account-wide), so importing this from a client component
 * must be a build error. The secret scan also checks the built bundle for the
 * literal key values.
 */

declare global {
  // eslint-disable-next-line no-var
  var __r2: S3Client | undefined;
}

function need(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`${name} is not set. See console/.env.local.example.`);
  }
  return v;
}

function client(): S3Client {
  if (!globalThis.__r2) {
    globalThis.__r2 = new S3Client({
      region: 'auto',
      endpoint: need('R2_ENDPOINT'),
      credentials: {
        accessKeyId: need('R2_ACCESS_KEY_ID'),
        secretAccessKey: need('R2_SECRET_ACCESS_KEY'),
      },
    });
  }
  return globalThis.__r2;
}

const bucket = () => need('R2_BUCKET');

export async function putObject(key: string, body: Uint8Array, contentType: string) {
  await client().send(
    new PutObjectCommand({
      Bucket: bucket(),
      Key: key,
      Body: body,
      ContentType: contentType,
      // Private objects should not linger in intermediary caches either.
      CacheControl: 'private, no-store',
    }),
  );
}

/**
 * A signed GET URL. Short by default: long enough to click "Download" and
 * open the file, not long enough to be worth leaking.
 */
export async function signedUrl(key: string, expiresInSeconds = 600): Promise<string> {
  return getSignedUrl(
    client(),
    new GetObjectCommand({
      Bucket: bucket(),
      Key: key,
      // Makes the browser save it with a sensible name instead of the key.
      ResponseContentDisposition: `attachment; filename="${key.split('/').pop()}"`,
    }),
    { expiresIn: expiresInSeconds },
  );
}

/** Newest object under a prefix, or null. Keys carry a sortable timestamp. */
export async function latestUnder(prefix: string): Promise<string | null> {
  const out = await client().send(
    new ListObjectsV2Command({ Bucket: bucket(), Prefix: prefix, MaxKeys: 1000 }),
  );
  const keys = (out.Contents ?? []).map((o) => o.Key).filter((k): k is string => !!k);
  if (keys.length === 0) return null;
  return keys.sort().at(-1) ?? null;
}
