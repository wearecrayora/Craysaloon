import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/ui/cache_banner.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import '../salon/salon_account.dart';
import 'checkout_sheet.dart';
import 'start_sheet.dart';
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
        // The salon's own mark and name, as on every screen (Claude Design O1).
        // The dashboard is a tab of its own now (OwnerShell).
        title: const SalonTitle(),
        actions: [
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
            // Why nothing can be recorded, BEFORE a tap is refused (0087).
            const ReadOnlyBanner(),
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
                onRefresh: () {
                  // A payment recorded in the console lifts read-only at once;
                  // pulling down is how the owner sees that.
                  ref.invalidate(salonBillingProvider);
                  return ref.read(dayControllerProvider.notifier).refresh();
                },
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
                      // The customer said "cash at the counter" in their app. It
                      // settles nothing - this row still needs Take payment.
                      _ when booking.counterRequested =>
                        '${l10n.dayDone} · ${l10n.payCounterRequested}',
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
          else if (booking.isInProgress)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.dayInProgress, style: text.labelLarge),
                const SizedBox(height: 8),
                FilledButton(
                  // Mark-complete is still ONE TAP, no dialog (DESIGN 6.4,
                  // RULES 13) - it moved from the booked row to the in-progress
                  // one when the start code arrived (0084).
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => ref.read(dayControllerProvider.notifier).complete(booking),
                  child: Text(l10n.markComplete),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    // Start, with the customer's code where they have the app
                    // (0084). 56dp: pressed one-handed between customers.
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () => StartSheet.open(context, booking),
                    child: Text(l10n.startTitle),
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
