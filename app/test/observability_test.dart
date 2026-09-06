import 'package:craysalon/core/observability/sentry_setup.dart';
import 'package:flutter_test/flutter_test.dart';

/// RULES.md 11.3: never log phone numbers, OTPs, tokens, secrets, or full
/// payment payloads.
///
/// Sentry collects breadcrumbs and exception text automatically, so the only
/// place this can be enforced is on the way out. A regression here is silent -
/// nothing breaks, customer phone numbers just start arriving in a third-party
/// system. Hence tests.
void main() {
  group('redaction', () {
    test('Indian mobile numbers, in every shape they arrive', () {
      const cases = [
        '9876543210',
        '+919876543210',
        '+91 9876543210',
        '+91-9876543210',
        '919876543210',
      ];
      for (final raw in cases) {
        final out = redactSensitive('OTP send failed for $raw');
        expect(out, isNot(contains('9876543210')), reason: 'leaked: $raw');
        expect(out, contains('[redacted]'));
      }
    });

    test('OTP codes of any length', () {
      for (final otp in ['1234', '48192', '481920', '12345678']) {
        expect(
          redactSensitive('code=$otp'),
          isNot(contains(otp)),
          reason: 'leaked OTP of length ${otp.length}',
        );
      }
    });

    test('Supabase keys, current and legacy', () {
      expect(
        redactSensitive('key sb_secret_FAKEFAKEFAKEFAKE0000'),
        isNot(contains('FAKEFAKEFAKEFAKE')),
      );
      expect(
        redactSensitive('anon sb_publishable_FAKEFAKEFAKE1111'),
        isNot(contains('FAKEFAKEFAKE1111')),
      );
      expect(
        redactSensitive(
          'jwt eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.sig-here',
        ),
        isNot(contains('eyJzdWIiOiIxMjMifQ')),
      );
    });

    test('Razorpay keys, live and test', () {
      expect(redactSensitive('rzp_live_AbCdEf123456'),
          isNot(contains('AbCdEf123456')));
      expect(redactSensitive('rzp_test_AbCdEf123456'),
          isNot(contains('AbCdEf123456')));
    });

    test('bearer tokens', () {
      final out = redactSensitive('Authorization: Bearer abc123DEF456ghi789');
      expect(out, isNot(contains('abc123DEF456ghi789')));
    });

    test('several secrets in one string are all removed', () {
      final out = redactSensitive(
        'user 9876543210 otp 481920 key sb_secret_ABCDEFGHIJ',
      );
      expect(out, isNot(contains('9876543210')));
      expect(out, isNot(contains('481920')));
      expect(out, isNot(contains('ABCDEFGHIJ')));
    });

    test('ordinary diagnostic text is left readable', () {
      const message = 'Booking failed: slot already taken for staff Suresh';
      expect(redactSensitive(message), message);
    });

    test('salon_id survives - it is what we triage on and is not personal', () {
      const uuid = 'a3f1c2d4-5b6e-7f80-91a2-b3c4d5e6f708';
      // A UUID has no 4-8 digit run bounded by word breaks, so it passes
      // through intact. Guards against over-broad redaction.
      expect(redactSensitive('salon $uuid'), contains(uuid));
    });
  });

  group('configuration', () {
    test('is disabled when no DSN is supplied, so the app still boots', () {
      // No --dart-define in the test harness, so this is the real default.
      expect(sentryDsn, isEmpty);
      expect(sentryEnabled, isFalse);
    });

    test('defaults to the development environment', () {
      expect(buildEnvironment, 'development');
    });

    test('runWithObservability runs the app when Sentry is off', () async {
      var ran = false;
      await runWithObservability(() async => ran = true);
      expect(ran, isTrue);
    });
  });
}
