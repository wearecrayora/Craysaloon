/**
 * What may leave the console in an error report (server/sentry.ts).
 *
 * Any run of six or more digits is removed: a phone number, an OTP, a bank or
 * UPI reference that reached an error message stops here. Capped at 500
 * characters so a message can never carry a dump.
 */
const DIGITS = /\d{6,}/g;

export function scrub(text: string): string {
  return text.replace(DIGITS, '[digits]').slice(0, 500);
}
