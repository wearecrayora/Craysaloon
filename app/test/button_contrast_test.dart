import 'dart:math' as math;

import 'package:craysalon/core/theme/brand_theme.dart';
import 'package:craysalon/core/theme/brand_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cray_api.dart';

/// Every button's words against every colour they can sit on (23 Oct 2026):
/// the domed primary at its lightest top and darkest foot, the raised
/// secondary, the soft tonal one, a tile's icon on its key, the chosen tab -
/// for the three test brands (the default teal, a dark navy, a pale yellow),
/// light and dark. The screen sweep measures the rendered screens too; this
/// names the pair that failed, so a bad token is found at its source.
void main() {
  double luminance(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  final brands = {
    'teal': publishedBranding(),
    'navy': publishedBranding(
      primaryLight: '#1e2a5a',
      primaryDark: '#8fa4f0',
      lightColors: const {
        'onPrimary': '#ffffff',
        'primaryContainer': '#dde3f7',
        'onPrimaryContainer': '#121a3a',
        'brandInk': '#1e2a5a',
      },
      darkColors: const {
        'onPrimary': '#1a1a19',
        'primaryContainer': '#1d2547',
        'onPrimaryContainer': '#c9d3fa',
        'brandInk': '#8fa4f0',
      },
    ),
    'pale': publishedBranding(
      primaryLight: '#f2c94c',
      primaryDark: '#f2c94c',
      lightColors: const {
        'onPrimary': '#1a1a19',
        'primaryContainer': '#fbf0cc',
        'onPrimaryContainer': '#4a3800',
        'brandInk': '#6b5200',
      },
      darkColors: const {
        'onPrimary': '#1a1a19',
        'primaryContainer': '#3d3210',
        'onPrimaryContainer': '#f7e3a3',
        'brandInk': '#f2c94c',
      },
    ),
  };

  for (final MapEntry(key: name, value: doc) in brands.entries) {
    for (final brightness in Brightness.values) {
      test('$name, ${brightness.name}: every button reads', () {
        final t = BrandTokens.fromPublished(doc, brightness: brightness)!;
        final (top, foot) = buttonDome(t);
        final pairs = <String, (Color, Color, double)>{
          // Text: 4.5:1.
          'primary button label on its lightest top': (t.onPrimary, top, 4.5),
          'primary button label on its darkest foot': (t.onPrimary, foot, 4.5),
          'secondary (raised) button label': (t.brandInk, t.glassCard, 4.5),
          'secondary button label on the raised top': (t.brandInk, t.cardTop, 4.5),
          'tonal button / greeting card text': (t.onPrimaryContainer, t.primaryContainer, 4.5),
          'text button / link on a card': (t.brandInk, t.glassCard, 4.5),
          'chosen tab label': (t.textPrimary, t.glassBar, 4.5),
          'other tab labels': (t.textSecondary, t.glassBar, 4.5),
          'placeholder in a recessed field': (t.textMuted, t.sunken, 4.5),
          'text in a recessed field': (t.textPrimary, t.sunken, 4.5),
          // Icons and boundaries: 3:1 (WCAG 1.4.11).
          'tile icon on its key': (t.brandInk, t.cardTop, 3),
          'menu icon in its well': (t.brandInk, t.sunken, 3),
          'chosen tab icon in its well': (t.onPrimaryContainer, t.primaryContainer, 3),
        };
        final failures = [
          for (final MapEntry(key: what, value: (fg, bg, need)) in pairs.entries)
            if (contrast(fg, bg) < need)
              '$what: ${contrast(fg, bg).toStringAsFixed(2)}:1, needs $need:1',
        ];
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  }
}
