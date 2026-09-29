import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// The glass chassis, carried on the theme so any widget can reach it with
/// `CrayGlass.of(context)`. Values come from [BrandTokens] - this file names no
/// colour of its own (GATE-2).
@immutable
class CrayGlass extends ThemeExtension<CrayGlass> {
  const CrayGlass({
    required this.card,
    required this.bar,
    required this.sheet,
    required this.line,
    required this.shadow,
    required this.meshTop,
    required this.meshBottom,
    required this.primaryGlow,
    required this.accentGlow,
    required this.primaryLow,
    required this.radius,
    required this.radiusChip,
    required this.radiusSheet,
  });

  factory CrayGlass.fromTokens(BrandTokens t) => CrayGlass(
        card: t.glassCard,
        bar: t.glassBar,
        sheet: t.glassSheet,
        line: t.glassLine,
        shadow: t.glassShadow,
        meshTop: t.meshTop,
        meshBottom: t.meshBottom,
        primaryGlow: t.meshPrimaryGlow,
        accentGlow: t.meshAccentGlow,
        primaryLow: t.meshPrimaryLow,
        radius: t.radiusBase,
        radiusChip: t.radiusChip,
        radiusSheet: t.radiusSheet,
      );

  final Color card;
  final Color bar;
  final Color sheet;
  final Color line;
  final Color shadow;
  final Color meshTop;
  final Color meshBottom;
  final Color primaryGlow;
  final Color accentGlow;
  final Color primaryLow;
  final double radius;
  final double radiusChip;
  final double radiusSheet;

  /// Falls back to a transparent, square chassis in a theme built without the
  /// extension (a bare MaterialApp in a widget test), rather than throwing.
  static CrayGlass of(BuildContext context) =>
      Theme.of(context).extension<CrayGlass>() ?? _fallback(Theme.of(context));

  static CrayGlass _fallback(ThemeData theme) {
    final s = theme.colorScheme.surface;
    return CrayGlass(
      card: s,
      bar: s,
      sheet: s,
      line: theme.colorScheme.outlineVariant,
      shadow: Colors.transparent,
      meshTop: s,
      meshBottom: s,
      primaryGlow: s,
      accentGlow: s,
      primaryLow: s,
      radius: 12,
      radiusChip: 8,
      radiusSheet: 18,
    );
  }

  /// The soft shadow every glass surface shares.
  List<BoxShadow> get shadows => [
        BoxShadow(color: shadow, blurRadius: 28, offset: const Offset(0, 8)),
      ];

  @override
  CrayGlass copyWith() => this;

  @override
  CrayGlass lerp(ThemeExtension<CrayGlass>? other, double t) {
    if (other is! CrayGlass) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return CrayGlass(
      card: c(card, other.card),
      bar: c(bar, other.bar),
      sheet: c(sheet, other.sheet),
      line: c(line, other.line),
      shadow: c(shadow, other.shadow),
      meshTop: c(meshTop, other.meshTop),
      meshBottom: c(meshBottom, other.meshBottom),
      primaryGlow: c(primaryGlow, other.primaryGlow),
      accentGlow: c(accentGlow, other.accentGlow),
      primaryLow: c(primaryLow, other.primaryLow),
      radius: d(radius, other.radius),
      radiusChip: d(radiusChip, other.radiusChip),
      radiusSheet: d(radiusSheet, other.radiusSheet),
    );
  }
}
