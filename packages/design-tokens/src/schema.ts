// The branding document an operator produces in the console, and the
// resolved token set both the app and the console preview consume.
// DESIGN.md 3.2 is authoritative for this shape.

export type Script = "latin" | "devanagari";

/** What the operator actually enters. At most four colours (DESIGN.md 3.2). */
export interface BrandInput {
  version: number;
  displayName: string;
  brand: {
    light: { primary: string; accent: string };
    dark: { primary: string; accent: string };
  };
  typography: {
    heading: { family: string; weight: number };
    body: { family: string; weight: number };
    script: Script;
  };
  shape: { radius: number };
  assets: {
    logo: string;
    wordmark?: string;
    splash?: string;
    notificationLarge?: string;
  };
}

/** Everything the UI reads. Derived values are never entered by hand. */
export interface ResolvedTokens {
  version: number;
  displayName: string;
  mode: "light" | "dark";
  color: {
    primary: string;
    onPrimary: string;
    primaryContainer: string;
    onPrimaryContainer: string;
    accent: string;
    onAccent: string;
    brandInk: string;
    surface: string;
    surfaceAlt: string;
    surfaceSunken: string;
    border: string;
    borderStrong: string;
    divider: string;
    textPrimary: string;
    textSecondary: string;
    textMuted: string;
    overlay: string;
    success: string;
    warning: string;
    danger: string;
    info: string;
  };
  chart: {
    series: [string, string, string];
    gridline: string;
    surface: string;
    sequential: readonly string[];
    diverging: { low: string; mid: string; high: string };
    maxSeries: number;
  };
  typography: BrandInput["typography"] & { lineHeightBonus: number };
  radius: { base: number; chip: number; sheet: number; pill: number };
  spacing: readonly number[];
  motion: typeof import("./fixed.js").MOTION;
}

export interface GateFailure {
  rule: string;
  detail: string;
  measured?: number;
  required?: number;
}

export interface GateResult {
  ok: boolean;
  failures: GateFailure[];
  warnings: GateFailure[];
}
