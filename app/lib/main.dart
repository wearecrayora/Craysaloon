import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'features/salon/branding_refresh.dart';
import 'l10n/app_localizations.dart';

/// Configuration arrives with `--dart-define`, never from a file in the repo.
/// The publishable key is designed to ship in a client; the secret key never
/// touches this codebase (`CLAUDE.md` Environment).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  await runWithObservability(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // The fonts are Google Fonts, under the SIL Open Font License, which asks
    // that the licence travel with them: shown on Me / More -> licences.
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        const ['Google Fonts'],
        await rootBundle.loadString('assets/licenses/OFL.txt'),
      );
    });
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
          // Live, not read once: signing in at the end of the join flow, signing
          // out, and a session ended server-side (a transfer, an unbind) all
          // move the app to the right shell without a restart. Only a change of
          // WHO (role or salon) re-reads it - an hourly token refresh must not
          // rebuild the router under someone mid-booking.
          if (api != null)
            sessionProvider.overrideWith((ref) {
              final current = api!.session;
              final sub = api.sessionChanges.listen((_) {
                final next = api!.session;
                if (next?.appRole != current?.appRole ||
                    next?.salonId != current?.salonId) {
                  ref.invalidateSelf();
                }
              });
              ref.onDispose(sub.cancel);
              return current;
            }),
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

/// The code the server keeps for a locale (customers.language, 0118) and the
/// message templates are keyed by: en | hi | hi_Latn.
String localeCode(Locale locale) => locale.languageCode == 'hi'
    ? (locale.scriptCode == 'Latn' ? 'hi_Latn' : 'hi')
    : 'en';

Locale localeFromCode(String? code) => switch (code) {
  'hi' => kHindi,
  'hi_Latn' => kHinglish,
  _ => kEnglish,
};

/// The locale in use: the customer's own choice, kept on the phone so it
/// survives a restart, and - for a signed-in customer - saved to their profile
/// too, so their messages arrive in it (0118).
class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'cray.locale';

  @override
  Locale build() {
    _restore();
    return kEnglish;
  }

  bool _chosen = false;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      // A choice made while this was reading wins over what was saved.
      if (saved != null && !_chosen) state = localeFromCode(saved);
    } catch (_) {
      // No storage (tests, a broken install): English until they choose.
    }
  }

  void select(Locale locale) {
    _chosen = true;
    state = locale;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_key, localeCode(locale)))
        .catchError((Object _) => false);
  }
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
      // Republished branding reaches the phone on its next open (PRD 20).
      builder: (context, child) => BrandingRefresh(child: child ?? const SizedBox.shrink()),
    );
  }
}
