import 'dart:ui';

/// The still life's colours (DESIGN.md 3.5a). NEUTRAL by rule - never the
/// salon's brand: an ink for light mode, white for dark, and the white of a
/// catch-light. Their faintness is set by the painter, not here.
abstract final class StillLifePalette {
  /// A deep, slightly violet ink - reads as glass on the light mesh.
  static const Color inkLight = Color(0xFF1B1530);

  /// White - reads as frosted glass on the dark mesh.
  static const Color inkDark = Color(0xFFFFFFFF);

  /// The catch-light along an object's edge.
  static const Color shine = Color(0xFFFFFFFF);
}
