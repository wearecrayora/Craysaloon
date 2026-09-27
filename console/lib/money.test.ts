import { describe, expect, it } from 'vitest';

import { formatPaise, parseRupees } from './money';

/**
 * The console types prices, setup fees and the balance a customer is told they
 * are leaving behind. Every one of those is a number somebody reads out loud, so
 * these are the cases that matter rather than a coverage exercise.
 */
describe('parseRupees', () => {
  it('reads what an operator actually types', () => {
    expect(parseRupees('400')).toBe(40000);
    expect(parseRupees('400.5')).toBe(40050);
    expect(parseRupees('400.50')).toBe(40050);
    expect(parseRupees('₹1,200')).toBe(120000);
    expect(parseRupees(' 550 ')).toBe(55000);
    expect(parseRupees('0')).toBe(0);
  });

  it('is integer arithmetic, not Number(x) * 100', () => {
    // The values that expose float parsing: Number('400.35') * 100 is
    // 40034.999999999996, and Number('8.3') * 100 is 829.9999999999999.
    expect(parseRupees('400.35')).toBe(40035);
    expect(parseRupees('8.3')).toBe(830);
    expect(parseRupees('19.99')).toBe(1999);
  });

  it('refuses anything that is not an amount, rather than guessing', () => {
    expect(parseRupees('')).toBeNull();
    expect(parseRupees('abc')).toBeNull();
    expect(parseRupees('4,00,0x')).toBeNull();
    expect(parseRupees(null)).toBeNull();
    expect(parseRupees(undefined)).toBeNull();
    // Three decimal places is a typo, not a price. Truncating it silently would
    // charge a different number than the one on screen.
    expect(parseRupees('400.355')).toBeNull();
    // Negative prices are not a thing an operator means to type.
    expect(parseRupees('-400')).toBeNull();
  });
});

describe('formatPaise', () => {
  it('groups the Indian way', () => {
    expect(formatPaise(12050000)).toBe('₹1,20,500');
    expect(formatPaise(100000000)).toBe('₹10,00,000');
    expect(formatPaise(100000)).toBe('₹1,000');
  });

  it('shows paise only when there are any', () => {
    expect(formatPaise(55000)).toBe('₹550');
    expect(formatPaise(55050)).toBe('₹550.50');
    expect(formatPaise(55005)).toBe('₹550.05');
  });

  it('accepts the string form a Postgres bigint arrives as', () => {
    expect(formatPaise('12050000')).toBe('₹1,20,500');
    expect(formatPaise('0')).toBe('₹0');
  });

  it('has something honest to show for nothing', () => {
    expect(formatPaise(null)).toBe('—');
    expect(formatPaise(undefined)).toBe('—');
    expect(formatPaise('')).toBe('—');
    expect(formatPaise('not a number')).toBe('—');
  });

  it('shows a reversal as negative rather than as a positive in red', () => {
    expect(formatPaise(-55000)).toBe('-₹550');
  });

  it('round-trips with the parser', () => {
    for (const typed of ['400', '400.50', '1,20,500', '0.05']) {
      const paise = parseRupees(typed);
      expect(paise).not.toBeNull();
      expect(parseRupees(formatPaise(paise!))).toBe(paise);
    }
  });
});
