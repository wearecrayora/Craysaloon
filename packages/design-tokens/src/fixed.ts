// Tokens that NEVER vary per salon (DESIGN.md 3.1).
// A salon changes how the app feels. It never changes how it is read.

export type Mode = "light" | "dark";

/** Neutral surface and ink ramps. Slightly warm - never pure grey (DESIGN.md 14). */
export const SURFACE = {
  light: {
    surface: "#fcfcfb",
    surfaceAlt: "#f4f3f0",
    surfaceSunken: "#eceae5",
    border: "#dedcd6",
    borderStrong: "#8f8d85",
    divider: "#e7e5df",
    textPrimary: "#1a1a19",
    textSecondary: "#52514e",
    textMuted: "#6b6964",
    overlay: "rgba(26,26,25,0.45)",
  },
  dark: {
    surface: "#1a1a19",
    surfaceAlt: "#232320",
    surfaceSunken: "#121211",
    border: "#35342f",
    borderStrong: "#7d7b73",
    divider: "#2b2a26",
    textPrimary: "#ffffff",
    textSecondary: "#c3c2b7",
    textMuted: "#9d9b93",
    overlay: "rgba(0,0,0,0.60)",
  },
} as const;

/** Status. Fixed. A salon whose brand is red does not get a red "success". */
export const STATUS = {
  success: "#0ca30c",
  warning: "#fab219",
  danger: "#d03b3b",
  info: "#2a78d6",
} as const;

/**
 * Chart palette. Fixed across every salon (DESIGN.md 9.1).
 * A per-salon palette cannot be validated for colour-vision deficiency at scale.
 * Validated all-pairs in both modes: CVD dE 9.2 light / 9.4 dark (>=8),
 * normal-vision dE 24.0 light / 20.9 dark (>=15).
 */
export const CHART = {
  light: {
    series1: "#2a78d6",
    series2: "#eb6834",
    series3: "#1baf7a",
    gridline: "#e7e5df",
    surface: "#fcfcfb",
  },
  dark: {
    series1: "#3987e5",
    series2: "#d95926",
    series3: "#199e70",
    gridline: "#2b2a26",
    surface: "#1a1a19",
  },
  sequential: [
    "#cde2fb", "#b7d3f6", "#9ec5f4", "#86b6ef",
    "#6da7ec", "#5598e7", "#3987e5", "#2a78d6",
    "#256abf", "#1c5cab", "#184f95", "#104281",
  ],
  diverging: {
    low: "#2a78d6",
    midLight: "#f0efec",
    midDark: "#383835",
    high: "#d03b3b",
  },
  /** Three is the cap. A fourth series folds into "Other" or becomes small multiples. */
  maxSeries: 3,
} as const;

/** Spacing scale. No other value appears in the codebase (DESIGN.md 4.1). */
export const SPACING = [4, 8, 12, 16, 20, 24, 32, 40, 48, 64] as const;

/** Type scale. Only the family varies per salon (DESIGN.md 5.1). */
export const TYPE_SCALE = {
  display:    { size: 32, line: 38, weight: "heading" },
  h1:         { size: 24, line: 30, weight: "heading" },
  h2:         { size: 20, line: 26, weight: "heading" },
  h3:         { size: 17, line: 24, weight: 600 },
  body:       { size: 15, line: 22, weight: 400 },
  bodyStrong: { size: 15, line: 22, weight: 600 },
  caption:    { size: 13, line: 18, weight: 400 },
  micro:      { size: 11, line: 16, weight: 500 },
  moneyXL:    { size: 34, line: 38, weight: 600, tabular: true },
  moneyL:     { size: 22, line: 26, weight: 600, tabular: true },
  moneyM:     { size: 17, line: 22, weight: 600, tabular: true },
} as const;

/** Devanagari needs more vertical room; never tighten its tracking (DESIGN.md 5.3). */
export const DEVANAGARI_LINE_HEIGHT_BONUS = 2;

/** Motion. Fixed. No bounce, no elastic, ever (DESIGN.md 7.1). */
export const MOTION = {
  micro: 120,
  standard: 220,
  large: 280,
  exitFactor: 0.8,
  easeStandard: [0.2, 0.0, 0.0, 1.0],
  easeExit: [0.3, 0.0, 1.0, 1.0],
} as const;

export const CONTRAST_MIN = { bodyText: 4.5, largeText: 3.0, ui: 3.0 } as const;
export const TOUCH_TARGET_MIN_DP = 48;
export const MARK_COMPLETE_TARGET_DP = 56;
