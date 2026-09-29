import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/outbox.dart';
import '../../data/repositories/day_repository.dart';
import '../../data/repositories/records_repository.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';

/// The owner's day (O1).
///
/// Every action here goes through the outbox first, so a tap is never lost to a
/// dead connection (`RULES.md` 9.1). The controller's job is only to say what
/// the screen shows next - it does not decide whether the work succeeded, the
/// server does.
class DayState {
  const DayState({
    this.bookings = const [],
    this.loading = true,
    this.fromCache = false,
    this.refreshedAt,
    this.date,
  });

  final List<BookingRow> bookings;
  final bool loading;
  final bool fromCache;
  final DateTime? refreshedAt;
  final DateTime? date;

  DayState copyWith({
    List<BookingRow>? bookings,
    bool? loading,
    bool? fromCache,
    DateTime? refreshedAt,
    DateTime? date,
  }) =>
      DayState(
        bookings: bookings ?? this.bookings,
        loading: loading ?? this.loading,
        fromCache: fromCache ?? this.fromCache,
        refreshedAt: refreshedAt ?? this.refreshedAt,
        date: date ?? this.date,
      );
}

class DayController extends Notifier<DayState> {
  @override
  DayState build() {
    Future.microtask(refresh);
    return DayState(date: DateTime.now());
  }

  DayRepository? get _repo => ref.read(dayRepositoryProvider);

  Future<void> refresh() async {
    final repo = _repo;
    final date = state.date ?? DateTime.now();
    if (repo == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true);
    // Send anything waiting before reading: otherwise the list can contradict
    // what the owner already did, which reads as the app losing their work.
    await repo.drain();
    final result = await repo.day(date);
    state = state.copyWith(
      bookings: result.value,
      loading: false,
      fromCache: result.fromCache,
      refreshedAt: result.refreshedAt,
    );
    _refreshCounts();
  }

  /// One tap, no confirmation dialog (`DESIGN.md` 6.4). The row changes
  /// immediately because the cache changed; the queue catches up.
  Future<void> complete(BookingRow booking) async {
    final repo = _repo;
    if (repo == null) return;

    _show(booking.id, 'completed');
    await repo.markComplete(booking.id);
    _refreshCounts();
  }

  void _show(String bookingId, String status) {
    state = state.copyWith(
      bookings: [
        for (final b in state.bookings) b.id == bookingId ? b.withStatus(status) : b,
      ],
    );
  }

  /// The counts are reads, so whoever changes the queue refreshes them.
  void _refreshCounts() {
    ref.invalidate(pendingSyncProvider);
    ref.invalidate(needsAttentionProvider);
    ref.invalidate(rejectedActionsProvider);
  }

  /// Starts ONLINE with the customer's code, so a wrong one is answered while
  /// they are still standing there. Throws [CrayApiException] (network) when
  /// there is no connection - the sheet then offers [startWithoutCode].
  Future<StartResult> start(BookingRow booking, {required String code}) async {
    final repo = _repo;
    if (repo == null) return const StartResult.refused(StartRefusal.notStartable);
    final result = await repo.startNow(booking.id, code: code);
    if (result.started) _show(booking.id, 'in_progress');
    return result;
  }

  /// Without the code - no app, locked, or no connection. Queued; never
  /// silent: the server records why and the owner sees it (0084, 0086).
  Future<void> startWithoutCode(BookingRow booking) async {
    final repo = _repo;
    if (repo == null) return;
    // Like mark-complete: the row changes under the stylist's thumb, and the
    // queue catches up.
    _show(booking.id, 'in_progress');
    await repo.startWithoutCode(booking.id);
    _refreshCounts();
  }

  /// Queued through the outbox. The row does NOT turn "paid" here: whether the
  /// money arrived is the server's to say, and the day view only shows paid once
  /// a refresh brings back `payment_status = paid` (RULES 9).
  Future<void> checkout(BookingRow booking, {required bool useWallet, required String method}) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.checkout(booking.id, useWallet: useWallet, method: method);
    _refreshCounts();
    await refresh();
  }

  Future<CheckoutQuote?> quote(BookingRow booking) async {
    final repo = _repo;
    if (repo == null) return null;
    try {
      return await repo.checkoutQuote(booking.id);
    } on CrayApiException {
      // No connection, or the server refused. Either way: no number, no guess.
      return null;
    }
  }

  Future<void> cancel(BookingRow booking, {String? reason}) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.cancel(booking.id, reason: reason);
    _refreshCounts();
    await refresh();
  }
}

final dayControllerProvider = NotifierProvider<DayController, DayState>(DayController.new);

/// How much work is waiting to reach the server. Watched by the day view so the
/// owner can see their taps are queued rather than lost.
final pendingSyncProvider = FutureProvider<int>((ref) async {
  final outbox = ref.watch(outboxProvider);
  if (outbox == null) return 0;
  return outbox.pendingCount();
});

/// How much the server REFUSED. This is the badge on "Needs attention", and it
/// is deliberately separate from the pending count: one is patience, the other
/// is a decision somebody has to make (RULES 9.6).
final needsAttentionProvider = FutureProvider<int>((ref) async {
  final outbox = ref.watch(outboxProvider);
  if (outbox == null) return 0;
  return outbox.rejectedCount();
});

/// Everything the server refused, with what it was and why.
final rejectedActionsProvider = FutureProvider((ref) async {
  final outbox = ref.watch(outboxProvider);
  if (outbox == null) return const [];
  return outbox.rejected();
});

/// Turns an error kind stored on a rejected row into something a person can act
/// on. The row stores the kind, never a server message: a raw server string is
/// not written for the owner of a salon.
String attentionReasonKey(String? lastError) => switch (lastError) {
      'slotTaken' => 'slot_taken',
      'forbidden' => 'forbidden',
      'notCompletable' => 'not_completable',
      'salonUnavailable' => 'salon_unavailable',
      'salon_changed' => 'salon_changed',
      _ => 'generic',
    };

/// Re-exported so the screens can name the outcome without importing the data
/// layer's internals.
typedef CachedList<T> = Cached<List<T>>;

/// The kinds a screen may show as "you are offline" rather than a refusal.
bool isOfflineKind(CrayErrorKind? kind) =>
    kind != null && outcomeFor(kind) == OutboxOutcome.unreachable;
