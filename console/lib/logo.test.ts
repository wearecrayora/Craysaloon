import { describe, expect, it } from 'vitest';
import { LOGO_MAX_BYTES, logoKey, logoProblem, sha256Hex, sniffLogo } from './logo';

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);
const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16]);
const webp = new Uint8Array([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50]);
const svg = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>x</script></svg>');

describe('logo', () => {
  it('knows a PNG, JPEG and WebP from their bytes', () => {
    expect(sniffLogo(png)?.ext).toBe('png');
    expect(sniffLogo(jpg)?.ext).toBe('jpg');
    expect(sniffLogo(webp)?.ext).toBe('webp');
  });

  it('refuses SVG - it can carry script, and would be served from a public origin', () => {
    expect(sniffLogo(svg)).toBeNull();
    expect(logoProblem(svg)).toMatch(/SVG is not accepted/);
  });

  it('refuses an empty file and one over 512 KB, saying which', () => {
    expect(logoProblem(new Uint8Array())).toMatch(/Choose/);
    const big = new Uint8Array(LOGO_MAX_BYTES + 1);
    big.set(png);
    expect(logoProblem(big)).toMatch(/513 KB/);
    expect(logoProblem(png)).toBeNull();
  });

  it('keys are content hashes under the salon - the only shape the Worker serves', async () => {
    const sha = await sha256Hex(png);
    expect(sha).toMatch(/^[0-9a-f]{64}$/);
    const key = logoKey('11111111-0000-4000-8000-000000000001', sha, 'png');
    expect(key).toBe(`logos/11111111-0000-4000-8000-000000000001/${sha}.png`);
    // The join Worker's pattern, verbatim (join/src/worker.ts).
    expect(`/brand/${key}`).toMatch(
      /^\/brand\/(logos\/[0-9a-f-]{36}\/[0-9a-f]{64}\.(png|jpg|webp))$/,
    );
  });

  it('will not build a key from anything but a salon id and a digest', () => {
    expect(() => logoKey('../../etc', 'a'.repeat(64), 'png')).toThrow();
    expect(() => logoKey('11111111-0000-4000-8000-000000000001', 'nope', 'png')).toThrow();
  });
});
