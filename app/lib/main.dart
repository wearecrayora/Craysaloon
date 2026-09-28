import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'core/observability/sentry_setup.dart';
import 'core/push/push_setup.dart';
import 'core/theme/brand_theme.dart';
import 'core/theme/brand_tokens.dart';
import 'data/local/branding_store.dart';
import 'data/local/cache_db.dart';
import 'data/local/cache_lifecycle.dart';
import 'data/local/device_key.dart';
import 'data/remote/supabase_cray_api.dart';
import 'features/join/join_controller.dart';
import 'features/notifications/background_ack.dart';
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
    // Registered before anything else touches Firebase: most pushes arrive when
    // nobody is looking at the app, and an unacked push escalates to a channel
    // the SALON pays for (ARCHITECTURE 12.3).
    registerBackgroundAck();

    SupabaseCrayApi? api;
    String? deviceKey;
    if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
      api = SupabaseCrayApi(Supabase.instance.client);
      deviceKey = await DeviceKey.get();
    }

    // The cached document is authoritative offline, so the app opens wearing the
    // salon's brand with no network at all (DESIGN 3.3, PRD 15) - but only while
    // it still belongs to whoever is signed in. A transfer or an unbind ends the
    // session server-side (0035), and THIS is where that becomes visible on the
    // phone: the old salon's branding and cached rows are wiped rather than worn
    // by whoever opens the app next.
    final cache = CacheDb();
    final cached = await brandingForSession(
      api?.session,
      store: BrandingStore(),
      cache: cache,
    );

    runApp(
      ProviderScope(
        overrides: [
          if (api != null) crayApiProvider.overrideWithValue(api),
          if (api != null) sessionProvider.overrideWithValue(api.session),
          if (deviceKey != null) deviceKeyProvider.overrideWithValue(deviceKey),
          if (cached != null) initialBrandingProvider.overrideWithValue(cached),
          cacheDbProvider.overrideWithValue(cache),
        ],
        child: const CraySalonApp(),
      ),
    );
  });
}

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

    return MaterialApp.router(
      // The salon's name is the app's name once there is one (DESIGN 2.1).
      onGenerateTitle: (context) => branding?.displayName ?? AppL10n.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      theme: brandTheme(tokensFor(Brightness.light)),
      darkTheme: brandTheme(tokensFor(Brightness.dark)),
      // The shell comes from app_role: the join flow when there is no salon, the
      // customer's salon when there is, the owner's shell for staff (ARCH 9.1).
      routerConfig: ref.watch(routerProvider),
    );
  }
}
