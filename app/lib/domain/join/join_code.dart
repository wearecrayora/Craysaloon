/// The salon code, as a person actually types it.
///
/// The database normalises too (migration 0026) and is the authority. This
/// exists so the app can enable its own button and show the code back in
/// canonical form, not so it can decide what is valid.
class JoinCode {
  const JoinCode._(this.value);

  /// Always `CRAY-XXXXXX`.
  final String value;

  /// Six characters, no `0/O`, `1/I/L` - a printed code is read aloud and
  /// retyped, so the ambiguous pairs are simply not in the alphabet
  /// (`ARCHITECTURE.md` 5.6).
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// Accepts what phones and people produce: lower case, stray spaces, a
  /// missing hyphen, an EN-DASH substituted by a phone keyboard, or the
  /// six-character body on its own. Returns null when it is not a code - the
  /// app never guesses at a character outside the alphabet, because guessing
  /// would send someone to the wrong salon.
  static JoinCode? tryParse(String raw) {
    var s = raw.trim().toUpperCase();
    // Every dash a keyboard might produce, plus the space people type instead.
    s = s.replaceAll(RegExp(r'[\s‐-―−-]'), '');
    if (s.startsWith('CRAY')) s = s.substring(4);
    if (s.length != 6) return null;
    for (final c in s.split('')) {
      if (!alphabet.contains(c)) return null;
    }
    return JoinCode._('CRAY-$s');
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is JoinCode && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
