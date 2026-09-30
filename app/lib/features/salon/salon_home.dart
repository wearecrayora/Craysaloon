import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format/money.dart';
import '../../core/platform/home_shortcut.dart';
import '../../core/platform/salon_notifications.dart';
import '../../core/theme/brand_tokens.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/visit/visit.dart';
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';
import '../join/join_controller.dart';
import '../notifications/push_registration.dart';
import '../visit/visit_cards.dart';
import '../wallet/wallet_controller.dart';
import 'salon_account.dart';

/// Injected so the offer can be tested without a launcher, and so iOS gets the
/// same code path with a different answer (`RULES.md` 15b).
final homeShortcutProvider = Provider<HomeShortcut>(
  (ref) => const MethodChannelHomeShortcut(),
);

final salonNotificationsProvider = Provider<SalonNotifications>(
  (ref) => const MethodChannelSalonNotifications(),
);

/// C1 - the customer's home, in their salon's brand (Claude Design, 30 Sep 2026).
///
/// Greeting, then whatever has somebody waiting on it (a bill, today's code),
/// then what comes next (a booking, or when they are due), then the wallet with
/// its line, then referrals. No offers card: the design drew one, but there is
/// no offers feature behind it, and an offer the salon never made is a promise
/// the counter will not keep.
class SalonHome extends ConsumerStatefulWidget {
  const SalonHome({super.key});

  @override
  ConsumerState<SalonHome> createState() => _SalonHomeState();
}

class _SalonHomeState extends ConsumerState<SalonHome> {
  static const _offeredKey = 'cray.shortcut_offered';

  bool _showOffer = false;
  String? _confirmation;
  PushRegistration? _push;

  /// Bills already asked about in this session. Once asked, the card stays
  /// on the screen; the sheet does not reopen by itself.
  final Set<String> _asked = {};
  bool _asking = false;

  /// When the work is finished, ASK how they want to pay (29 Sep 2026) -
  /// unless they already said "at the counter".
  void _askAboutNewBill(List<Bill> bills) {
    if (_asking) return;
    final bill = bills
        .where((b) => !b.counterRequested && !_asked.contains(b.visitId))
        .firstOrNull;
    if (bill == null) return;
    _asked.add(bill.visitId);
    _asking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await PayBillSheet.open(context, bill);
      _asking = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _considerOffer();
    _ensureChannel();
    _startPush();
  }

  /// Push is the free channel, and the ack is what keeps it free: until the
  /// device says a message arrived, the server is counting down a window at the
  /// end of which the SALON pays for WhatsApp or SMS (ARCHITECTURE 12.3).
  @override
  void dispose() {
    // The streams outlive the widget otherwise, and an ack fired into a
    // disposed ref is a crash in a notification handler.
    _push?.dispose();
    super.dispose();
  }

