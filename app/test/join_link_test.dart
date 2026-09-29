import 'package:craysalon/domain/join/join_code.dart';
import 'package:craysalon/domain/join/join_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// A QR is scanned in bad light, at an angle, from a sticker on a mirror, and
/// sometimes it is not our QR at all.
void main() {
  group('the printed link', () {
    test('the canonical form the console prints', () {
      expect(
        JoinLink.parse('https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S')?.value,
        'CRAY-22335S',
      );
    });

    test('and what the console prints is what we parse', () {
      final code = JoinCode.tryParse('CRAY-22335S')!;
      expect(JoinLink.parse(JoinLink.forCode(code))?.value, code.value);
    });

    test('a trailing slash, mixed-case host and extra segments still resolve', () {
      expect(JoinLink.parse('https://CraySalon-Join.CRAYORATECH.workers.dev/s/cray-22335s/')?.value, 'CRAY-22335S');
    });

    test('tracking parameters are ignored', () {
      expect(
        JoinLink.parse('https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?utm_source=poster')?.value,
        'CRAY-22335S',
      );
    });

    test('?code= - how the Play Install Referrer carries it through an install', () {
      expect(
        JoinLink.parse('https://craysalon-join.crayoratech.workers.dev/?code=CRAY-22335S')?.value,
        'CRAY-22335S',
      );
    });
  });

  group('a bare code', () {
    test('scanned from a hand-reprinted sticker', () {
      expect(JoinLink.parse('CRAY-22335S')?.value, 'CRAY-22335S');
      expect(JoinLink.parse('22335s')?.value, 'CRAY-22335S');
    });
  });

  group('what is not a salon code', () {
    test('someone else\'s QR', () {
      expect(JoinLink.parse('https://example.com/s/CRAY-22335S'), isNull);
      // A lookalike host is not ours either.
      expect(JoinLink.parse('https://craysalon-join.crayoratech.workers.dev.evil.test/s/CRAY-22335S'), isNull);
    });

    test('a wifi or vcard QR, which is most of what a camera meets', () {
      expect(JoinLink.parse('WIFI:S:SalonGuest;T:WPA;P:hunter2;;'), isNull);
      expect(JoinLink.parse('mailto:hello@example.com'), isNull);
      expect(JoinLink.parse(''), isNull);
    });

    test('our host, but not a code', () {
      expect(JoinLink.parse('https://craysalon-join.crayoratech.workers.dev/'), isNull);
      expect(JoinLink.parse('https://craysalon-join.crayoratech.workers.dev/s/NOTACODE1'), isNull);
    });
  });
}
