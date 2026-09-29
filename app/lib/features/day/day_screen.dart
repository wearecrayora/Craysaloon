import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/ui/cache_banner.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import 'checkout_sheet.dart';
import 'day_controller.dart';

/// O1 - the day view. **The screen everything depends on.**
///
/// Mark-complete is one tap with no confirmation dialog (`DESIGN.md` 6.4) and a
/// 56dp target, because it is pressed with a customer standing there and a comb
/// in the other hand. It works with the wi-fi off (`RULES.md` 9.1): the row
/// changes immediately, the work queues, and the count of what is waiting is on
/// screen so nobody wonders whether a tap was lost.
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final state = ref.watch(dayControllerProvider);
    final pending = ref.watch(pendingSyncProvider).value ?? 0;
    final attention = ref.watch(needsAttentionProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dayTitle),
        actions: [
          // Owners and managers only: owner_dashboard refuses anyone else, and
          // offering staff a button that answers "not allowed" is worse than no
          // button at all.
          if (ref.watch(canEditCatalogueProvider))
            IconButton(
              tooltip: l10n.dashTitle,
              onPressed: () => context.push('/dashboard'),
              icon: const Icon(Icons.insights_outlined),
            ),
          if (attention > 0)
            IconButton(
              tooltip: l10n.needsAttention,
              onPressed: () => context.go('/attention'),
              icon: Badge(
                label: Text('$attention'),
                child: const Icon(Icons.error_outline),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/day/walk-in'),
        icon: const Icon(Icons.add),
        label: Text(l10n.walkInTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.fromCache) CacheBanner(refreshedAt: state.refreshedAt),
            if (pending > 0)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_send, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.daySyncPending(pending),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(dayControllerProvider.notifier).refresh(),
                child: state.loading && state.bookings.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : state.bookings.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [Text(l10n.dayEmpty)],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            // +1 for clearance under the Walk-in button,
                            // composed from the 4dp scale (DESIGN 4.1, GATE-4).
                            itemCount: state.bookings.length + 1,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => i == state.bookings.length
                                ? const SizedBox(height: 64)
                                : _BookingTile(booking: state.bookings[i]),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingTile extends ConsumerWidget {
  const _BookingTile({required this.booking});

  final BookingRow booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final title = booking.customerName?.trim().isNotEmpty == true
        ? booking.customerName!
        : l10n.walkInCustomer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat.jm().format(booking.startsAt),
                      style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                    ),
                    Text(title, style: text.bodyLarge),
                    if (booking.serviceNames.isNotEmpty)
                      Text(booking.serviceNames, style: text.bodySmall),
                    if (booking.staffName != null)
                      Text(booking.staffName!, style: text.bodySmall),
                  ],
                ),
              ),
              Text(
                rupees(booking.totalPaise),
                style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (booking.status == 'completed')
            Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                // "Paid" only when the SERVER says so. Never inferred from a tap.
                Expanded(
                  child: Text(
                    switch (booking.paymentStatus) {
                      'paid' => '${l10n.dayDone} · ${l10n.payPaid}',
                      'partial' => '${l10n.dayDone} · ${l10n.payPartial}',
                      _ => l10n.dayDone,
                    },
                    style: text.labelLarge,
                  ),
                ),
                if (booking.awaitsPayment)
                  OutlinedButton(
                    // An explicit, FINITE minimum width. The theme gives buttons
                    // Size.fromHeight(48) - infinite width - so a button inside a
                    // Row without Expanded asserts at layout. The referral screen
                    // hit the same trap.
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => CheckoutSheet.open(context, booking),
                    child: Text(l10n.payTake),
                  ),
              ],
            )
          else if (booking.status == 'cancelled')
            Text(l10n.dayCancelled, style: text.labelLarge)
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    // 56dp, not 48: this is THE button of the product, pressed
                    // one-handed between customers (DESIGN 6.4).
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () =>
                        ref.read(dayControllerProvider.notifier).complete(booking),
                    child: Text(l10n.markComplete),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n.dayCancelBooking,
                  onPressed: () => ref.read(dayControllerProvider.notifier).cancel(booking),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
