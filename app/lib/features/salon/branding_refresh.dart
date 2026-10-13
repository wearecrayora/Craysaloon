import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/branding_store.dart';
import '../../domain/join/cray_api.dart';
import '../join/join_controller.dart';
import 'live_refresh.dart';

/// Branding published in the console reaches the app on its next open (PRD 20).
///
/// The app stores its salon's branding at join and wears the cached copy from
/// then on, so it opens branded with no network (DESIGN 3.3). This is the other
/// half: on every open, and every return to the foreground, it asks the server
/// for the salon's CURRENT branding and, if anything changed, stores and wears
/// it.
///
/// Three rules, each of which a simpler version would break:
///
/// * **The cache stays authoritative offline.** A failed read changes nothing -
///   the phone keeps the brand it has rather than dropping to the neutral one.
/// * **Only the bound salon, ever** (RULES 8.6). An answer naming any salon but
///   the one in the session is ignored, not worn.
/// * **Nothing is rewritten that did not change.** An unchanged answer does not
///   touch storage or rebuild the theme.
///
/// Returns true when a new version was worn.
Future<bool> refreshBranding(WidgetRef ref) async {
  final salonId = ref.read(sessionProvider)?.salonId;
  if (salonId == null) return false;

  final SalonSummary? fresh;
  try {
    fresh = await ref.read(crayApiProvider).myBranding();
  } on CrayApiException {
    return false;
  }
  if (fresh == null || fresh.salonId != salonId) return false;

  final current = ref.read(resolvedBrandingProvider);
  final unchanged = current != null &&
      current.salonId == fresh.salonId &&
      current.version == fresh.brandingVersion &&
      current.displayName == fresh.displayName &&
      current.grievance == fresh.grievance;
  if (unchanged) return false;

  await ref.read(brandingStoreProvider).save(
        salonId: fresh.salonId,
        displayName: fresh.displayName,
        version: fresh.brandingVersion,
        document: fresh.branding,
        grievance: fresh.grievance,
      );
  ref.read(resolvedBrandingProvider.notifier).wear(
        CachedBranding(
          salonId: fresh.salonId,
          displayName: fresh.displayName,
          version: fresh.brandingVersion,
          document: fresh.branding,
          grievance: fresh.grievance,
        ),
      );
  return true;
}

/// Keeps the app current with the console, without an update or a reinstall:
///
/// * on open - the branding;
/// * on every return to the foreground - the branding AND every server read
///   the console can change ([refreshServerReads]); "next open" on a phone is
///   usually a resume, not a cold start;
/// * every [interval] while the app stays open - the same, so a phone left on
///   the counter all day still catches a price changed at noon.
class BrandingRefresh extends ConsumerStatefulWidget {
  const BrandingRefresh({
    required this.child,
    this.interval = const Duration(minutes: 3),
    super.key,
  });

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<BrandingRefresh> createState() => _BrandingRefreshState();
}

class _BrandingRefreshState extends ConsumerState<BrandingRefresh>
    with WidgetsBindingObserver {
  bool _running = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(reads: false));
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(reads: true);
      _startTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // No polling from the background: it costs the customer battery and
      // data for a screen nobody is looking at.
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _refresh(reads: true));
  }

  Future<void> _refresh({required bool reads}) async {
    // One at a time: a resume during a slow read must not race it.
    if (_running || !mounted) return;
    _running = true;
    try {
      // Only a signed-in app has salon data to re-read; the join flow does not.
      if (reads && ref.read(sessionProvider) != null) refreshServerReads(ref);
      await refreshBranding(ref);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
