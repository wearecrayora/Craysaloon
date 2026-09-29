/**
 * What the console accepts as a salon logo, decided from the bytes.
 *
 * The logo is served publicly (join/src/worker.ts) and pulled onto every push by
 * FCM, so it is checked here rather than trusted:
 *
 * - **Raster only - PNG, JPEG, WebP.** Never SVG: an SVG is a document that can
 *   carry script, and this one would be served from the join site's origin.
 * - **The type comes from the magic bytes**, not the file name or the browser's
 *   claim. A renamed file is refused.
 * - **512 KB at most.** It is downloaded on salon wifi and onto every push.
 */

export const LOGO_MAX_BYTES = 512 * 1024;

export type LogoType = { ext: 'png' | 'jpg' | 'webp'; contentType: string };

export function sniffLogo(bytes: Uint8Array): LogoType | null {
  const at = (i: number, ...sig: number[]) => sig.every((b, j) => bytes[i + j] === b);

  if (at(0, 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) {
    return { ext: 'png', contentType: 'image/png' };
  }
  if (at(0, 0xff, 0xd8, 0xff)) return { ext: 'jpg', contentType: 'image/jpeg' };
  // RIFF....WEBP
  if (at(0, 0x52, 0x49, 0x46, 0x46) && at(8, 0x57, 0x45, 0x42, 0x50)) {
    return { ext: 'webp', contentType: 'image/webp' };
  }
  return null;
}

/** Why a file is refused, in words an operator can act on - or null if it is fine. */
export function logoProblem(bytes: Uint8Array): string | null {
  if (bytes.length === 0) return 'Choose a logo file first.';
  if (bytes.length > LOGO_MAX_BYTES) {
    return `That file is ${Math.ceil(bytes.length / 1024)} KB; a logo must be 512 KB or less.`;
  }
  if (!sniffLogo(bytes)) return 'A logo must be a PNG, JPEG or WebP image. SVG is not accepted.';
  return null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * `logos/<salon>/<sha-256>.<ext>` - the only shape the join Worker serves. The
 * hash makes the key immutable: a new logo is a new URL, so no cache anywhere
 * can keep showing the old one.
 */
export function logoKey(salonId: string, sha256Hex: string, ext: LogoType['ext']): string {
  if (!UUID.test(salonId)) throw new Error('Not a salon id.');
  if (!/^[0-9a-f]{64}$/.test(sha256Hex)) throw new Error('Not a SHA-256 hex digest.');
  return `logos/${salonId.toLowerCase()}/${sha256Hex}.${ext}`;
}

export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
