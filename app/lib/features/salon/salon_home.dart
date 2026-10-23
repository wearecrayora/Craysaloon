import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format/money.dart';
import '../../core/platform/home_shortcut.dart';
import '../../core/platform/salon_notifications.dart';
import '../../core/theme/brand_tokens.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/theme/motion.dart';
import '../../core/ui/action_tile.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/service_icon.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/customer/customer.dart';
import '../../domain/records/records.dart' show Service;
import '../../domain/visit/visit.dart';
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';
import '../../core/ui/menu.dart' show Initials;
import '../customer/me_screen.dart' show editBirthday;
import '../join/join_controller.dart';
import '../notifications/push_registration.dart';
import '../visit/visit_cards.dart';
import '../wallet/wallet_controller.dart';
import '../../core/platform/external_link.dart' show openUpdate;
import '../app_config/app_config_providers.dart';
import '../booking/kind_label.dart';
import 'live_refresh.dart';
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
      // The app is open: say it here, as a pop-up, since Android will not.
      onForeground: (text) {
        if (mounted) showNotice(context, text, kind: NoticeKind.info);
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

    final profile = ref.watch(myProfileProvider).value;
    final firstName = profile?.firstName;
    final billCount = ref.watch(billsProvider).value?.length ?? 0;
    final config = appConfig(ref);

    // Each tile the console can place, in the order it chose (0119). A tile
    // the app cannot show here - a switch off, a plan without it, a child's
    // account - is simply left out; an unknown name is skipped.
    ActionTile? tile(String key) => switch (key) {
      'book' => ActionTile(
        icon: Icons.event_available_outlined,
        label: l10n.navBook,
        onTap: () => context.go('/book'),
      ),
      'add_money' when config.on('wallet_topup') => ActionTile(
        icon: Icons.add_card_outlined,
        label: l10n.walletAddMoney,
        onTap: () => context.push('/wallet/add'),
      ),
      'bookings' => ActionTile(
        icon: Icons.receipt_long_outlined,
        label: l10n.bookingsTitle,
        onTap: () => context.go('/bookings'),
      ),
      'bills' => ActionTile(
        icon: Icons.request_quote_outlined,
        label: l10n.meTileBills,
        badge: billCount > 0 ? '$billCount' : null,
        onTap: () => context.push('/documents'),
      ),
      // Only when the salon's plan carries it (0087) and the switch is on.
      'refer' when hasFeature(ref, 'referrals') => ActionTile(
        icon: Icons.card_giftcard_outlined,
        label: l10n.referTitle,
        onTap: () => context.push('/refer'),
      ),
      'birthday'
          when profile != null && !profile.isMinor && config.on('birthday') =>
        ActionTile(
          icon: Icons.cake_outlined,
          label: l10n.homeTileBirthday,
          onTap: () => editBirthday(context, ref, profile, salonName),
        ),
      'profile' => ActionTile(
        icon: Icons.person_outline,
        label: l10n.meEditProfile,
        onTap: () => context.push('/me/edit'),
      ),
      'your_data' => ActionTile(
        icon: Icons.privacy_tip_outlined,
        label: l10n.yourDataTitle,
        onTap: () => context.push('/your-data'),
      ),
      'search' when config.on('search') => ActionTile(
        icon: Icons.search,
        label: l10n.homeTileSearch,
        onTap: () => context.push('/search'),
      ),
      _ => null,
    };

    final sections = <Widget>[
      for (final s in config.homeSections)
        ...switch (s) {
          'categories' => [const _CategoriesRow()],
          'quick' => [
            SectionHeader(l10n.homeQuickTitle),
            ActionGrid(tiles: [for (final k in config.homeTiles) ?tile(k)]),
          ],
          'services' => [const _ServicesRow()],
          'wallet' => [
            const SizedBox(height: 24),
            _WalletCard(salonName: salonName),
          ],
          _ => const <Widget>[],
        },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const SalonTitle(),
        actions: [
          // On the home screen, not three levels into a settings menu: a right
          // nobody can find is a right nobody has (DPDP ss.6(4), 11-13). Never
          // configurable away.
          IconButton(
            onPressed: () => context.push('/your-data'),
            icon: const Icon(Icons.shield_outlined),
            tooltip: l10n.yourDataTitle,
          ),
          // The profile, one tap from anywhere it is needed.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: l10n.navMe,
              onPressed: () => context.go('/me'),
              icon: Initials(profile?.initials, size: 36),
            ),
          ),
        ],
      ),
      // The search bar stays put while the rest scrolls under it, as on a
      // shopping app's home - unless the console switched search off.
      body: Column(
        children: [
          if (config.on('search'))
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _SearchBar(),
            ),
          Expanded(
            child: RefreshIndicator(
              // A "your bill is ready" push can arrive while this screen is
              // open; pulling down shows it - and re-reads the balance, which
              // is never served from a cache.
              onRefresh: () async => refreshServerReads(ref),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _Hero(
                    greeting: firstName == null
                        ? l10n.homeGreetingNoName
                        : _greeting(l10n, firstName, DateTime.now()),
                    today: _today(context),
                  ),
                  const SizedBox(height: 16),
                  const _UpdateBanner(),
                  if (config.on('announcements')) const _Announcements(),
                  // Once, right after joining, and never again (ARCH 7.3).
                  if (_showOffer) ...[
                    Appear(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.add_to_home_screen_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      l10n.shortcutTitle(salonName),
                                      style: text.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(l10n.shortcutBody, style: text.bodySmall),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () async {
                                  // Android shows its own dialog; a false answer
                                  // means it was not accepted, and the app says
                                  // nothing rather than claim an icon exists.
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
                  // Through the birthday month: what to claim at the counter.
                  if (config.on('birthday')) const _BirthdayCard(),
                  if (_confirmation != null) ...[
                    Text(_confirmation!, style: text.bodySmall),
                    const SizedBox(height: 12),
                  ],
                  // These three are never moved by the console: a bill to pay,
                  // today's booking with its code, and the next one are what
                  // somebody is waiting on, so they come first, always.
                  const BillsCard(),
                  const TodayVisitsCard(),
                  const _NextCard(),
                  ...sections,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The greeting, on a card in the salon's own soft colour with one of its
/// photos - the colourful top of the page, as a shopping app's home has.
/// The words sit on the brand's container colour with its computed ink, the
/// pair the publish step proves (DESIGN 3.3); the photo is beside them, never
/// behind them.
class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.today});

  final String greeting;
  final String today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    final ink = scheme.onPrimaryContainer;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(g.radius + 8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(scheme.primaryContainer, g.cardTop, 0.35)!,
          ],
        ),
        border: Border.all(color: g.line),
        boxShadow: g.shadows,
      ),
      // As tall as the words need; the photo fills that height beside them.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      greeting,
                      style: text.headlineSmall?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 4),
                    Text(today, style: text.bodyMedium?.copyWith(color: ink)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 112,
              child: Image.asset(
                'assets/images/salon_bright.jpg',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "A new version is available" - when the console says a newer build exists
/// (0119). Dismissed for this session; the forced update is UpdateGate's.
class _UpdateBanner extends ConsumerStatefulWidget {
  const _UpdateBanner();

  @override
  ConsumerState<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<_UpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final config = appConfig(ref);
    final build = ref.watch(buildNumberProvider).value ?? 0;
    if (_dismissed || build == 0 || config.latestBuild <= build) {
      return const SizedBox.shrink();
    }
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Appear(
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.system_update_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.updateAvailable, style: text.bodyMedium),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => openUpdate(config.updateUrl),
                child: Text(l10n.updateNow),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => setState(() => _dismissed = true),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The salon's announcements, as cards you swipe through - its own news,
/// between the dates the console set (0119). Never auto-advancing: a card
/// that moves while you read it is a card you cannot read.
class _Announcements extends ConsumerWidget {
  const _Announcements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsProvider).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final hindi =
        Localizations.localeOf(context).languageCode == 'hi' &&
        Localizations.localeOf(context).scriptCode != 'Latn';
    final height =
        112 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.2);
    // Room between cards only when there is more than one to swipe to.
    final double gap = list.length > 1 ? 12 : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: height,
        child: PageView.builder(
          controller: PageController(
            viewportFraction: list.length > 1 ? 0.9 : 1,
          ),
          padEnds: false,
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            final title = hindi && (a.titleHi ?? '').isNotEmpty
                ? a.titleHi!
                : a.title;
            final body = hindi && (a.bodyHi ?? '').isNotEmpty
                ? a.bodyHi
                : a.body;
            return Padding(
              padding: EdgeInsets.only(right: gap),
              child: _AnnouncementCard(title: title, body: body, icon: a.icon),
            );
          },
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String? body;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    final ink = scheme.onSecondaryContainer;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(g.radius + 4),
          color: scheme.secondaryContainer,
          border: Border.all(color: g.line),
          boxShadow: g.shadows,
        ),
        child: Row(
          children: [
            Icon(
              switch (icon) {
                'event' => Icons.event_outlined,
                'celebration' => Icons.celebration_outlined,
                'info' => Icons.info_outline,
                'schedule' => Icons.schedule,
                'new' => Icons.fiber_new_outlined,
                _ => Icons.campaign_outlined,
              },
              size: 32,
              color: ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: ink),
                  ),
                  if ((body ?? '').isNotEmpty)
                    Text(
                      body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: ink),
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

/// "What are you looking for?" - the kinds of service this salon actually
/// offers, each with its photograph, as a grocery app's categories. A tap
/// opens search narrowed to that kind.
class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final services =
        ref.watch(bookableServicesProvider).value ?? const <Service>[];
    final kinds = <ServiceKind>[
      for (final k in ServiceKind.values)
        if (kindImage(k) != null &&
            services.any((s) => serviceKind(s.name, category: s.category) == k))
          k,
    ];
    // ServiceKind.styling shares the hair photo; one tile for both.
    kinds.remove(ServiceKind.styling);
    if (kinds.length < 2) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.homeCategoriesTitle),
        SizedBox(
          height: 124 + 24 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kinds.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final k = kinds[i];
              return Pressable(
                onTap: () => context.push('/search?kind=${k.name}'),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: CrayGlass.of(context).line,
                            width: 2,
                          ),
                          boxShadow: CrayGlass.of(context).shadows,
                        ),
                        child: Image.asset(
                          kindImage(k)!,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        kindLabel(l10n, k),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The search bar: looks like a field, opens the search page. A real field
/// here would put the keyboard up on the home screen for anyone who brushed it.
///
/// Its hint walks through the salon's own services - "Search "Haircut"", then
/// "Search "Facial"" - every three seconds, rolling up, as a grocery app's
/// does: it tells a first-time customer what the salon offers before they
/// type anything. With reduced motion it holds still on the general hint.
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  Timer? _tick;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !Motion.isReduced(context)) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final g = CrayGlass.of(context);
    final text = Theme.of(context).textTheme;
    final names =
        (ref.watch(bookableServicesProvider).value ?? const <Service>[])
            .map((s) => s.name)
            .take(6)
            .toList();
    final hint = names.isEmpty || Motion.isReduced(context)
        ? l10n.searchHint
        : l10n.searchFor(names[_i % names.length]);
    return Pressable(
      onTap: () => context.push('/search'),
      scale: 0.98,
      child: Semantics(
        label: l10n.searchHint,
        button: true,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Recessed, like the field it opens.
          decoration: BoxDecoration(
            color: g.sunken,
            borderRadius: BorderRadius.circular(g.radius),
            border: Border.all(color: g.line),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: text.bodyMedium?.color),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: Motion.standard,
                    switchInCurve: Motion.enter,
                    switchOutCurve: Motion.exit,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    // The new hint rises in from below; the old one rises out.
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(
                            0,
                            child.key == ValueKey(hint) ? 0.6 : -0.6,
                          ),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      hint,
                      key: ValueKey(hint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The salon's services as a row of cards - picture, name, time, price - each
/// one tap from booking it. Nothing is booked or chosen until they say so:
/// the card opens the booking with that service ticked, nothing else.
class _ServicesRow extends ConsumerWidget {
  const _ServicesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final services = ref.watch(bookableServicesProvider);
    final list = services.value;
    if (services.hasError || (list != null && list.isEmpty)) {
      return const SizedBox.shrink();
    }
    final height =
        232 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.homeServicesTitle,
          action: l10n.homeSeeAll,
          onAction: () => context.push('/search'),
        ),
        SizedBox(
          height: height,
          child: list == null
              // Loading: still cards the size of the real ones (DESIGN 7.4).
              ? ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      SizedBox(width: 148, child: SkeletonCard(height: height)),
                    ],
                  ],
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length.clamp(0, 10),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _ServiceCard(service: list[i]),
                ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);
    return SizedBox(
      width: 148,
      child: Pressable(
        onTap: () => context.go('/book?service=${service.id}'),
        child: GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The kind's photograph where there is one, else its icon in a
              // soft brand square - every card carries a picture.
              ClipRRect(
                borderRadius: BorderRadius.circular(g.radius - 2),
                child: SizedBox(
                  height: 72,
                  width: double.infinity,
                  child: switch (kindImage(
                    serviceKind(service.name, category: service.category),
                  )) {
                    final String asset => Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                    null => ColoredBox(
                      color: scheme.primaryContainer,
                      child: Icon(
                        serviceIcon(service.name, category: service.category),
                        size: 32,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  service.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ),
              Text(
                l10n.bookMinutes(service.durationMinutes),
                style: text.bodySmall,
              ),
              Text(
                rupees(service.pricePaise),
                style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
              ),
            ],
          ),
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
      return Appear(child: _NextBookingCard(booking: next));
    }

    final due = ref.watch(nextDueProvider);
    if (!due.hasValue) return const SizedBox.shrink();
    final nextDue = due.value;

    if (nextDue == null) {
      // No reminder scheduled. Somebody who has been before is invited back;
      // only somebody who never has is told it would be their first visit.
      final history = ref.watch(historyProvider);
      if (!history.hasValue) return const SizedBox.shrink();
      return _FirstVisitCard(returning: history.value!.isNotEmpty);
    }

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
  const _FirstVisitCard({required this.returning});

  final bool returning;

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
                    returning ? l10n.homeBookAgain : l10n.homeFirstVisit,
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
              AsyncValue(hasError: true) => Text(
                l10n.homeWalletUnavailable,
                style: text.bodyMedium,
              ),
              // A still block, not a shimmer (DESIGN 7.3), the height of the
              // number it stands in for.
              _ => const SkeletonBlock(height: 64),
            },
            const SizedBox(height: 16),
            Row(
              children: [
                if (switchOn(ref, 'wallet_topup')) ...[
                  Expanded(
                    child: FilledButton.tonal(
                      style: _tonal(context),
                      onPressed: () => context.push('/wallet/add'),
                      child: Text(l10n.walletAddMoney),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
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

/// "Good morning, Asha" - by the phone's clock, which is the customer's.
String _greeting(AppL10n l10n, String name, DateTime now) => switch (now.hour) {
  < 12 => l10n.homeGreetingMorning(name),
  < 17 => l10n.homeGreetingAfternoon(name),
  _ => l10n.homeGreetingEvening(name),
};

/// Today, written out ("Wednesday, October 14"), in the app's language.
String _today(BuildContext context) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  try {
    return DateFormat.MMMMEEEEd(locale).format(DateTime.now());
  } catch (_) {
    return DateFormat.MMMMEEEEd().format(DateTime.now());
  }
}

/// The next booking as a ticket: the date large on the left, where the eye
/// lands, then the time, what is booked and with whom.
class _NextBookingCard extends StatelessWidget {
  const _NextBookingCard({required this.booking});

  final UpcomingBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ml = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    String month;
    try {
      month = DateFormat.MMM(locale).format(booking.startsAt);
    } catch (_) {
      month = DateFormat.MMM().format(booking.startsAt);
    }
    final staff = booking.staffName;

    return Pressable(
      onTap: () => context.push('/booking/${booking.id}'),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // The date block: the brand's container, its computed ink.
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${booking.startsAt.day}',
                      style: text.headlineSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      month,
                      style: text.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.homeNextBooking, style: text.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      ml.formatTimeOfDay(
                        TimeOfDay.fromDateTime(booking.startsAt),
                      ),
                      style: text.titleMedium,
                    ),
                    if (booking.serviceNames.isNotEmpty)
                      Text(booking.serviceNames, style: text.bodyMedium),
                    if (staff != null && staff.isNotEmpty)
                      Text(l10n.homeWithStylist(staff), style: text.bodySmall),
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

/// The salon's birthday offer, in the customer's birthday month (0113): the
/// thing to show at the counter. Nothing at all in any other month.
class _BirthdayCard extends ConsumerWidget {
  const _BirthdayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(myBirthdayOfferProvider).value;
    if (offer == null) return const SizedBox.shrink();
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Appear(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cake_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.homeBirthdayTitle, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        l10n.homeBirthdayBody(offer),
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
