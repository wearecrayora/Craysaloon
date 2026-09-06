import 'package:craysalon/l10n/app_localizations.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The M0 gate: the app boots and renders correctly in en / hi / hi_Latn.
///
/// Eyeballing three locales on an emulator proves it once. This proves it on
/// every commit, and catches the specific failure that is easy to reintroduce:
/// hi_Latn silently falling back to Hindi.
void main() {
  Future<void> pumpAt(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWith(() => _FixedLocale(locale)),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('every supported locale renders', () {
    testWidgets('en', (tester) async {
      await pumpAt(tester, kEnglish);
      expect(find.text('Find your salon'), findsOneWidget);
      expect(find.text('Money you pay never expires.'), findsOneWidget);
    });

    testWidgets('hi renders Devanagari, not a fallback to English',
        (tester) async {
      await pumpAt(tester, kHindi);
      expect(find.text('अपना सैलॉन खोजें'), findsOneWidget);
      // If the delegate silently fell back, the English string would be here.
      expect(find.text('Find your salon'), findsNothing);
    });

    testWidgets('hi_Latn resolves to Hinglish, NOT to Hindi', (tester) async {
      await pumpAt(tester, kHinglish);
      expect(find.text('Apna salon dhundhein'), findsOneWidget);
      // The trap this test exists for: Locale('hi','Latn') sets a COUNTRY
      // code, never matches the script variant, and falls back to Devanagari.
      expect(find.text('अपना सैलॉन खोजें'), findsNothing);
    });
  });

  group('locale plumbing', () {
    test('hi_Latn is a script subtag, not a country subtag', () {
      expect(kHinglish.scriptCode, 'Latn');
      expect(kHinglish.countryCode, isNull);
      expect(kHinglish.toLanguageTag(), 'hi-Latn');
    });

    test('all three locales are actually supported by the delegate', () {
      for (final locale in [kEnglish, kHindi, kHinglish]) {
        expect(
          AppL10n.supportedLocales.contains(locale),
          isTrue,
          reason: '$locale missing from supportedLocales',
        );
      }
    });

    test('every locale resolves to its own translation set', () {
      // Distinct instances - proves no locale is quietly aliased to another.
      final en = lookupAppL10n(kEnglish);
      final hi = lookupAppL10n(kHindi);
      final hinglish = lookupAppL10n(kHinglish);
      expect(en.joinTitle, isNot(hi.joinTitle));
      expect(hi.joinTitle, isNot(hinglish.joinTitle));
      expect(en.joinTitle, isNot(hinglish.joinTitle));
    });

    test('placeholders interpolate, and the salon name is never translated',
        () {
      const salon = 'Studio Nine Salon';
      for (final l10n in [
        lookupAppL10n(kEnglish),
        lookupAppL10n(kHindi),
        lookupAppL10n(kHinglish),
      ]) {
        expect(l10n.joinConfirmTitle(salon), contains(salon));
        expect(l10n.walletOnlyAtSalon(salon), contains(salon));
      }
    });

    test('the already-bound message never names another salon (RULES 4.4)', () {
      for (final l10n in [
        lookupAppL10n(kEnglish),
        lookupAppL10n(kHindi),
        lookupAppL10n(kHinglish),
      ]) {
        // It takes no arguments at all - there is no way to leak a salon name.
        expect(l10n.joinAlreadyBound, isNotEmpty);
      }
    });
  });
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._locale);
  final Locale _locale;

  @override
  Locale build() => _locale;
}
