import 'package:craysalon/domain/join/join_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// A salon code is printed on a counter card, read aloud across a till, and
/// retyped on a phone keyboard. These are the ways that actually goes wrong.
void main() {
  group('a code a person typed', () {
    test('canonical', () {
      expect(JoinCode.tryParse('CRAY-22335S')?.value, 'CRAY-22335S');
    });

    test('lower case and stray spaces still resolve', () {
      expect(JoinCode.tryParse('  cray-22335s ')?.value, 'CRAY-22335S');
    });

    test('a missing hyphen still resolves', () {
      expect(JoinCode.tryParse('CRAY22335S')?.value, 'CRAY-22335S');
    });

    test('a space in place of the hyphen still resolves', () {
      expect(JoinCode.tryParse('CRAY 22335S')?.value, 'CRAY-22335S');
    });

    test('an EN-DASH, as a phone keyboard substitutes it, still resolves', () {
      expect(JoinCode.tryParse('CRAY–22335S')?.value, 'CRAY-22335S');
    });

    test('the six-character body alone still resolves', () {
      expect(JoinCode.tryParse('22335s')?.value, 'CRAY-22335S');
    });
  });

  group('what is not a code', () {
    test('a character outside the alphabet is not guessed at', () {
      // O/0 and I/1/L are not in the alphabet precisely because they are
      // misread. Silently "correcting" O to 0 could send someone to a
      // different salon than the one on the card in front of them.
      expect(JoinCode.tryParse('CRAY-2233OS'), isNull);
      expect(JoinCode.tryParse('CRAY-2233L5'), isNull);
    });

    test('the wrong length', () {
      expect(JoinCode.tryParse('CRAY-2233'), isNull);
      expect(JoinCode.tryParse('CRAY-2233555'), isNull);
    });

    test('empty', () {
      expect(JoinCode.tryParse(''), isNull);
      expect(JoinCode.tryParse('   '), isNull);
    });

    test('the alphabet excludes every ambiguous character', () {
      for (final c in ['0', 'O', '1', 'I', 'L']) {
        expect(JoinCode.alphabet.contains(c), isFalse, reason: '$c must not be in the alphabet');
      }
      expect(JoinCode.alphabet.length, 31);
    });
  });
}
