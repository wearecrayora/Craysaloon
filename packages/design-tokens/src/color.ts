// Colour maths. sRGB <-> OKLab/OKLCH for perceptual lightness steps,
// plus WCAG 2.1 contrast for the publish gate (DESIGN.md 3.3).

export type RGB = { r: number; g: number; b: number }; // 0..1
export type OKLCH = { L: number; C: number; h: number }; // L 0..1, h degrees

const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);

export function hexToRgb(hex: string): RGB {
  const h = hex.trim().replace(/^#/, "");
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h;
  if (!/^[0-9a-fA-F]{6}$/.test(full)) throw new Error(`Not a hex colour: ${hex}`);
  return {
    r: parseInt(full.slice(0, 2), 16) / 255,
    g: parseInt(full.slice(2, 4), 16) / 255,
    b: parseInt(full.slice(4, 6), 16) / 255,
  };
}

export function rgbToHex({ r, g, b }: RGB): string {
  const c = (v: number) =>
    Math.round(clamp01(v) * 255).toString(16).padStart(2, "0");
  return `#${c(r)}${c(g)}${c(b)}`;
}

// WCAG 2.1 linearisation - deliberately NOT the same curve as OKLab's.
const wcagLin = (v: number) =>
  v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);

export function relativeLuminance(hex: string): number {
  const { r, g, b } = hexToRgb(hex);
  return 0.2126 * wcagLin(r) + 0.7152 * wcagLin(g) + 0.0722 * wcagLin(b);
}

/** WCAG 2.1 contrast ratio, 1..21. Order of arguments does not matter. */
export function contrast(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

const srgbToLinear = (v: number) =>
  v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
const linearToSrgb = (v: number) =>
  v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;

export function hexToOklch(hex: string): OKLCH {
  const { r, g, b } = hexToRgb(hex);
  const lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b);

  const l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb;
  const m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb;
  const s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb;

  const l_ = Math.cbrt(l), m_ = Math.cbrt(m), s_ = Math.cbrt(s);

  const L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
  const A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
  const B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

  const C = Math.sqrt(A * A + B * B);
  let h = (Math.atan2(B, A) * 180) / Math.PI;
  if (h < 0) h += 360;
  return { L, C, h };
}

export function oklchToHex({ L, C, h }: OKLCH): string {
  const hr = (h * Math.PI) / 180;
  const A = C * Math.cos(hr);
  const B = C * Math.sin(hr);

  const l_ = L + 0.3963377774 * A + 0.2158037573 * B;
  const m_ = L - 0.1055613458 * A - 0.0638541728 * B;
  const s_ = L - 0.0894841775 * A - 1.2914855480 * B;

  const l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;

  const lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  const lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  const lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  return rgbToHex({
    r: clamp01(linearToSrgb(lr)),
    g: clamp01(linearToSrgb(lg)),
    b: clamp01(linearToSrgb(lb)),
  });
}

/** Move a colour's perceptual lightness, keeping hue and chroma. */
export function withLightness(hex: string, L: number): string {
  const c = hexToOklch(hex);
  return oklchToHex({ ...c, L: clamp01(L) });
}

/** Mix two colours in OKLab space. t=0 returns a, t=1 returns b. */
export function mix(a: string, b: string, t: number): string {
  const ca = hexToOklch(a), cb = hexToOklch(b);
  // Interpolate through Lab, not LCH, so a near-neutral endpoint does not
  // drag the hue around the wheel.
  const A1 = ca.C * Math.cos((ca.h * Math.PI) / 180);
  const B1 = ca.C * Math.sin((ca.h * Math.PI) / 180);
  const A2 = cb.C * Math.cos((cb.h * Math.PI) / 180);
  const B2 = cb.C * Math.sin((cb.h * Math.PI) / 180);
  const L = ca.L + (cb.L - ca.L) * t;
  const A = A1 + (A2 - A1) * t;
  const B = B1 + (B2 - B1) * t;
  const C = Math.sqrt(A * A + B * B);
  let h = (Math.atan2(B, A) * 180) / Math.PI;
  if (h < 0) h += 360;
  return oklchToHex({ L, C, h });
}
