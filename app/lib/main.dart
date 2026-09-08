import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/observability/sentry_setup.dart';
import 'core/push/push_setup.dart';
import 'l10n/app_localizations.dart';

/// M0 scaffold.
///
/// The gate for this milestone is narrow and specific: the app boots and
/// renders in en / hi / hi_Latn (PHASES.md M0). There is deliberately no
/// product content here yet - screens arrive from M4 onward, and the theme
/// becomes salon-driven at M4 (DESIGN.md 3).
Future<void> main() async {
  // Sentry wraps the app when a DSN is configured, and is a no-op when it is
  // not. Observability is never a boot dependency (core/observability).
  await runWithObservability(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Push is initialised but not yet used: the ladder is M8. Like Sentry, a
    // missing configuration disables it rather than stopping the app.
    await Push.init();
    runApp(const ProviderScope(child: CraySalonApp()));
  });
}

/// Hinglish is a SCRIPT variant, not a country variant: it must be built with
/// `Locale.fromSubtags(scriptCode: 'Latn')`. `Locale('hi', 'Latn')` silently
/// makes 'Latn' a country code and never matches (DESIGN.md 5.3).
final kEnglish = const Locale('en');
final kHindi = const Locale('hi');
final kHinglish = Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn');

/// The locale the scaffold is previewing. Replaced at M4 by
/// customer.language ?? salon.default_language ?? 'en' (DESIGN.md 12.5).
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => kEnglish;

  void select(Locale locale) => state = locale;
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class CraySalonApp extends ConsumerWidget {
  const CraySalonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) => AppL10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: const LocaleProbe(),
    );
  }
}

/// Proves the M0 gate by eye: every supported locale, showing the strings that
/// exercise the hard parts - Devanagari metrics and the longest locale.
class LocaleProbe extends ConsumerWidget {
  const LocaleProbe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final current = ref.watch(localeProvider);

    // Not const: Locale overrides ==, so it cannot be a const map key.
    final labels = <Locale, String>{
      kEnglish: 'English',
      kHindi: 'Devanagari',
      kHinglish: 'Hinglish (longest)',
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: ListView(
          // 16dp screen padding - the only permitted value here (DESIGN.md 4.1).
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<Locale>(
              segments: [
                for (final entry in labels.entries)
                  ButtonSegment(
                    value: entry.key,
                    label: Text(entry.key.toLanguageTag()),
                  ),
              ],
              selected: {current},
              onSelectionChanged: (selection) =>
                  ref.read(localeProvider.notifier).select(selection.first),
            ),
            const SizedBox(height: 24),
            Text(
              labels[current] ?? current.toLanguageTag(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            _Line(l10n.joinTitle),
            _Line(l10n.joinScanQr),
            _Line(l10n.joinEnterCode),
            _Line(l10n.joinConfirmTitle('Studio Nine Salon')),
            _Line(l10n.joinAlreadyBound),
            _Line(l10n.walletBalance),
            _Line(l10n.walletOnlyAtSalon('Studio Nine Salon')),
            _Line(l10n.addMoneyPaidNeverExpires),
            _Line(l10n.markComplete),
            _Line(l10n.offlineBanner),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
