import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/branding_store.dart';
import '../../domain/join/cray_api.dart';
import '../join/join_controller.dart';

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

/// Runs [refreshBranding] once the app is up and again whenever it comes back
/// to the foreground - "next open" on a phone is usually a resume, not a cold
/// start.
class BrandingRefresh extends ConsumerStatefulWidget {
  const BrandingRefresh({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BrandingRefresh> createState() => _BrandingRefreshState();
}

class _BrandingRefreshState extends ConsumerState<BrandingRefresh>
    with WidgetsBindingObserver {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    // One at a time: a resume during a slow read must not race it.
    if (_running || !mounted) return;
    _running = true;
    try {
      await refreshBranding(ref);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
