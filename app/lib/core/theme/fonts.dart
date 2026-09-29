import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';

/// The salon's fonts, actually loaded.
///
/// Until 29 Sep 2026 the app NAMED each salon's heading and body family and
/// never loaded either, so every salon rendered in the phone's own font. The
/// console only offers families from the curated Google Fonts allow-list
/// (DESIGN 5.4), so google_fonts can fetch and cache them. First paint is never
/// blocked on it (DESIGN 5.4, RULES 8.5): text renders in the fallback and
/// swaps when the font arrives, and a family that cannot be loaded simply stays
/// on the fallback.
String fontFamilyFor(String family) {
  if (family.isEmpty || _underTest) return family;
  try {
    return GoogleFonts.getFont(family).fontFamily ?? family;
  } catch (_) {
    return family;
  }
}

/// Devanagari coverage whatever the salon picked: the fallback the text theme
/// reaches for when a glyph is missing (DESIGN 5.3).
List<String> get devanagariFallback {
  if (_underTest) return const ['Noto Sans Devanagari'];
  try {
    return [GoogleFonts.notoSansDevanagari().fontFamily ?? 'Noto Sans Devanagari'];
  } catch (_) {
    return const ['Noto Sans Devanagari'];
  }
}

/// Widget tests run offline and must not start font downloads.
final bool _underTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
