import { describe, expect, it } from 'vitest';
import { scrub } from './scrub';

describe('scrub', () => {
  it('removes a phone number, however it is written', () => {
    expect(scrub('no customer for 9876543210')).toBe('no customer for [digits]');
    expect(scrub('Key (phone)=(+919876543210) exists')).toBe('Key (phone)=(+[digits]) exists');
  });

  it('removes an OTP and a UTR', () => {
    expect(scrub('code 482193 rejected, UTR 412345678901')).toBe(
      'code [digits] rejected, UTR [digits]',
    );
  });

  it('keeps what an operator needs to act on', () => {
    expect(scrub('app_admin: a payment covers 1 to 24 months')).toBe(
      'app_admin: a payment covers 1 to 24 months',
    );
    expect(scrub('migration 0087 failed at 12:30')).toBe('migration 0087 failed at 12:30');
  });

  it('never carries a dump', () => {
    expect(scrub('x'.repeat(2000))).toHaveLength(500);
  });
});
