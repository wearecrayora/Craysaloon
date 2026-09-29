import 'package:flutter/material.dart';

/// The salon's resolved design tokens.
///
/// **This layer reads values. It never derives them** (ADR-40). `onPrimary`,
/// `brandInk`, `primaryContainer` and the radius ladder are computed once, at
/// publish, by `packages/design-tokens`, and the published document carries the
/// resolved light and dark sets (migration 0037 refuses one that does not).
/// A Dart port of that maths would be a second implementation free to disagree
/// with the operator's preview - the exact failure ADR-22 exists to prevent.
///
/// This is also the only file permitted to name a colour literally
/// (`RULES.md` 12A.8 / GATE-2), and the only literals here are the neutral
/// default: what the app wears when it has no salon yet, or cannot reach one
/// (`DESIGN.md` 3.3 - never a half-themed screen, and never another salon's
/// branding).
@immutable
class BrandTokens {
  const BrandTokens({
    required this.displayName,
    required this.version,
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.onAccent,
    required this.brandInk,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.radiusBase,
    required this.radiusChip,
    required this.radiusSheet,
    required this.headingFamily,
    required this.bodyFamily,
    required this.headingWeight,
    required this.bodyWeight,
    required this.script,
    required this.lineHeightBonus,
  });

  /// The salon's name. Never translated, never abbreviated (`DESIGN.md` 2.1).
  final String displayName;

  /// `salon_branding.version`. Monotonic: a newer number means re-theme.
  final int version;

  final Brightness brightness;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color accent;
  final Color onAccent;

  /// The brand hue pushed until it is legible as TEXT on [surface]. Brand
  /// primary is never a text colour on an arbitrary surface (`DESIGN.md` 3.3).
  final Color brandInk;

  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Fixed for every salon. A salon whose brand is red does not get a red
  /// "success" (`DESIGN.md` 3.1).
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  final double radiusBase;
  final double radiusChip;
  final double radiusSheet;

  final String headingFamily;
  final String bodyFamily;
  final int headingWeight;
  final int bodyWeight;

  /// `latin` or `devanagari`.
  final String script;

  /// Extra line height for Devanagari, in dp. Resolved at publish; the app adds
  /// it rather than deciding it (`DESIGN.md` 5.3).
  final double lineHeightBonus;

  bool get isDevanagari => script == 'devanagari';

  // ---------------------------------------------------------------------------
  // The glass chassis (Claude Design, 29 Sep 2026; DESIGN.md 3.5).
  //
  // Frosted cards, bars and sheets over a soft colour mesh made from the
  // salon's OWN primary and accent. The translucent whites and darks are part
  // of the fixed chassis, like the surface ramp - only the mesh tint follows the
  // brand, and it is mixed far enough toward the base that text on it still
  // clears 4.5:1 (checked in test/glass_contrast_test.dart).
  // ---------------------------------------------------------------------------

  bool get _isLight => brightness == Brightness.light;

  /// A card: translucent enough for the mesh to show, opaque enough to read on.
  Color get glassCard => _isLight ? const Color(0x94FFFFFF) : const Color(0x8C2C1E24);

  /// App bar and bottom navigation, drawn over a blur.
  Color get glassBar => _isLight ? const Color(0x80FFFFFF) : const Color(0x801E1418);

  /// Bottom sheets: the most opaque glass, because money is read on them.
  Color get glassSheet => _isLight ? const Color(0xD1FFFAFA) : const Color(0xDB22161C);

  /// The bright hairline that makes glass read as glass.
  Color get glassLine => _isLight ? const Color(0xC7FFFFFF) : const Color(0x1FFFFFFF);

  /// Soft, brand-warm shadow under glass.
  Color get glassShadow => _isLight ? const Color(0x14783C46) : const Color(0x59000000);

  /// The mesh's base wash, top to bottom.
  Color get meshTop => _isLight ? const Color(0xFFFCF4F3) : const Color(0xFF1A1216);
  Color get meshBottom => _isLight ? const Color(0xFFF8E9E9) : const Color(0xFF120C0F);

  Color get _meshMixBase => _isLight ? const Color(0xFFFFFFFF) : const Color(0xFF140E11);

  /// The brand's two glows in the mesh, mixed toward the base (the design's
  /// `color-mix` values): primary top-left and bottom, accent top-right.
  Color get meshPrimaryGlow => Color.lerp(_meshMixBase, primary, _isLight ? 0.38 : 0.34)!;
  Color get meshAccentGlow => Color.lerp(_meshMixBase, accent, _isLight ? 0.55 : 0.22)!;
  Color get meshPrimaryLow => Color.lerp(_meshMixBase, primary, _isLight ? 0.26 : 0.22)!;

