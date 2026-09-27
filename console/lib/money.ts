/**
 * Money, in one place.
 *
 * The console had grown two parsers and three formatters: `Math.round(Number(v)
 * * 100)` in the catalogue actions, an integer-safe one in the binding desk, and
 * three separate `toLocaleString` calls that disagreed about whether paise are
 * shown. That is how a price list and an invoice end up differing by a rupee.
 *
 * The rules, the same as the app's (`RULES.md` 5.1.2, `DESIGN.md` 6.1):
 *   * money is integer **paise** everywhere, never a float;
 *   * it is written with Indian digit grouping - ₹1,20,500, not ₹120,500;
 *   * paise are shown only when there are any.
 */

/**
 * "400", "400.5", "400.50", "₹1,200" -> paise. Null when it is not an amount.
 *
 * Parsed with integer arithmetic rather than `Number(x) * 100`, which is how
 * 400.35 becomes 40034.999999999996 and then depends on a rounding call to come
 * back. At most two decimal places: "400.355" is a typo, not a price, and
 * silently truncating it would charge someone a different number than they read.
 */
export function parseRupees(input: unknown): number | null {
  if (typeof input !== 'string' && typeof input !== 'number') return null;
  const text = String(input).replace(/[₹,\s]/g, '');
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(text);
  if (!match) return null;
  const fraction = (match[2] ?? '').padEnd(2, '0');
  return Number(match[1]) * 100 + Number(fraction);
}

/** Paise -> ₹1,20,500 / ₹550.50. Accepts the string form Postgres bigints arrive as. */
export function formatPaise(paise: number | string | null | undefined): string {
  if (paise === null || paise === undefined || paise === '') return '—';
  const value = typeof paise === 'string' ? Number(paise) : paise;
  if (!Number.isFinite(value)) return '—';

  const negative = value < 0;
  const absolute = Math.abs(Math.trunc(value));
  const whole = Math.trunc(absolute / 100);
  const fraction = absolute % 100;

  const digits = whole.toLocaleString('en-IN');
  const text =
    fraction === 0 ? `₹${digits}` : `₹${digits}.${String(fraction).padStart(2, '0')}`;

  return negative ? `-${text}` : text;
}
