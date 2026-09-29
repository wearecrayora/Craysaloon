import 'package:flutter/material.dart';

/// The chart palette - FIXED across every salon (DESIGN 9.1).
///
/// **Charts are brand-neutral, and that is a rule rather than a preference.** A
/// per-salon palette cannot be validated for colour-vision deficiency at scale:
/// one salon's brand hues will collide under deuteranopia, and we would ship an
/// unreadable chart to that salon and never hear about it. So the marks inside
/// a chart never wear the salon's colour; the salon is carried by the chrome
/// around it.
///
/// Validated: worst all-pairs CVD ΔE 9.2 light / 9.4 dark (≥8 target). **Three
/// is the cap** - a fourth series folds into "Other" or becomes small multiples.
/// Do not add a fourth hue here.
///
/// These live in `core/theme` because GATE-2 forbids a raw colour literal
/// anywhere else, and a chart colour chosen in a widget is exactly how a
/// fourth, unvalidated hue gets in.
abstract final class ChartPalette {
  /// Wallet customers in the cohort chart (DESIGN 9.4 - fixed assignment).
  static Color series1(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);

  /// No-wallet customers in the cohort chart.
  static Color series2(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFD95926) : const Color(0xFFEB6834);

  static Color series3(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF199E70) : const Color(0xFF1BAF7A);

  /// Recessive, never full-strength ink (DESIGN 9.3).
  static Color gridline(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF383835) : const Color(0xFFE3E3DE);

  /// STATUS colours are reserved: never a series, and always shipped with an
  /// icon and a label (DESIGN 9.1). Never themed either.
  static const warning = Color(0xFFFAB219);
  static const danger = Color(0xFFD03B3B);
  static const success = Color(0xFF0CA30C);
}
