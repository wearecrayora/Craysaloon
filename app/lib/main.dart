import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/observability/sentry_setup.dart';
import 'core/push/push_setup.dart';
import 'core/theme/brand_theme.dart';
import 'core/theme/brand_tokens.dart';
import 'data/local/branding_store.dart';
import 'data/local/device_key.dart';
import 'data/remote/supabase_cray_api.dart';
import 'features/join/join_controller.dart';
import 'features/join/join_screen.dart';
import 'features/salon/salon_home.dart';
import 'l10n/app_localizations.dart';

/// Configuration arrives with `--dart-define`, never from a file in the repo.
/// The publishable key is designed to ship in a client; the secret key never
/// touches this codebase (`CLAUDE.md` Environment).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  await runWithObservability(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Push.init();

    SupabaseCrayApi? api;
    String? deviceKey;
    if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
      api = SupabaseCrayApi(Supabase.instance.client);
      deviceKey = await DeviceKey.get();
    }

    // The cached document is authoritative offline, so the app opens wearing
    // the salon's brand with no network at all (DESIGN 3.3, PRD 15).
    final cached = await BrandingStore().read();

    runApp(
      ProviderScope(
        overrides: [
          if (api != null) crayApiProvider.overrideWithValue(api),
          if (api != null) hasSessionProvider.overrideWithValue(api.hasSession),
          if (deviceKey != null) deviceKeyProvider.overrideWithValue(deviceKey),
          if (cached != null) initialBrandingProvider.overrideWithValue(cached),
        ],
        child: const CraySalonApp(),
      ),
    );
  });
}

/// True when a session is already on the device. Overridden at startup;
/// defaults to false so widget tests need no Supabase.
final hasSessionProvider = Provider<bool>((ref) => false);

/// Hinglish is a SCRIPT variant, not a country variant: it must be built with
/// `Locale.fromSubtags(scriptCode: 'Latn')`. `Locale('hi', 'Latn')` silently
/// makes 'Latn' a country code and never matches (DESIGN.md 5.3).
final kEnglish = const Locale('en');
final kHindi = const Locale('hi');
final kHinglish = Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn');

/// The locale in use. At M5 this follows customer.language ??
/// salon.default_language ?? 'en' (DESIGN.md 12.5); until a customer has
/// settings, it follows the device.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => kEnglish;

  void select(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class CraySalonApp extends ConsumerWidget {
  const CraySalonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(resolvedBrandingProvider);
    final document = branding?.document ?? const <String, Object?>{};
    final version = branding?.version ?? 0;

    // Both modes come from the same published document, so a customer who
    // switches their phone to dark mode stays in their salon's brand.
    // A document we cannot theme from falls back whole - never half-themed,
    // and never another salon's colours (DESIGN 3.3).
    BrandTokens tokensFor(Brightness brightness) =>
        BrandTokens.fromPublished(document, brightness: brightness, version: version) ??
        BrandTokens.neutral(brightness: brightness, displayName: branding?.displayName);

    return MaterialApp(
      // The salon's name is the app's name once there is one (DESIGN 2.1).
      onGenerateTitle: (context) => branding?.displayName ?? AppL10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      theme: brandTheme(tokensFor(Brightness.light)),
      darkTheme: brandTheme(tokensFor(Brightness.dark)),
      home: ref.watch(hasSessionProvider) ? const SalonHome() : const JoinScreen(),
    );
  }
}
