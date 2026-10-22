import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/celebrate.dart';
import '../../core/ui/live.dart';
import '../../core/ui/load_failed.dart';
import '../../core/ui/success_check.dart';
import '../../core/format/money.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/skeleton.dart';
import '../../core/ui/notice.dart';
import '../../data/local/outbox.dart';
import '../../domain/customer/customer.dart';
import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';
import 'book_screen.dart' show DetailRow;

/// C9 - one of the customer's bookings.
///
/// "Cancel booking" sits high on the screen, away from the thumb, and asks
/// first: the design's answer to a cancel pressed by accident on the way to
/// something else. It is offered only for a booking that has not started - the
/// server would refuse nothing else but a completed one, and cancelling a
/// haircut already in progress is a conversation, not a button.
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({required this.id, this.justBooked = false, super.key});

  final String id;

  /// Opened straight from Confirm: the success check and a burst of confetti,
  /// once, above the details.
  final bool justBooked;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;
  String? _actionId;

  Future<void> _cancel(UpcomingBooking booking) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.bookingCancelAsk,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.bookingCancelBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              // Keeping it is the filled, default-looking choice.
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.bookingKeep),
              ),
              const SizedBox(height: 8),
              // The red is on the icon: the fixed danger colour reads 3.4:1 as
              // text on the glass, under the 4.5:1 a label needs. The words
              // stay in the readable ink, so it is never colour alone.
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: Icon(
                  Icons.event_busy_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                label: Text(l10n.bookingCancel),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true || !mounted) return;

    final api = ref.read(customerBookingsProvider);
    if (api == null) return;
    // One id for this cancel, however many times it is retried (RULES 9.3).
    _actionId ??= Outbox.newActionId();
    setState(() => _busy = true);
    try {
      await api.cancelBooking(
        clientActionId: _actionId!,
        bookingId: booking.id,
      );
      ref.invalidate(bookingDetailProvider(widget.id));
      ref.invalidate(upcomingProvider);
      messenger.notice(l10n.bookingCancelled);
    } on CrayApiException {
      messenger.notice(l10n.bookingCancelFailed, kind: NoticeKind.problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final booking = ref.watch(bookingDetailProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: switch (booking) {
        AsyncData(:final value?) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (widget.justBooked && value.cancellable)
              _Booked(booking: value)
            else
              Text(l10n.bookingTitle, style: text.headlineMedium),
            const SizedBox(height: 12),
            // A booking that did not happen says so as a chip; a live one
            // shows where it is up to instead.
            if (value.status == 'cancelled' || value.status == 'no_show')
              Align(
                alignment: Alignment.centerLeft,
                child: _StatusChip(value.status),
              ),
            // Where it is up to, as a food app tracks an order: booked, the
            // day, done - the current step live (DESIGN 7: pings, then rests).
            if (value.status != 'cancelled' && value.status != 'no_show') ...[
              const SizedBox(height: 16),
              StepTracker(
                steps: [l10n.bookingStepBooked, l10n.bookingStepDay, l10n.bookingStepDone],
                current: value.status == 'completed'
                    ? 3
                    : DateUtils.dateOnly(DateTime.now()).isBefore(DateUtils.dateOnly(value.startsAt))
                    ? 1
                    : 2,
              ),
            ],
            const SizedBox(height: 8),
            DetailRow(
              label: l10n.bookDateTime,
              value:
                  '${ml.formatShortMonthDay(value.startsAt)} · '
                  '${ml.formatTimeOfDay(TimeOfDay.fromDateTime(value.startsAt))}',
            ),
            DetailRow(label: l10n.bookService, value: value.serviceNames),
            if (value.staffName != null)
              DetailRow(label: l10n.bookStylist, value: value.staffName!),
            DetailRow(
              label: l10n.bookTakesAbout,
              value: l10n.bookMinutes(value.minutes),
            ),
            DetailRow(
              label: l10n.bookTotal,
              value: rupees(value.totalPaise),
              emphasis: true,
            ),
            const SizedBox(height: 20),
            Text(l10n.bookPayAfter, style: text.bodyMedium),
            if (value.cancellable) ...[
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _busy ? null : () => _cancel(value),
                  icon: Icon(
                    Icons.event_busy_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(l10n.bookingCancel),
                ),
              ),
            ],
          ],
        ),
        AsyncData() => Center(
          child: Text(l10n.bookingNotFound, style: text.bodyLarge),
        ),
        AsyncValue(hasError: true) => LoadFailed(
          onRetry: () => ref.invalidate(bookingDetailProvider(widget.id)),
        ),
        _ => const SkeletonList(padding: EdgeInsets.all(16)),
      },
    );
  }
}

/// The moment after Confirm: confetti once, the success check, "You're
/// booked", and when - then the details underneath, as usual.
class _Booked extends StatelessWidget {
  const _Booked({required this.booking});

  final UpcomingBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(left: 0, right: 0, top: -48, child: Celebrate(height: 240)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const SuccessCheck(size: 72),
            const SizedBox(height: 16),
            Text(l10n.bookingBookedTitle, style: text.headlineMedium),
            const SizedBox(height: 4),
            Text(
              l10n.bookingBookedBody(
                ml.formatFullDate(booking.startsAt),
                ml.formatTimeOfDay(TimeOfDay.fromDateTime(booking.startsAt)),
              ),
              style: text.bodyLarge,
            ),
          ],
        ),
      ],
    );
  }
}

/// Status in the FIXED status colours, with an icon and a word - never the
/// brand, never colour alone (DESIGN 3.4).
class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final g = CrayGlass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status) {
      'cancelled' => (
        Icons.event_busy_outlined,
        l10n.bookingCancelledStatus,
        scheme.error,
      ),
      'no_show' => (
        Icons.event_busy_outlined,
        l10n.bookingMissed,
        scheme.error,
      ),
      'in_progress' => (Icons.content_cut, l10n.bookingInProgress, g.success),
      _ => (Icons.event_available_outlined, l10n.bookingBooked, g.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: g.face,
        boxShadow: g.shadows,
        borderRadius: BorderRadius.circular(g.radiusChip),
        border: Border.all(color: g.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
