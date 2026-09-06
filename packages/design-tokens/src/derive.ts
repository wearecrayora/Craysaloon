// Publish-time derivation. The operator enters at most four colours;
// everything else is computed here (DESIGN.md 3.3).
//
// An operator choosing twelve colours is an operator choosing twelve
// accessibility failures. So they do not get to.

import { contrast, hexToOklch, mix, withLightness } from "./color.js";
import {
  CHART, CONTRAST_MIN, DEVANAGARI_LINE_HEIGHT_BONUS, MOTION, SPACING, STATUS, SURFACE,
} from "./fixed.js";
import type { BrandInput, Mode, ResolvedTokens } from "./schema.js";
import type { Mode as _M } from "./fixed.js";

/** Black or white, whichever reaches 4.5:1. Never chosen by a human. */
export function deriveOnColor(bg: string): string | null {
  const white = contrast(bg, "#ffffff");
  const black = contrast(bg, "#1a1a19");
  const best = white >= black ? "#ffffff" : "#1a1a19";
  const ratio = Math.max(white, black);
  return ratio >= CONTRAST_MIN.bodyText ? best : null;
}

/**
 * The brand hue, pushed in lightness until it is legible as text on the
 * surface. Light mode darkens, dark mode lightens.
 * Returns null if the hue cannot reach 4.5:1 at any lightness.
 */
export function deriveBrandInk(primary: string, surface: string, mode: Mode): string | null {
  if (contrast(primary, surface) >= CONTRAST_MIN.bodyText) return primary;
  const { L } = hexToOklch(primary);
  const step = mode === "light" ? -0.01 : 0.01;
  let l = L;
  for (let i = 0; i < 100; i++) {
    l += step;
    if (l <= 0 || l >= 1) break;
    const candidate = withLightness(primary, l);
    if (contrast(candidate, surface) >= CONTRAST_MIN.bodyText) return candidate;
  }
  return null;
}

/** Clamp the operator's radius and derive the rest (DESIGN.md 3.3). */
export function deriveRadius(input: number) {
  const base = Math.max(0, Math.min(24, Math.round(input)));
  return {
    base,
    chip: Math.max(6, Math.min(12, Math.round(base / 2))),
    sheet: Math.round(base * 1.5),
    pill: 999,
  };
}

export function resolveTokens(input: BrandInput, mode: Mode): ResolvedTokens {
  const s = SURFACE[mode];
  const brand = input.brand[mode];
  const chart = CHART[mode];

  const primaryContainer = mix(brand.primary, s.surface, mode === "light" ? 0.86 : 0.78);
  const brandInk = deriveBrandInk(brand.primary, s.surface, mode);

  return {
    version: input.version,
    displayName: input.displayName,
    mode,
    color: {
      primary: brand.primary,
      onPrimary: deriveOnColor(brand.primary) ?? "#ffffff",
      primaryContainer,
      onPrimaryContainer: deriveBrandInk(brand.primary, primaryContainer, mode) ?? s.textPrimary,
      accent: brand.accent,
      onAccent: deriveOnColor(brand.accent) ?? "#1a1a19",
      brandInk: brandInk ?? s.textPrimary,
      surface: s.surface,
      surfaceAlt: s.surfaceAlt,
      surfaceSunken: s.surfaceSunken,
      border: s.border,
      borderStrong: s.borderStrong,
      divider: s.divider,
      textPrimary: s.textPrimary,
      textSecondary: s.textSecondary,
      textMuted: s.textMuted,
      overlay: s.overlay,
      ...STATUS,
    },
    chart: {
      series: [chart.series1, chart.series2, chart.series3],
      gridline: chart.gridline,
      surface: chart.surface,
      sequential: CHART.sequential,
      diverging: {
        low: CHART.diverging.low,
        mid: mode === "light" ? CHART.diverging.midLight : CHART.diverging.midDark,
        high: CHART.diverging.high,
      },
      maxSeries: CHART.maxSeries,
    },
    typography: {
      ...input.typography,
      lineHeightBonus:
        input.typography.script === "devanagari" ? DEVANAGARI_LINE_HEIGHT_BONUS : 0,
    },
    radius: deriveRadius(input.shape.radius),
    spacing: SPACING,
    motion: MOTION,
  };
}
