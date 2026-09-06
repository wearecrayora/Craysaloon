import { describe, expect, test } from "bun:test";
import {
  CHART, CONTRAST_MIN, SPACING, STATUS, SURFACE,
  contrast, deriveBrandInk, deriveOnColor, deriveRadius,
  hexToOklch, oklchToHex, resolveTokens, validateBranding,
} from "../src/index.js";
import type { BrandInput } from "../src/schema.js";

const brand = (light: string, dark: string, accentL = "#C8A24A", accentD = "#E3C378"): BrandInput => ({
  version: 1,
  displayName: "Studio Nine Salon",
  brand: { light: { primary: light, accent: accentL }, dark: { primary: dark, accent: accentD } },
  typography: {
    heading: { family: "Fraunces", weight: 600 },
    body: { family: "Inter Tight", weight: 400 },
    script: "latin",
  },
  shape: { radius: 14 },
  assets: { logo: "https://example.test/logo.png" },
});

describe("colour maths", () => {
  test("hex round-trips through OKLCH", () => {
    for (const hex of ["#1F6F5C", "#eb6834", "#fcfcfb", "#1a1a19", "#2a78d6"]) {
      expect(oklchToHex(hexToOklch(hex)).toLowerCase()).toBe(hex.toLowerCase());
    }
  });

  test("contrast matches known WCAG values", () => {
    expect(contrast("#000000", "#ffffff")).toBeCloseTo(21, 1);
    expect(contrast("#ffffff", "#ffffff")).toBeCloseTo(1, 5);
    // Order must not matter.
    expect(contrast("#1a1a19", "#fcfcfb")).toBeCloseTo(contrast("#fcfcfb", "#1a1a19"), 6);
  });
});

describe("fixed ramps are legible - guards the ramps, not the operator", () => {
  for (const mode of ["light", "dark"] as const) {
    const s = SURFACE[mode];
    test(`${mode}: textPrimary clears body text`, () => {
      expect(contrast(s.textPrimary, s.surface)).toBeGreaterThanOrEqual(CONTRAST_MIN.bodyText);
    });
    test(`${mode}: textSecondary clears body text`, () => {
      expect(contrast(s.textSecondary, s.surface)).toBeGreaterThanOrEqual(CONTRAST_MIN.bodyText);
    });
    test(`${mode}: borderStrong clears UI contrast`, () => {
      expect(contrast(s.borderStrong, s.surface)).toBeGreaterThanOrEqual(CONTRAST_MIN.ui);
    });
  }
});

describe("chart palette is capped and fixed", () => {
  test("three series, no more (DESIGN.md 9.1)", () => {
    expect(CHART.maxSeries).toBe(3);
    expect(Object.keys(CHART.light).filter((k) => k.startsWith("series")).length).toBe(3);
  });
  test("sequential ramp is monotonic in lightness", () => {
    const ls = CHART.sequential.map((h) => hexToOklch(h).L);
    for (let i = 1; i < ls.length; i++) expect(ls[i]).toBeLessThan(ls[i - 1]);
  });
  test("diverging midpoint is neutral, not a hue", () => {
    expect(hexToOklch(CHART.diverging.midLight).C).toBeLessThan(0.02);
    expect(hexToOklch(CHART.diverging.midDark).C).toBeLessThan(0.02);
  });
  test("status colours are not reused as series", () => {
    const series = [CHART.light.series1, CHART.light.series2, CHART.light.series3];
    for (const s of Object.values(STATUS)) {
      if (s === CHART.light.series1) continue; // info IS series1 by design
      expect(series).not.toContain(s);
    }
  });
});

