import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/theme/chart_palette.dart';
import '../../domain/salon/salon_account.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

final salonAccountApiProvider = Provider<SalonAccountApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is SalonAccountApi ? api as SalonAccountApi : null;
});

/// Whether this salon can record anything (0087). A failed read is NOT read-only:
/// the server refuses writes either way, and a banner shown on a network error
/// would tell an owner their subscription lapsed when it did not.
final salonBillingProvider = FutureProvider<SalonBilling>((ref) async {
  final api = ref.watch(salonAccountApiProvider);
  if (api == null) return SalonBilling.open;
  try {
    return await api.myBilling();
  } on Exception {
    return SalonBilling.open;
  }
});

/// The features this salon's plan carries, or null while unknown. Unknown shows
/// the button: the server gate refuses it anyway, and hiding a feature the
/// salon HAS because the network blinked is the worse mistake.
final salonFeaturesProvider = FutureProvider<Set<String>?>((ref) async {
  final api = ref.watch(salonAccountApiProvider);
  if (api == null) return null;
  try {
    return await api.myFeatures();
  } on Exception {
    return null;
  }
});

bool hasFeature(WidgetRef ref, String feature) {
  final features = ref.watch(salonFeaturesProvider).value;
  return features == null || features.contains(feature);
}

/// Shown at the top of the owner's day when the salon cannot record anything.
///
/// It says WHY, before the owner taps Start and gets a refusal in Needs
/// attention. A fixed status colour with an icon and words - never the brand,
/// never colour alone (DESIGN 3.3, 6.7).
class ReadOnlyBanner extends ConsumerWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(salonBillingProvider).value;
    if (billing == null || !billing.readOnly) return const SizedBox.shrink();

    final l10n = AppL10n.of(context);
    final owner = ref.watch(canEditCatalogueProvider);
    final text = !owner
        ? l10n.billingReadOnlyStaff
        : billing.state == 'grace' && billing.graceEndsAt != null
            ? l10n.billingReadOnlyGrace(DateFormat.yMMMd().format(billing.graceEndsAt!.toLocal()))
            : billing.lapsed
                ? l10n.billingReadOnlySuspended
                : l10n.billingReadOnlyOther;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, color: ChartPalette.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.billingReadOnlyTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
