import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format/money.dart';
import '../../core/ui/cache_banner.dart';
import '../../data/repositories/records_repository.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import 'catalogue_form.dart';

/// O7, O8, O9 - the menu and the team.
///
/// Add and edit are shown **only to an owner or a manager**, and that is a
/// courtesy: the database refuses the write whatever the app sends (0041). A
/// stylist sees the list without controls rather than controls that fail.
///
/// All three screens share a shape, so they share a widget: three near-identical
/// screens is how two of them end up behaving differently.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    return _CatalogueList<Service>(
      title: l10n.catalogueServices,
      cached: ref.watch(servicesProvider),
      onAdd: () => _edit(context, ref, null),
      rowBuilder: (context, service) => _CatalogueRow(
        name: service.name,
        detail: l10n.minutesShort(service.durationMinutes),
        amountPaise: service.pricePaise,
        active: service.active,
        onTap: () => _edit(context, ref, service),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Service? service) async {
    // Captured BEFORE the sheet: after an await the screen may be gone, and a
    // BuildContext used across that gap is a crash waiting for a slow network.
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = await CatalogueForm.open(
      context,
      title: l10n.serviceFormTitle,
      draft: CatalogueDraft(
        name: service?.name ?? '',
        active: service?.active ?? true,
        pricePaise: service?.pricePaise ?? 0,
        minutes: service?.durationMinutes ?? 30,
      ),
    );
    if (draft == null) return;

    await saveAndReport(
      messenger,
      l10n,
      () async {
        final repo = ref.read(recordsRepositoryProvider);
        if (repo == null) throw const CrayApiException(CrayErrorKind.forbidden);
        await repo.saveService(
          id: service?.id,
          name: draft.name,
          pricePaise: draft.pricePaise,
          durationMinutes: draft.minutes,
          active: draft.active,
        );
        ref.invalidate(servicesProvider);
      },
    );
  }
}

class AddOnsScreen extends ConsumerWidget {
  const AddOnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    return _CatalogueList<AddOn>(
      title: l10n.catalogueAddOns,
      cached: ref.watch(addOnsProvider),
      onAdd: () => _edit(context, ref, null),
      rowBuilder: (context, addOn) => _CatalogueRow(
        name: addOn.name,
        // Add-ons are never pre-selected anywhere in this app (RULES 9); this
        // screen only says what exists and what it costs.
        detail: addOn.extraDurationMinutes == 0
            ? null
            : l10n.addsMinutes(addOn.extraDurationMinutes),
        amountPaise: addOn.pricePaise,
        active: addOn.active,
        onTap: () => _edit(context, ref, addOn),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AddOn? addOn) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = await CatalogueForm.open(
      context,
      title: l10n.addOnFormTitle,
      draft: CatalogueDraft(
        name: addOn?.name ?? '',
        active: addOn?.active ?? true,
        pricePaise: addOn?.pricePaise ?? 0,
        minutes: addOn?.extraDurationMinutes ?? 0,
      ),
      minutesLabelIsExtra: true,
    );
    if (draft == null) return;

    await saveAndReport(
      messenger,
      l10n,
      () async {
        final repo = ref.read(recordsRepositoryProvider);
        if (repo == null) throw const CrayApiException(CrayErrorKind.forbidden);
        await repo.saveAddOn(
          id: addOn?.id,
          name: draft.name,
          pricePaise: draft.pricePaise,
          extraDurationMinutes: draft.minutes,
          active: draft.active,
        );
        ref.invalidate(addOnsProvider);
      },
    );
  }
}

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    return _CatalogueList<StaffMember>(
      title: l10n.staffTitle,
      cached: ref.watch(staffProvider),
      onAdd: () => _edit(context, ref, null),
      rowBuilder: (context, member) => _CatalogueRow(
        name: member.name,
        active: member.active,
        onTap: () => _edit(context, ref, member),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, StaffMember? member) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = await CatalogueForm.open(
      context,
      title: l10n.staffFormTitle,
      draft: CatalogueDraft(name: member?.name ?? '', active: member?.active ?? true),
      showPrice: false,
      showMinutes: false,
    );
    if (draft == null) return;

    await saveAndReport(
      messenger,
      l10n,
      () async {
        final repo = ref.read(recordsRepositoryProvider);
        if (repo == null) throw const CrayApiException(CrayErrorKind.forbidden);
        await repo.saveStaff(id: member?.id, name: draft.name, active: draft.active);
        ref.invalidate(staffProvider);
      },
    );
  }
}

/// Runs a save and says what happened. A refusal is reported as a refusal - the
/// account cannot do this - and never retried, because the answer will not
/// change. Offline is reported as not saved, which is the truth: catalogue edits
/// are not queued (ARCHITECTURE 10.1).
@visibleForTesting
Future<void> saveAndReport(
  ScaffoldMessengerState messenger,
  AppL10n l10n,
  Future<void> Function() save,
) async {
  try {
    await save();
  } on CrayApiException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(switch (e.kind) {
        CrayErrorKind.forbidden => l10n.saveFailedRefused,
        CrayErrorKind.network => l10n.saveFailedOffline,
        _ => l10n.saveFailed,
      }),
    ));
  }
}

class _CatalogueList<T> extends ConsumerWidget {
  const _CatalogueList({
    required this.title,
    required this.cached,
    required this.rowBuilder,
    required this.onAdd,
  });

  final String title;
  final AsyncValue<Cached<List<T>>> cached;
  final Widget Function(BuildContext, T) rowBuilder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final canEdit = ref.watch(canEditCatalogueProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.catalogueAdd),
            )
          : null,
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
                // Clearance for the Add button, composed from the 4dp scale
                // rather than a one-off 88 (DESIGN 4.1, GATE-4).
                if (canEdit) const SizedBox(height: 64),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CatalogueRow extends ConsumerWidget {
  const _CatalogueRow({
    required this.name,
    required this.active,
    this.detail,
    this.amountPaise,
    this.onTap,
  });

  final String name;
  final bool active;
  final String? detail;
  final int? amountPaise;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final canEdit = ref.watch(canEditCatalogueProvider);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(name),
      subtitle: detail == null && active
          ? null
          : Wrap(
              spacing: 12,
              children: [
                if (detail != null) Text(detail!, style: text.bodySmall),
                // Hidden, not deleted: history keeps its own price snapshot.
                if (!active) Text(l10n.inactiveLabel, style: text.bodySmall),
              ],
            ),
      trailing: amountPaise == null
          ? null
          : Text(
              rupees(amountPaise!),
              style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
            ),
      onTap: canEdit ? onTap : null,
    );
  }
}
