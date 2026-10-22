import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/theme/motion.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/live.dart';
import '../../core/ui/load_failed.dart';
import '../../core/ui/salon_mark.dart';
import '../../core/ui/service_icon.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/customer/customer.dart';
import '../../domain/records/records.dart' show Service;
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';
import '../customer/documents_screen.dart' show DocumentSheet;
import '../visit/visit_cards.dart' show PayBillSheet, billsProvider;

/// Which bookings are showing.
enum BookingFilter { all, upcoming, done, cancelled }

/// My bookings (21 Oct 2026): every booking in one place, the way an order
/// list is - what is coming up, what was done (paid or not), and what was
/// cancelled or missed. Newest at the top within each, grouped by month.
///
/// Each one does the thing you would want from it: an upcoming booking opens
/// to its details (and cancel), an unpaid visit offers Pay now, a paid one
/// opens its bill, and anything in the past offers Book again - the same
/// service, chosen and nothing else (RULES: nothing is pre-selected for them).
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({this.initialFilter = BookingFilter.all, super.key});

  final BookingFilter initialFilter;

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

/// One row on the list, whatever kind it is.
sealed class _Entry {
  DateTime get when;
}

class _Upcoming extends _Entry {
  _Upcoming(this.booking);
  final UpcomingBooking booking;
  @override
  DateTime get when => booking.startsAt;
}

class _Done extends _Entry {
  _Done(this.visit);
  final PastVisit visit;
  @override
  DateTime get when => visit.completedAt;
}

class _Closed extends _Entry {
  _Closed(this.booking);
  final UpcomingBooking booking;
  @override
  DateTime get when => booking.startsAt;
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  late BookingFilter _filter = widget.initialFilter;

