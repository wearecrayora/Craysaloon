import 'package:craysalon/core/theme/brand_theme.dart';
import 'package:craysalon/core/theme/brand_tokens.dart';
import 'package:craysalon/core/theme/cray_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cray_api.dart';

/// The app READS resolved tokens and derives nothing (ADR-40). These tests are
/// about the two ways that can go wrong: quietly deriving something anyway, and
/// half-theming a screen when the document cannot be read.
void main() {
  group('a published document', () {
    test('is read, not recomputed', () {
      final t = BrandTokens.fromPublished(
        publishedBranding(),
        brightness: Brightness.light,
        version: 3,
      )!;

      expect(t.displayName, 'Studio Nine Salon');
      expect(t.primary, const Color(0xFF1F6F5C));
      expect(t.onPrimary, const Color(0xFFFFFFFF));
      expect(t.brandInk, const Color(0xFF155447));
      // The radius ladder is published, not derived here.
      expect(t.radiusBase, 16);
      expect(t.radiusChip, 8);
      expect(t.version, 3);
    });

    test('dark mode comes from the same document', () {
      final t = BrandTokens.fromPublished(
        publishedBranding(),
        brightness: Brightness.dark,
      )!;
      expect(t.primary, const Color(0xFF3FBF9F));
      expect(t.surface, const Color(0xFF1A1A19));
      expect(t.textPrimary, const Color(0xFFFFFFFF));
    });

    test('cannot recolour status - a salon whose brand is red gets no red success', () {
      final t = BrandTokens.fromPublished(
        publishedBranding(),
        brightness: Brightness.light,
      )!;
      // The fixture tries to publish success #ff00ff and danger #00ff00.
      expect(t.success, const Color(0xFF0CA30C));
      expect(t.danger, const Color(0xFFD03B3B));
    });

    test('ignores keys it does not understand', () {
      final document = publishedBranding()..['somethingNewerThanThisApp'] = {'x': 1};
      expect(
        BrandTokens.fromPublished(document, brightness: Brightness.light),
        isNotNull,
      );
    });
  });

  group('when it cannot be themed, it falls back WHOLE', () {
    test('an unresolved document gives null, so the caller uses the neutral default', () {
      // What the console published before 0037: the operator's input only.
      final unresolved = {
        'displayName': 'Studio Nine Salon',
        'brand': {
          'light': {'primary': '#1f6f5c', 'accent': '#eb6834'},
        },
      };
      expect(BrandTokens.fromPublished(unresolved, brightness: Brightness.light), isNull);
    });

    test('a resolved set missing a colour the screen needs gives null', () {
      final document = publishedBranding();
      (((document['resolved']! as Map)['light']! as Map)['color']! as Map).remove('surface');
      expect(BrandTokens.fromPublished(document, brightness: Brightness.light), isNull);
    });

    test('the neutral default is Cray\'s own, never a salon\'s', () {
      final t = BrandTokens.neutral(brightness: Brightness.light);
      expect(t.displayName, 'Cray Salon');
      expect(t.primary, isNot(const Color(0xFF1F6F5C)));
      expect(t.version, 0);
    });
  });

  group('the theme built from them', () {
    test('carries the salon\'s colours into the scheme', () {
      final t = BrandTokens.fromPublished(publishedBranding(), brightness: Brightness.light)!;
      final theme = brandTheme(t);
      expect(theme.colorScheme.primary, const Color(0xFF1F6F5C));
      // Transparent on purpose: every page paints the glass chassis's mesh
      // beneath its scaffold (Claude Design, 29 Sep 2026; DESIGN 3.5).
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.extension<CrayGlass>(), isNotNull);
      // Never tint a surface with the brand colour (DESIGN 3.3).
      expect(theme.colorScheme.surface, t.surface);
    });

    // The mesh carries the brand's colour behind the screen, so it must stay
    // light enough (dark enough, in dark mode) that body text on it still
    // reads - headings sit directly on the mesh, not only on cards.
    for (final brightness in Brightness.values) {
      test('text on the mesh still clears 4.5:1 ($brightness)', () {
        final t = BrandTokens.fromPublished(publishedBranding(), brightness: brightness)!;
        for (final glow in [t.meshTop, t.meshBottom, t.meshPrimaryGlow, t.meshAccentGlow, t.meshPrimaryLow]) {
          final ratio = _contrast(t.textPrimary, glow);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'textPrimary on ${glow.toARGB32().toRadixString(16)} is ${ratio.toStringAsFixed(2)}:1');
        }
      });
    }

    test('Devanagari gets the extra line height and zero letter-spacing', () {
      final latin = brandTheme(
        BrandTokens.fromPublished(publishedBranding(), brightness: Brightness.light)!,
      );
      final devanagari = brandTheme(
        BrandTokens.fromPublished(
          publishedBranding(script: 'devanagari', lineHeightBonus: 2),
          brightness: Brightness.light,
        )!,
      );

      expect(
        devanagari.textTheme.bodyMedium!.height,
        greaterThan(latin.textTheme.bodyMedium!.height!),
      );
      expect(devanagari.textTheme.bodyMedium!.letterSpacing, 0.0);
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
