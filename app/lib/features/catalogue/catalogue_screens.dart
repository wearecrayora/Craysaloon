import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/format/money.dart';
import '../../core/ui/cache_banner.dart';
import '../../data/repositories/records_repository.dart';
import '../../l10n/app_localizations.dart';

/// O7, O8, O9 - the menu and the team, as the owner sees them.
///
/// Read-only for now, and honest about it: Crayora sets the catalogue up in the
/// console (M2), and editing it from the app is the next slice of M5. A screen
/// with disabled edit buttons would promise something that is not there.
///
/// All three share a shape, so they share a widget: a list, a hidden-items
/// marker, and the cache notice that keeps "as of" visible rather than implied.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return _CatalogueList(
      title: l10n.catalogueServices,
      cached: ref.watch(servicesProvider),
      rowBuilder: (context, service) => _CatalogueRow(
        name: service.name,
        detail: l10n.minutesShort(service.durationMinutes),
        amountPaise: service.pricePaise,
        active: service.active,
      ),
    );
  }
}

class AddOnsScreen extends ConsumerWidget {
  const AddOnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return _CatalogueList(
      title: l10n.catalogueAddOns,
      cached: ref.watch(addOnsProvider),
      rowBuilder: (context, addOn) => _CatalogueRow(
        name: addOn.name,
        // Add-ons are never pre-selected anywhere in this app (RULES 9); this
        // screen only lists what exists.
        detail: addOn.extraDurationMinutes == 0
            ? null
            : l10n.addsMinutes(addOn.extraDurationMinutes),
        amountPaise: addOn.pricePaise,
        active: addOn.active,
      ),
    );
  }
}

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return _CatalogueList(
      title: l10n.staffTitle,
      cached: ref.watch(staffProvider),
      rowBuilder: (context, member) =>
          _CatalogueRow(name: member.name, active: member.active),
    );
  }
}

class _CatalogueList<T> extends StatelessWidget {
  const _CatalogueList({
    required this.title,
    required this.cached,
    required this.rowBuilder,
  });

  final String title;
  final AsyncValue<Cached<List<T>>> cached;
  final Widget Function(BuildContext, T) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: cached.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.joinOffline),
          ),
          data: (result) {
            if (result.value.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  result.fromCache ? l10n.cachedNeverLoaded : l10n.catalogueEmpty,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (result.fromCache) CacheBanner(refreshedAt: result.refreshedAt),
                for (final row in result.value) rowBuilder(context, row),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogueRow extends StatelessWidget {
  const _CatalogueRow({
    required this.name,
    required this.active,
    this.detail,
    this.amountPaise,
  });

  final String name;
  final bool active;
  final String? detail;
  final int? amountPaise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(name),
      subtitle: detail == null && active
          ? null
          : Wrap(
              spacing: 12,
              children: [
                if (detail != null) Text(detail!, style: text.bodySmall),
                if (!active) Text(l10n.inactiveLabel, style: text.bodySmall),
              ],
            ),
      trailing: amountPaise == null
          ? null
          : Text(
              rupees(amountPaise!),
              style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
            ),
    );
  }
}