describe("derivation", () => {
  test("onPrimary is computed, never chosen", () => {
    expect(deriveOnColor("#1F6F5C")).toBe("#ffffff");   // dark brand -> white text
    expect(deriveOnColor("#F5E9C8")).toBe("#1a1a19");   // pale brand -> dark text
  });

  test("a mid-lightness primary with no legible text colour is rejected", () => {
    // The real dead band is #777777-#818181: neither white (4.17:1) nor
    // near-black (4.17:1) reaches 4.5:1. Verified empirically, not guessed.
    expect(deriveOnColor("#7c7c7c")).toBeNull();
  });

  test("brandInk darkens a pale brand until it is readable as text", () => {
    const pale = "#F5E9C8";
    const surface = SURFACE.light.surface;
    expect(contrast(pale, surface)).toBeLessThan(CONTRAST_MIN.bodyText);
    const ink = deriveBrandInk(pale, surface, "light")!;
    expect(ink).not.toBeNull();
    expect(contrast(ink, surface)).toBeGreaterThanOrEqual(CONTRAST_MIN.bodyText);
    // Hue is preserved - it is still recognisably the brand.
    expect(Math.abs(hexToOklch(ink).h - hexToOklch(pale).h)).toBeLessThan(12);
  });

  test("brandInk lightens in dark mode", () => {
    const deep = "#10241F";
    const ink = deriveBrandInk(deep, SURFACE.dark.surface, "dark")!;
    expect(hexToOklch(ink).L).toBeGreaterThan(hexToOklch(deep).L);
    expect(contrast(ink, SURFACE.dark.surface)).toBeGreaterThanOrEqual(CONTRAST_MIN.bodyText);
  });

  test("radius is clamped and derived", () => {
    expect(deriveRadius(14)).toEqual({ base: 14, chip: 7, sheet: 21, pill: 999 });
    expect(deriveRadius(999).base).toBe(24);
    expect(deriveRadius(-5).base).toBe(0);
    expect(deriveRadius(0).chip).toBe(6);   // clamped to the floor
    expect(deriveRadius(40).chip).toBe(12); // clamped to the ceiling
  });

  test("resolved tokens carry fixed status and chart colours unchanged", () => {
    const t = resolveTokens(brand("#1F6F5C", "#7FD3BC"), "light");
    expect(t.color.success).toBe(STATUS.success);
    expect(t.chart.series[0]).toBe(CHART.light.series1);
    expect(t.spacing).toEqual(SPACING);
  });

  test("devanagari gets the line-height bonus, latin does not", () => {
    const latin = resolveTokens(brand("#1F6F5C", "#7FD3BC"), "light");
    expect(latin.typography.lineHeightBonus).toBe(0);
    const dev = brand("#1F6F5C", "#7FD3BC");
    dev.typography.script = "devanagari";
    expect(resolveTokens(dev, "light").typography.lineHeightBonus).toBe(2);
  });
});

describe("publish gate", () => {
  test("a sane brand passes", () => {
    const r = validateBranding(brand("#1F6F5C", "#7FD3BC"));
    expect(r.ok).toBe(true);
    expect(r.failures).toEqual([]);
  });

  test("a pale brand still passes - the system protects the reader", () => {
    // The salon that picks pale-yellow. onPrimary goes dark, brandInk darkens.
    const r = validateBranding(brand("#F5E9C8", "#F5E9C8"));
    expect(r.ok).toBe(true);
    expect(r.warnings.some((w) => w.rule === "primaryVisibility")).toBe(true);
  });

  test("a mid-grey brand is BLOCKED", () => {
    const r = validateBranding(brand("#7c7c7c", "#7c7c7c"));
    expect(r.ok).toBe(false);
    expect(r.failures.some((f) => f.rule === "onPrimary")).toBe(true);
  });

  test("a malformed hex is blocked before any colour maths runs", () => {
    const b = brand("#1F6F5C", "#7FD3BC");
    (b.brand.light as any).primary = "teal";
    const r = validateBranding(b);
    expect(r.ok).toBe(false);
    expect(r.failures[0].rule).toBe("hex");
  });

  test("a missing display name is blocked - every message renders it", () => {
    const b = brand("#1F6F5C", "#7FD3BC");
    b.displayName = "  ";
    expect(validateBranding(b).ok).toBe(false);
  });

  test("a missing logo is blocked", () => {
    const b = brand("#1F6F5C", "#7FD3BC");
    (b.assets as any).logo = "";
    expect(validateBranding(b).ok).toBe(false);
  });
});