  Future<void> _refresh() async {
    ref.invalidate(upcomingProvider);
    ref.invalidate(historyProvider);
    ref.invalidate(closedBookingsProvider);
    ref.invalidate(billsProvider);
    ref.invalidate(documentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final upcoming = ref.watch(upcomingProvider);
    final history = ref.watch(historyProvider);
    final closed = ref.watch(closedBookingsProvider);
    // Read ahead, so Pay now and a bill open without a wait.
    ref.watch(billsProvider);
    ref.watch(documentsProvider);

    final all = [upcoming, history, closed];
    final waiting = all.any((a) => !a.hasValue && !a.hasError);
    final failed = all.every((a) => a.hasError && !a.hasValue);

    final next = (upcoming.value ?? const <UpcomingBooking>[]).map(_Upcoming.new).toList();
    final done = (history.value ?? const <PastVisit>[]).map(_Done.new).toList();
    final off = (closed.value ?? const <UpcomingBooking>[]).map(_Closed.new).toList();
    final past = <_Entry>[...done, ...off]..sort((a, b) => b.when.compareTo(a.when));

    final showNext = _filter == BookingFilter.all || _filter == BookingFilter.upcoming;
    final shownPast = switch (_filter) {
      BookingFilter.all => past,
      BookingFilter.upcoming => const <_Entry>[],
      BookingFilter.done => done,
      BookingFilter.cancelled => off,
    };

    final children = <Widget>[
      Text(l10n.bookingsTitle, style: text.headlineMedium),
      const SizedBox(height: 12),
      _Filters(
        value: _filter,
        counts: {
          BookingFilter.all: next.length + past.length,
          BookingFilter.upcoming: next.length,
          BookingFilter.done: done.length,
          BookingFilter.cancelled: off.length,
        },
        onChanged: (f) => setState(() => _filter = f),
      ),
      const SizedBox(height: 16),
    ];

    if (waiting && next.isEmpty && past.isEmpty) {
      children.add(const SkeletonList(rows: 4));
    } else if (failed) {
      children.add(LoadFailed(inline: true, onRetry: _refresh));
    } else if ((showNext ? next.length : 0) + shownPast.length == 0) {
      children.add(_Empty(filter: _filter));
    } else {
      if (showNext && next.isNotEmpty) {
        children.add(_Heading(l10n.bookingsUpcoming));
        for (final e in next) {
          children
            ..add(_UpcomingCard(booking: e.booking))
            ..add(const SizedBox(height: 12));
        }
      }
      String? month;
      for (final e in shownPast) {
        final m = _month(context, e.when);
        if (m != month) {
          month = m;
          children.add(_Heading(m));
        }
        children
          ..add(switch (e) {
            _Done(:final visit) => _DoneCard(visit: visit),
            _Closed(:final booking) => _ClosedCard(booking: booking),
            _Upcoming(:final booking) => _UpcomingCard(booking: booking),
          })
          ..add(const SizedBox(height: 12));
      }
      // Partly loaded: say what is missing rather than imply it is all here.
      if (all.any((a) => a.hasError && !a.hasValue)) {
        children.add(LoadFailed(inline: true, onRetry: _refresh));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // The list cross-fades when the filter changes, so it is clear the
            // same list was narrowed rather than a new page opened.
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.standard),
              child: Column(
                key: ValueKey(_filter),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _month(BuildContext context, DateTime d) {
    final tag = Localizations.localeOf(context).toLanguageTag();
    try {
      return DateFormat.yMMMM(tag).format(d);
    } catch (_) {
      return DateFormat.yMMMM().format(d);
    }
  }
}

/// All · Upcoming · Done · Cancelled, as chips you can see and tap, each with
/// its count - the chosen one filled, changing in a 120ms beat (DESIGN 7.2).
class _Filters extends StatelessWidget {
  const _Filters({required this.value, required this.counts, required this.onChanged});

  final BookingFilter value;
  final Map<BookingFilter, int> counts;
  final ValueChanged<BookingFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    String label(BookingFilter f) => switch (f) {
      BookingFilter.all => l10n.bookingsAll,
      BookingFilter.upcoming => l10n.bookingsUpcoming,
      BookingFilter.done => l10n.bookingsDone,
      BookingFilter.cancelled => l10n.bookingsCancelled,
    };
    // One row that scrolls sideways, as the food apps' filter chips do: the
    // list starts right under it instead of three rows down.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, f) in BookingFilter.values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text('${label(f)} · ${counts[f] ?? 0}'),
              selected: value == f,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onChanged(f),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// The date as a block - day large, month under it - the ticket look.
class _DateBlock extends StatelessWidget {
  const _DateBlock(this.date, {this.muted = false});

  final DateTime date;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tag = Localizations.localeOf(context).toLanguageTag();
    String month;
    try {
      month = DateFormat.MMM(tag).format(date);
    } catch (_) {
      month = DateFormat.MMM().format(date);
    }
    final bg = muted ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final fg = muted ? scheme.onSurface : scheme.onPrimaryContainer;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(
            '${date.day}',
            style: text.titleLarge?.copyWith(
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(month, style: text.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// A coming booking: date block, time (with a live dot when it is today), what
/// and with whom, and when it is - "Today", "Tomorrow", "In 3 days".
class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.booking});

  final UpcomingBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final days = DateUtils.dateOnly(booking.startsAt).difference(DateUtils.dateOnly(now)).inDays;
    final today = days == 0;
    final when = switch (days) {
      <= 0 => l10n.bookingsToday,
      1 => l10n.bookingsTomorrow,
      _ => l10n.bookingsInDays(days),
    };
    return Pressable(
      onTap: () => context.push('/booking/${booking.id}'),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _DateBlock(booking.startsAt),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (today) ...[const LiveDot(size: 8), const SizedBox(width: 4)],
                      Flexible(
                        child: Text(
                          '$when · ${ml.formatTimeOfDay(TimeOfDay.fromDateTime(booking.startsAt))}',
                          style: text.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  if (booking.serviceNames.isNotEmpty)
                    Text(booking.serviceNames, style: text.titleMedium),
                  if ((booking.staffName ?? '').isNotEmpty)
                    Text(l10n.homeWithStylist(booking.staffName!), style: text.bodySmall),
                  // In the column, not beside it: at large text a trailing
                  // amount squeezes the row off the screen.
                  Text(
                    rupees(booking.totalPaise),
                    style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// A visit that happened: paid or not, Pay now when not, its bill when paid,
/// and Book again.
class _DoneCard extends ConsumerWidget {
  const _DoneCard({required this.visit});

  final PastVisit visit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bill = (ref.watch(billsProvider).value ?? const [])
        .where((b) => b.visitId == visit.id)
        .firstOrNull;
    final doc = (ref.watch(documentsProvider).value ?? const [])
        .where((d) => d.visitId == visit.id)
        .firstOrNull;

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: doc == null ? null : () => DocumentSheet.open(context, doc),
            child: Row(
              children: [
                _DateBlock(visit.completedAt, muted: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            visit.paid ? Icons.check_circle : Icons.schedule,
                            size: 16,
                            color: visit.paid ? g.success : scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              visit.paid ? l10n.historyPaid : l10n.historyUnpaid,
                              style: text.labelMedium,
                            ),
                          ),
                        ],
                      ),
                      if (visit.serviceNames.isNotEmpty)
                        Text(visit.serviceNames, style: text.titleMedium),
                      if ((visit.staffName ?? '').isNotEmpty)
                        Text(l10n.homeWithStylist(visit.staffName!), style: text.bodySmall),
                      Text(
                        rupees(visit.amountPaise),
                        style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!visit.paid && bill != null) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: () => PayBillSheet.open(context, bill),
                    child: Text(l10n.bookingsPayNow),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: _BookAgain(names: visit.serviceNames)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A booking that did not happen: what it was, why (cancelled or missed), and
/// Book again.
class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.booking});

  final UpcomingBooking booking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: () => context.push('/booking/${booking.id}'),
            child: Row(
              children: [
                _DateBlock(booking.startsAt, muted: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_busy_outlined, size: 16, color: scheme.error),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              booking.status == 'no_show'
                                  ? l10n.bookingMissed
                                  : l10n.bookingCancelledStatus,
                              style: text.labelMedium,
                            ),
                          ),
                        ],
                      ),
                      if (booking.serviceNames.isNotEmpty)
                        Text(booking.serviceNames, style: text.titleMedium),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _BookAgain(names: booking.serviceNames),
        ],
      ),
    );
  }
}

/// "Book again": the first service of what they had, if the salon still offers
/// it, chosen on the booking - nothing else carried over (add-ons are never
/// pre-ticked). If it is gone from the menu, booking opens with nothing chosen.
class _BookAgain extends ConsumerWidget {
  const _BookAgain({required this.names});

  final String names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final first = names.split(' + ').first.trim().toLowerCase();
    final Service? match = (ref.watch(bookableServicesProvider).value ?? const <Service>[])
        .where((s) => s.name.trim().toLowerCase() == first)
        .firstOrNull;
    return OutlinedButton.icon(
      onPressed: () => context.go(match == null ? '/book' : '/book?service=${match.id}'),
      icon: Icon(match == null ? Icons.replay : serviceIcon(match.name, category: match.category)),
      label: Text(l10n.bookingsBookAgain),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final BookingFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.event_note_outlined, size: 48, color: text.bodySmall?.color),
          const SizedBox(height: 12),
          Text(
            switch (filter) {
              BookingFilter.cancelled => l10n.bookingsNoneCancelled,
              BookingFilter.done => l10n.bookingsNoneDone,
              _ => l10n.bookingsNone,
            },
            style: text.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/book'),
            icon: const Icon(Icons.event_available_outlined),
            label: Text(l10n.homeBookNow),
          ),
        ],
      ),
    );
  }
}