  /// Reads the published document. Returns null if it carries no resolved set
  /// for [brightness] - the caller then renders the neutral default rather than
  /// a half-themed screen.
  ///
  /// Unknown keys are ignored on purpose: the schema is versioned and
  /// backward-compatible, so a console that publishes more than this app
  /// understands must not break it (`ARCHITECTURE.md` 7.2).
  static BrandTokens? fromPublished(
    Map<String, Object?> document, {
    required Brightness brightness,
    int version = 0,
  }) {
    final resolved = _map(document['resolved']);
    final set = _map(resolved?[brightness == Brightness.dark ? 'dark' : 'light']);
    final color = _map(set?['color']);
    if (set == null || color == null) return null;

    final radius = _map(set['radius']) ?? const {};
    final type = _map(set['typography']) ?? const {};
    final fallback = neutral(brightness: brightness);

    Color pick(String key, Color orElse) => _color(color[key]) ?? orElse;

    final primary = _color(color['primary']);
    final surface = _color(color['surface']);
    final textPrimary = _color(color['textPrimary']);
    final onPrimary = _color(color['onPrimary']);
    // These four are what a screen cannot be drawn without. A document missing
    // any of them is not "mostly fine": it is unthemed.
    if (primary == null || surface == null || textPrimary == null || onPrimary == null) {
      return null;
    }

    return BrandTokens(
      displayName: (document['displayName'] as String?)?.trim().isNotEmpty == true
          ? (document['displayName']! as String).trim()
          : fallback.displayName,
      version: version,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: pick('primaryContainer', fallback.primaryContainer),
      onPrimaryContainer: pick('onPrimaryContainer', fallback.onPrimaryContainer),
      accent: pick('accent', primary),
      onAccent: pick('onAccent', onPrimary),
      brandInk: pick('brandInk', textPrimary),
      surface: surface,
      surfaceAlt: pick('surfaceAlt', fallback.surfaceAlt),
      surfaceSunken: pick('surfaceSunken', fallback.surfaceSunken),
      border: pick('border', fallback.border),
      borderStrong: pick('borderStrong', fallback.borderStrong),
      divider: pick('divider', fallback.divider),
      textPrimary: textPrimary,
      textSecondary: pick('textSecondary', fallback.textSecondary),
      textMuted: pick('textMuted', fallback.textMuted),
      // Status colours come from the fixed set, not from the document: a
      // published palette does not get to recolour "danger".
      success: fallback.success,
      warning: fallback.warning,
      danger: fallback.danger,
      info: fallback.info,
      radiusBase: _number(radius['base']) ?? fallback.radiusBase,
      radiusChip: _number(radius['chip']) ?? fallback.radiusChip,
      radiusSheet: _number(radius['sheet']) ?? fallback.radiusSheet,
      headingFamily: _family(type['heading']) ?? fallback.headingFamily,
      bodyFamily: _family(type['body']) ?? fallback.bodyFamily,
      headingWeight: _weight(type['heading']) ?? fallback.headingWeight,
      bodyWeight: _weight(type['body']) ?? fallback.bodyWeight,
      script: (type['script'] as String?) ?? fallback.script,
      lineHeightBonus: _number(type['lineHeightBonus']) ?? fallback.lineHeightBonus,
    );
  }

  /// Cray's own neutral. Used before a salon is known, and whenever branding
  /// cannot be read. Deliberately not derived from any salon.
  static BrandTokens neutral({required Brightness brightness, String? displayName}) {
    final dark = brightness == Brightness.dark;
    return BrandTokens(
      displayName: displayName ?? 'Cray Salon',
      version: 0,
      brightness: brightness,
      primary: dark ? const Color(0xFFD8D5CC) : const Color(0xFF3F3D39),
      onPrimary: dark ? const Color(0xFF1A1A19) : const Color(0xFFFFFFFF),
      primaryContainer: dark ? const Color(0xFF2E2D29) : const Color(0xFFE9E7E1),
      onPrimaryContainer: dark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A19),
      accent: dark ? const Color(0xFFD8D5CC) : const Color(0xFF3F3D39),
      onAccent: dark ? const Color(0xFF1A1A19) : const Color(0xFFFFFFFF),
      brandInk: dark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A19),
      // The neutral surface ramps, matching packages/design-tokens SURFACE.
      surface: dark ? const Color(0xFF1A1A19) : const Color(0xFFFCFCFB),
      surfaceAlt: dark ? const Color(0xFF232320) : const Color(0xFFF4F3F0),
      surfaceSunken: dark ? const Color(0xFF121211) : const Color(0xFFECEAE5),
      border: dark ? const Color(0xFF35342F) : const Color(0xFFDEDCD6),
      borderStrong: dark ? const Color(0xFF7D7B73) : const Color(0xFF8F8D85),
      divider: dark ? const Color(0xFF2B2A26) : const Color(0xFFE7E5DF),
      textPrimary: dark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A19),
      textSecondary: dark ? const Color(0xFFC3C2B7) : const Color(0xFF52514E),
      textMuted: dark ? const Color(0xFF9D9B93) : const Color(0xFF6B6964),
      // STATUS in packages/design-tokens. Identical in both modes, by design.
      success: const Color(0xFF0CA30C),
      warning: const Color(0xFFFAB219),
      danger: const Color(0xFFD03B3B),
      info: const Color(0xFF2A78D6),
      radiusBase: 12,
      radiusChip: 6,
      radiusSheet: 18,
      headingFamily: 'Inter',
      bodyFamily: 'Inter',
      headingWeight: 600,
      bodyWeight: 400,
      script: 'latin',
      lineHeightBonus: 0,
    );
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _family(Object? value) => _map(value)?['family'] as String?;

  static int? _weight(Object? value) => _number(_map(value)?['weight'])?.round();

  /// `#rgb`, `#rrggbb` or `#rrggbbaa`. Anything else is not a colour we will
  /// guess at: the caller falls back rather than painting something arbitrary.
  static Color? _color(Object? value) {
    if (value is! String) return null;
    final raw = value.trim().replaceFirst('#', '');
    final String hex;
    switch (raw.length) {
      case 3:
        hex = 'ff${raw.split('').map((c) => '$c$c').join()}';
      case 6:
        hex = 'ff$raw';
      case 8:
        // CSS publishes #rrggbbaa; Flutter wants aarrggbb.
        hex = raw.substring(6) + raw.substring(0, 6);
      default:
        return null;
    }
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
