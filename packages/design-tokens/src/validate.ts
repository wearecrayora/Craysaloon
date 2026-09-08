// The publish gate (DESIGN.md 3.3, ARCHITECTURE 14.2).
// Publish is BLOCKED on any failure. This is not advisory.

import { contrast } from "./color.js";
import { CONTRAST_MIN } from "./fixed.js";
import { deriveBrandInk, deriveOnColor, resolveTokens } from "./derive.js";
import type { BrandInput, GateFailure, GateResult } from "./schema.js";
import type { Mode } from "./fixed.js";

const HEX = /^#[0-9a-fA-F]{6}$/;

function checkMode(input: BrandInput, mode: Mode, failures: GateFailure[], warnings: GateFailure[]) {
  const brand = input.brand[mode];
  const t = resolveTokens(input, mode);
  const label = (s: string) => `${mode}.${s}`;

  // 1. onPrimary must be computable at 4.5:1.
  if (deriveOnColor(brand.primary) === null) {
    failures.push({
      rule: "onPrimary",
      detail: `${label("primary")} ${brand.primary}: neither white nor near-black reaches 4.5:1. Pick a primary further from mid-lightness.`,
      measured: Math.max(contrast(brand.primary, "#ffffff"), contrast(brand.primary, "#1a1a19")),
      required: CONTRAST_MIN.bodyText,
    });
  }

  // 2. onAccent must be computable at 4.5:1.
  if (deriveOnColor(brand.accent) === null) {
    failures.push({
      rule: "onAccent",
      detail: `${label("accent")} ${brand.accent}: no legible text colour at 4.5:1.`,
      required: CONTRAST_MIN.bodyText,
    });
  }

  // 3. brandInk must exist - the brand hue has to be usable as text somewhere.
  if (deriveBrandInk(brand.primary, t.color.surface, mode) === null) {
    failures.push({
      rule: "brandInk",
      detail: `${label("primary")} ${brand.primary}: cannot be darkened or lightened to 4.5:1 on the surface. Choose a more saturated or less pale hue.`,
      required: CONTRAST_MIN.bodyText,
    });
  }

  // 4. Fixed ink ramp must clear body text on the fixed surface. Guards the
  //    ramps themselves against a careless edit, not the operator.
  const bodyRatio = contrast(t.color.textPrimary, t.color.surface);
  if (bodyRatio < CONTRAST_MIN.bodyText) {
    failures.push({
      rule: "textPrimary", detail: label("textPrimary vs surface"),
      measured: bodyRatio, required: CONTRAST_MIN.bodyText,
    });
  }
  const secondaryRatio = contrast(t.color.textSecondary, t.color.surface);
  if (secondaryRatio < CONTRAST_MIN.bodyText) {
    failures.push({
      rule: "textSecondary", detail: label("textSecondary vs surface"),
      measured: secondaryRatio, required: CONTRAST_MIN.bodyText,
    });
  }

  // 5. Borders must be visible as UI at 3:1.
  const borderRatio = contrast(t.color.borderStrong, t.color.surface);
  if (borderRatio < CONTRAST_MIN.ui) {
    failures.push({
      rule: "borderStrong", detail: label("borderStrong vs surface"),
      measured: borderRatio, required: CONTRAST_MIN.ui,
    });
  }

  // 6. Advisory: a primary that is nearly the surface still passes the gate
  //    (buttons use onPrimary) but will read as a flat, brandless UI.
  const primaryOnSurface = contrast(brand.primary, t.color.surface);
  if (primaryOnSurface < CONTRAST_MIN.ui) {
    warnings.push({
      rule: "primaryVisibility",
      detail: `${label("primary")} is below 3:1 against the surface; filled controls will look washed out. brandInk is used for any text.`,
      measured: primaryOnSurface, required: CONTRAST_MIN.ui,
    });
  }
}

export function validateBranding(input: BrandInput): GateResult {
  const failures: GateFailure[] = [];
  const warnings: GateFailure[] = [];

  for (const [path, value] of [
    ["light.primary", input.brand?.light?.primary],
    ["light.accent", input.brand?.light?.accent],
    ["dark.primary", input.brand?.dark?.primary],
    ["dark.accent", input.brand?.dark?.accent],
  ] as const) {
    if (!value || !HEX.test(value)) {
      failures.push({ rule: "hex", detail: `brand.${path} is not a 6-digit hex colour: ${value}` });
    }
  }

  if (!input.displayName?.trim()) {
    failures.push({ rule: "displayName", detail: "displayName is required - every message renders it." });
  }
  if (!input.assets?.logo) {
    failures.push({ rule: "assets.logo", detail: "A logo is required; it is the app bar and the notification large icon." });
  }
  if (input.typography?.script !== "latin" && input.typography?.script !== "devanagari") {
    failures.push({ rule: "script", detail: "typography.script must be 'latin' or 'devanagari' (DESIGN.md 5.3)." });
  }

  if (failures.length === 0) {
    checkMode(input, "light", failures, warnings);
    checkMode(input, "dark", failures, warnings);
  }

  return { ok: failures.length === 0, failures, warnings };
}

/** Human-readable gate report for the console. */
export function formatGate(r: GateResult): string {
  const line = (f: GateFailure) =>
    `  ${f.rule.padEnd(18)} ${f.detail}` +
    (f.measured !== undefined ? ` (${f.measured.toFixed(2)}:1, need ${f.required}:1)` : "");
  const out: string[] = [];
  out.push(r.ok ? "PUBLISH ALLOWED" : "PUBLISH BLOCKED");
  if (r.failures.length) out.push("FAIL:", ...r.failures.map(line));
  if (r.warnings.length) out.push("WARN:", ...r.warnings.map(line));
  return out.join("\n");
}
