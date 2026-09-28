import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/home_shortcut.dart';
import '../../core/platform/salon_notifications.dart';
import '../../core/theme/brand_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

/// Injected so the offer can be tested without a launcher, and so iOS gets the
/// same code path with a different answer (`RULES.md` 15b).
final homeShortcutProvider =
    Provider<HomeShortcut>((ref) => const MethodChannelHomeShortcut());

final salonNotificationsProvider =
    Provider<SalonNotifications>((ref) => const MethodChannelSalonNotifications());

/// The customer's salon, after binding.
///
/// The product surfaces - wallet, bookings, offers - arrive in later
/// milestones; this screen exists because M4 owns two things that belong to
/// binding rather than to any feature: the app wearing the salon's brand, and
/// the offer to put the salon on the home screen.
class SalonHome extends ConsumerStatefulWidget {
  const SalonHome({super.key});

  @override
  ConsumerState<SalonHome> createState() => _SalonHomeState();
}

class _SalonHomeState extends ConsumerState<SalonHome> {
  static const _offeredKey = 'cray.shortcut_offered';

  bool _showOffer = false;
  String? _confirmation;

  @override
  void initState() {
    super.initState();
    _considerOffer();
    _ensureChannel();
  }

  /// The channel is named for the salon, so Settings shows the customer their
  /// salon (ARCHITECTURE 7.4). Created here rather than at push-registration
  /// time because the name only exists once there is a binding.
  Future<void> _ensureChannel() async {
    final branding = ref.read(resolvedBrandingProvider);
    if (branding == null) return;
    final tokens = BrandTokens.fromPublished(
      branding.document,
      brightness: Brightness.light,
      version: branding.version,
    );
    await ref.read(salonNotificationsProvider).ensureChannel(
          salonName: branding.displayName,
          accentArgb: tokens?.primary.toARGB32(),
        );
  }

  /// Offered once, after binding, and never again on its own: "make it
  /// re-triggerable from settings. Never nag" (`ARCHITECTURE.md` 7.3). An
  /// unsupported launcher - and every iPhone - sees nothing at all.
  Future<void> _considerOffer() async {
    final supported = await ref.read(homeShortcutProvider).isSupported();
    if (!supported || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_offeredKey) ?? false) return;
    if (mounted) setState(() => _showOffer = true);
  }

  Future<void> _dismissOffer({String? confirmation}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offeredKey, true);
    if (!mounted) return;
    setState(() {
      _showOffer = false;
      _confirmation = confirmation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final branding = ref.watch(resolvedBrandingProvider);
    final salonName = branding?.displayName ?? l10n.appTitle;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(salonName),
        actions: [
          // On the home screen, not three levels into a settings menu: a right
          // nobody can find is a right nobody has (DPDP ss.6(4), 11-13).
          IconButton(
            onPressed: () => context.push('/your-data'),
            icon: const Icon(Icons.shield_outlined),
            tooltip: l10n.yourDataTitle,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.joinedTitle(salonName), style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(l10n.homeReady, style: text.bodyMedium),
            const SizedBox(height: 24),
            // The wallet is the retention loop's front door. It is a
            // destination, not a number on this screen: a balance shown here
            // would have to carry its own "only at this salon, not cash" line
            // (DESIGN 6.1), and two places saying it is two places to get it
            // wrong.
            FilledButton.tonal(
              onPressed: () => context.push('/wallet'),
              child: Text(l10n.walletTitle),
            ),
            if (_confirmation != null) ...[
              const SizedBox(height: 16),
              Text(_confirmation!, style: text.bodySmall),
            ],
            if (_showOffer) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.shortcutTitle(salonName), style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(l10n.shortcutBody, style: text.bodySmall),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          // Android shows its own dialog; a false answer means
                          // the request was not accepted, and the app says
                          // nothing rather than claiming an icon exists.
                          final accepted = await ref
                              .read(homeShortcutProvider)
                              .offer(label: salonName);
                          await _dismissOffer(
                            confirmation: accepted ? l10n.shortcutAdded : null,
                          );
                        },
                        child: Text(l10n.shortcutAdd),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _dismissOffer(),
                        child: Text(l10n.shortcutNotNow),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
