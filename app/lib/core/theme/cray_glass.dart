import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// The tactile chassis (DESIGN 3.5), carried on the theme so any widget can
/// reach it with `CrayGlass.of(context)`. Named for the glass it replaced, so
/// every screen kept its roles. Values come from [BrandTokens] - this file
/// names no colour of its own (GATE-2).
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
    required this.ink,
    required this.success,
    required this.cardTop,
    required this.highlight,
    required this.sunken,
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
        ink: t.brandInk,
        success: t.success,
        cardTop: t.cardTop,
        highlight: t.raisedHighlight,
        sunken: t.sunken,
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

  /// Brand-coloured TEXT: the brand's ink, computed at publish to clear 4.5:1
  /// on the surface. `primary` is for fills; text in `primary` is not proven.
  final Color ink;

  /// The fixed status green - never themed (DESIGN 3.4).
  final Color success;

  /// The top of a raised face, lighter than [card] - the dome.
  final Color cardTop;

  /// The light on a raised surface's top-left edge.
  final Color highlight;

  /// A recessed well or field.
  final Color sunken;

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
      ink: theme.colorScheme.primary,
      success: theme.colorScheme.primary,
      cardTop: s,
      highlight: Colors.transparent,
      sunken: theme.colorScheme.surfaceContainerHighest,
    );
  }

  /// A raised surface, lit from the top-left: a soft shadow down and to the
  /// right, a glow of light up and to the left.
  List<BoxShadow> get shadows => [
        BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(4, 6)),
        BoxShadow(color: highlight, blurRadius: 12, offset: const Offset(-4, -4)),
      ];

  /// The same surface pressed in: the shadows close up almost to nothing.
  List<BoxShadow> get pressedShadows => [
        BoxShadow(color: shadow, blurRadius: 4, offset: const Offset(1, 1)),
      ];

  /// A raised face: lighter at the top, as a domed key catches the light.
  Gradient get face => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cardTop, card],
      );

  /// A face pressed in: the light moves to the bottom.
  Gradient get pressedFace => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [sunken, card],
      );

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
      ink: c(ink, other.ink),
      success: c(success, other.success),
      cardTop: c(cardTop, other.cardTop),
      highlight: c(highlight, other.highlight),
      sunken: c(sunken, other.sunken),
    );
  }
}