  Future<void> _startPush() async {
    final api = ref.read(pushApiProvider);
    if (api == null) return;
    final push = PushRegistration(
      api,
      onArrived: (purpose) {
        // "Your bill is ready": re-read, and the listener in build() asks.
        if (purpose == 'visit_completed' && mounted) {
          ref.invalidate(billsProvider);
          ref.invalidate(visitsTodayProvider);
        }
      },
    );
    _push = push;
    await push.start();
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
    await ref
        .read(salonNotificationsProvider)
        .ensureChannel(
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
    ref.listen(
      billsProvider,
      (_, next) => _askAboutNewBill(next.value ?? const []),
    );

    final firstName = ref.watch(myProfileProvider).value?.firstName;

    return Scaffold(
      appBar: AppBar(
        title: const SalonTitle(),
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
      body: RefreshIndicator(
        // A "your bill is ready" push can arrive while this screen is open;
        // pulling down shows it - and re-reads the balance, which is never
        // served from a cache.
        onRefresh: () async {
          ref.invalidate(visitsTodayProvider);
          ref.invalidate(billsProvider);
          ref.invalidate(walletProvider);
          ref.invalidate(upcomingProvider);
          ref.invalidate(nextDueProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              firstName == null
                  ? l10n.homeGreetingNoName
                  : l10n.homeGreeting(firstName),
              style: text.headlineMedium,
            ),
            const SizedBox(height: 16),
            // Once, right after joining, and never again (ARCHITECTURE 7.3):
            // near the top, where it is seen, since it will not come back.
            if (_showOffer) ...[
              Appear(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.shortcutTitle(salonName),
                          style: text.titleMedium,
                        ),
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
                              confirmation: accepted
                                  ? l10n.shortcutAdded
                                  : null,
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
              ),
              const SizedBox(height: 12),
            ],
            if (_confirmation != null) ...[
              Text(_confirmation!, style: text.bodySmall),
              const SizedBox(height: 12),
            ],
            // A bill to pay comes FIRST: it is the one thing on this screen with
            // somebody waiting on it at the counter.
            const BillsCard(),
            // Today's booking and the code to read to the stylist (0084).
            const TodayVisitsCard(),
            const _NextCard(),
            const SizedBox(height: 12),
            _WalletCard(salonName: salonName),
            // Only when the salon's plan carries it (0087). The server refuses
            // the code either way; this just avoids a row that cannot work.
            if (hasFeature(ref, 'referrals')) ...[
              const SizedBox(height: 12),
              _RowCard(
                icon: Icons.card_giftcard_outlined,
                title: l10n.referTitle,
                subtitle: l10n.referSubtitle,
                onTap: () => context.push('/refer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What comes next: the next booking if there is one (and it is not today -
/// today's has its own card, with the start code), else when the salon's
/// reminder says they are due, else - a customer with neither - an invitation
/// to book, over one of the salon photos (an empty state, DESIGN 10).
class _NextCard extends ConsumerWidget {
  const _NextCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final now = DateTime.now();

    final upcoming = ref.watch(upcomingProvider).value ?? const [];
    final next = upcoming
        .where((b) => !DateUtils.isSameDay(b.startsAt, now))
        .firstOrNull;

    if (next != null) {
      return Appear(
        child: _RowCard(
          icon: Icons.event_available_outlined,
          title: l10n.homeNextBooking,
          subtitle: [
            '${ml.formatShortMonthDay(next.startsAt)} · '
                '${ml.formatTimeOfDay(TimeOfDay.fromDateTime(next.startsAt))}',
            if (next.serviceNames.isNotEmpty) next.serviceNames,
          ].join(' · '),
          onTap: () => context.push('/booking/${next.id}'),
        ),
      );
    }

    final due = ref.watch(nextDueProvider);
    if (!due.hasValue) return const SizedBox.shrink();
    final nextDue = due.value;

    if (nextDue == null) return const _FirstVisitCard();

    final date = ml.formatShortMonthDay(nextDue.dueOn);
    final service = nextDue.serviceName?.toLowerCase();
    return Appear(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.event_repeat_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      service == null
                          ? l10n.homeNextDue(date)
                          : l10n.homeNextDueService(service, date),
                      style: text.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                style: _tonal(context),
                onPressed: () => context.go('/book'),
                child: Text(l10n.homeBookNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstVisitCard extends StatelessWidget {
  const _FirstVisitCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);

    return Appear(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A salon space, no people (DESIGN 10: "rich, rules kept").
            SizedBox(
              height: 132,
              child: Image.asset(
                'assets/images/salon_chairs.jpg',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.homeFirstVisit,
                    style: text.titleMedium?.copyWith(color: g.ink),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go('/book'),
                    child: Text(l10n.homeBookNow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The balance, with its line, always together (DESIGN 6.1): a balance on its
/// own would be a number a customer might think is cash. Never from a cache,
/// never animated - it appears, or the card says it could not be loaded.
class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.salonName});

  final String salonName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final wallet = ref.watch(walletProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.walletBalance, style: text.bodyMedium),
            const SizedBox(height: 4),
            switch (wallet) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rupees(value.summary.balancePaise),
                    style: text.displaySmall?.copyWith(
                      fontFeatures: moneyFeatures,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.walletOnlyAtSalon(salonName),
                    style: text.bodyMedium,
                  ),
                ],
              ),
              AsyncError() => Text(
                l10n.homeWalletUnavailable,
                style: text.bodyMedium,
              ),
              // A still block, not a shimmer (DESIGN 7.3), the height of the
              // number it stands in for.
              _ => const _Placeholder(height: 64),
            },
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    style: _tonal(context),
                    onPressed: () => context.push('/wallet/add'),
                    child: Text(l10n.walletAddMoney),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/wallet'),
                    child: Text(l10n.walletView),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// A tappable glass row: icon, title, one line under it, a chevron.
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's soft secondary action (Book now, Add money): the brand's
/// container fill with its computed ink. Set here because the app-wide
/// FilledButton theme paints every FilledButton - tonal included - in primary.
ButtonStyle _tonal(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.primaryContainer,
    foregroundColor: scheme.onPrimaryContainer,
  );
}
