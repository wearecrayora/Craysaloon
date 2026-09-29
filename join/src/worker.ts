// The join site's only code: serving salon logos from the public-brand bucket.
//
// Everything else on this site is static (public/), served by Cloudflare
// without this script running - `run_worker_first` sends only /brand/* here.
//
// Why logos live behind this Worker: they must be fetchable by anyone - FCM
// pulls the logo onto a push, and the app shows it - but the main R2 bucket is
// private (QR packs, invoices), and there is no custom domain to put a public
// bucket on. So logos have their own bucket, craysalon-brand, and this is its
// only reader. The console writes it (console/server/r2.ts, putBrandObject).
//
// Read-only, by construction: GET and HEAD, nothing else. Keys are content
// hashes, so every object is immutable and cached for a year.

interface Env {
  BRAND: R2Bucket;
  ASSETS: Fetcher;
}

// logos/<salon uuid>/<sha-256 hex>.<png|jpg|webp> - nothing else is served,
// so a stray object in the bucket is never published by accident.
const LOGO = /^\/brand\/(logos\/[0-9a-f-]{36}\/[0-9a-f]{64}\.(png|jpg|webp))$/;

const TYPES: Record<string, string> = { png: 'image/png', jpg: 'image/jpeg', webp: 'image/webp' };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/brand/')) return env.ASSETS.fetch(request);

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }

    const match = LOGO.exec(url.pathname);
    if (!match) return new Response('Not found', { status: 404 });

    const object = await env.BRAND.get(match[1]);
    if (!object) return new Response('Not found', { status: 404 });

    return new Response(request.method === 'HEAD' ? null : object.body, {
      headers: {
        // From the extension we validated, never from the stored metadata.
        'Content-Type': TYPES[match[2]],
        'Cache-Control': 'public, max-age=31536000, immutable',
        'X-Content-Type-Options': 'nosniff',
        // An image, never a document: nothing here may run script.
        'Content-Security-Policy': "default-src 'none'; sandbox",
        ETag: object.httpEtag,
      },
    });
  },
};
