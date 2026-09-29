import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../local/cache_db.dart';
import '../local/outbox.dart';
import 'records_repository.dart' show Cached;

/// The owner's day, and the three writes that change it.
///
/// **The promise (`RULES.md` 9.1, `ARCHITECTURE.md` 10.1): capture works with
/// the wi-fi off.** So a write is not "try the server, show an error if it
/// fails". It is:
///
///   1. write the intent to the outbox, with an id generated once;
///   2. update the cached row so the screen changes under the owner's thumb;
///   3. try to send, now if there is a connection and later if not.
///
/// Step 1 happens first and is what makes the other two safe to fail. The server
/// is authoritative about the outcome (`RULES.md` 10.3) - a rejection comes back
/// and lands in "Needs attention" with its reason, never dropped (9.6).
class DayRepository {
  DayRepository({
    required this.remote,
    required this.cache,
    required this.outbox,
    required this.salonId,
  });

  final SalonBookings remote;
  final CacheDb cache;
  final Outbox outbox;
  final String salonId;

  /// The day's appointments: the server's answer when it can be reached, this
  /// device's copy when it cannot - and the screen is told which.
  Future<Cached<List<BookingRow>>> day(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    try {
      final rows = await remote.bookingsOn(start);
      await cache.transaction(() async {
        await (cache.delete(cache.cachedBookings)
              ..where((t) =>
                  t.salonId.equals(salonId) &
                  t.startsAt.isBiggerOrEqualValue(start) &
                  t.startsAt.isSmallerThanValue(end)))
            .go();
        await cache.batch((b) => b.insertAll(
              cache.cachedBookings,
              rows.map((r) => CachedBooking(
                    id: r.id,
                    salonId: salonId,
                    customerId: r.customerId,
                    customerName: r.customerName,
                    staffName: r.staffName,
                    serviceNames: r.serviceNames,
                    startsAt: r.startsAt,
                    endsAt: r.endsAt,
                    status: r.status,
                    totalPaise: r.totalPaise,
                  )),
            ));
        await cache.into(cache.cacheStamps).insertOnConflictUpdate(
              CacheStamp(key: 'day', refreshedAt: DateTime.now()),
            );
      });
      return Cached(rows, fromCache: false, refreshedAt: DateTime.now());
    } on CrayApiException catch (e) {
      final stamp = await (cache.select(cache.cacheStamps)
            ..where((t) => t.key.equals('day')))
          .getSingleOrNull();
      return Cached(
        await _cachedDay(start, end),
        fromCache: true,
        refreshedAt: stamp?.refreshedAt,
        problem: e.kind,
      );
    }
  }

  Future<List<BookingRow>> _cachedDay(DateTime start, DateTime end) async {
    final rows = await (cache.select(cache.cachedBookings)
          ..where((t) =>
              t.salonId.equals(salonId) &
              t.startsAt.isBiggerOrEqualValue(start) &
              t.startsAt.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm(expression: t.startsAt)]))
        .get();

    return rows
        .map((r) => BookingRow(
              id: r.id,
              customerId: r.customerId,
              startsAt: r.startsAt,
              endsAt: r.endsAt,
              status: r.status,
              totalPaise: r.totalPaise,
              customerName: r.customerName,
              staffName: r.staffName,
              serviceNames: r.serviceNames,
            ))
        .toList();
  }

  /// **Mark complete: one tap, offline, idempotent** (`RULES.md` 9.4).
  ///
  /// The cached row flips immediately, because the owner is standing in front of
  /// the customer and the screen has to agree with the room. The server is still
  /// what decides; if it refuses, the row surfaces in "Needs attention" and the
  /// cache is corrected by the next refresh.
  Future<void> markComplete(String bookingId, {int? finalAmountPaise, int tipPaise = 0}) async {
    await outbox.enqueue(
      salonId: salonId,
      op: 'mark_visit_complete',
      payload: {
        'booking_id': bookingId,
        'final_amount_paise': finalAmountPaise,
        'tip_paise': tipPaise,
      },
    );

    await (cache.update(cache.cachedBookings)..where((t) => t.id.equals(bookingId)))
        .write(const CachedBookingsCompanion(status: Value('completed')));

    // The tap has already succeeded locally; this is the attempt to send it
    // now. A send that cannot happen stays in the outbox for the next drain.
    await drain();
  }

  Future<String> book({
    required String serviceId,
    required DateTime startsAt,
    String? staffId,
    String? customerId,
    List<String> addOnIds = const [],
    String? notes,
  }) async {
    final actionId = await outbox.enqueue(
      salonId: salonId,
      op: 'create_booking',
      payload: {
        'service_id': serviceId,
        'starts_at': startsAt.toIso8601String(),
        'staff_id': staffId,
        'customer_id': customerId,
        'add_on_ids': addOnIds,
        'notes': notes,
      },
    );
    await drain();
    return actionId;
  }

  /// Starts a service ONLINE, so the stylist hears "wrong code, 3 left" while the
  /// customer is still standing there. A code cannot be checked offline and a
  /// refusal must be answered at once - so this is never queued. Throws when
  /// there is no connection; the screen then offers [startWithoutCode].
  Future<StartResult> startNow(String bookingId, {String? code}) async {
    final result = await remote.startService(
      clientActionId: Outbox.newActionId(),
      bookingId: bookingId,
      code: code,
    );
    if (result.started) await _markStarted(bookingId);
    return result;
  }

  /// Starts WITHOUT the code, queued like every owner action (RULES 13). The
  /// server records why - no app, locked, or no connection - and the owner sees
  /// it (0084, 0086). Nobody is turned away.
  Future<void> startWithoutCode(String bookingId) async {
    await outbox.enqueue(
      salonId: salonId,
      op: 'start_service',
      payload: {'booking_id': bookingId},
    );
    // The row changes under the stylist's thumb; the queue catches up.
    await _markStarted(bookingId);
    await drain();
  }

  Future<void> _markStarted(String bookingId) =>
      (cache.update(cache.cachedBookings)..where((t) => t.id.equals(bookingId)))
          .write(const CachedBookingsCompanion(status: Value('in_progress')));

  /// Never cached and never queued: a quote read from a stale copy is exactly
  /// the guess this exists to prevent (0080).
  Future<CheckoutQuote> checkoutQuote(String bookingId) => remote.checkoutQuote(bookingId);

  /// Queued, like mark-complete. RULES 9.5: an offline action records INTENT,
  /// and the wallet debit runs server-side at sync. The phone never subtracts a
  /// rupee from anybody's balance - it asks, and the server decides.
  Future<void> checkout(String bookingId, {bool useWallet = true, String method = 'cash'}) async {
    await outbox.enqueue(
      salonId: salonId,
      op: 'checkout_booking',
      payload: {'booking_id': bookingId, 'use_wallet': useWallet, 'method': method},
    );
    await drain();
  }

  Future<void> cancel(String bookingId, {String? reason}) async {
    await outbox.enqueue(
      salonId: salonId,
      op: 'cancel_booking',
      payload: {'booking_id': bookingId, 'reason': reason},
    );
    await (cache.update(cache.cachedBookings)..where((t) => t.id.equals(bookingId)))
        .write(const CachedBookingsCompanion(status: Value('cancelled')));
    await drain();
  }

  /// Sends what is waiting, oldest first.
  ///
  /// Stops at the first row it cannot send: if the network is gone, the next row
  /// will not fare better, and hammering a dead connection wastes the battery of
  /// a phone that is in someone's apron. A REFUSAL is different - that row is
  /// parked in "Needs attention" and the drain carries on.
  Future<DrainReport> drain({int max = 25}) async {
    var applied = 0;
    var rejected = 0;

    for (final action in await outbox.pending(limit: max)) {
      final payload = jsonDecode(action.payload) as Map<String, Object?>;
      await outbox.markSyncing(action.clientActionId);

      try {
        switch (action.op) {
          case 'mark_visit_complete':
            await remote.markComplete(
              clientActionId: action.clientActionId,
              bookingId: payload['booking_id']! as String,
              finalAmountPaise: payload['final_amount_paise'] as int?,
              tipPaise: (payload['tip_paise'] as int?) ?? 0,
            );
          case 'create_booking':
            await remote.createBooking(
              clientActionId: action.clientActionId,
              serviceId: payload['service_id']! as String,
              startsAt: DateTime.parse(payload['starts_at']! as String),
              staffId: payload['staff_id'] as String?,
              customerId: payload['customer_id'] as String?,
              addOnIds: ((payload['add_on_ids'] as List?) ?? const [])
                  .map((e) => e as String)
                  .toList(),
              notes: payload['notes'] as String?,
            );
          case 'cancel_booking':
            await remote.cancelBooking(
              clientActionId: action.clientActionId,
              bookingId: payload['booking_id']! as String,
              reason: payload['reason'] as String?,
            );
          case 'start_service':
            final result = await remote.startService(
              clientActionId: action.clientActionId,
              bookingId: payload['booking_id']! as String,
            );
            if (!result.started) {
              // Without a code, a start is refused only when the booking cannot
              // be started at all - completed or cancelled in the meantime.
              await outbox.markRejected(action.clientActionId, 'not_startable');
              rejected++;
              continue;
            }
          case 'checkout_booking':
            await remote.checkout(
              clientActionId: action.clientActionId,
              bookingId: payload['booking_id']! as String,
              useWallet: (payload['use_wallet'] as bool?) ?? true,
              method: (payload['method'] as String?) ?? 'cash',
            );
          default:
            await outbox.markRejected(action.clientActionId, 'unknown_op');
            rejected++;
            continue;
        }
        await outbox.markApplied(action.clientActionId);
        applied++;
      } on CrayApiException catch (e) {
        if (outcomeFor(e.kind) == OutboxOutcome.unreachable) {
          await outbox.markUnreachable(action.clientActionId, e.kind.name);
          // Nothing else will get through either.
          return DrainReport(applied: applied, rejected: rejected, stoppedOffline: true);
        }
        await outbox.markRejected(action.clientActionId, e.kind.name);
        rejected++;
      }
    }

    return DrainReport(applied: applied, rejected: rejected, stoppedOffline: false);
  }
}

class DrainReport {
  const DrainReport({
    required this.applied,
    required this.rejected,
    required this.stoppedOffline,
  });

  final int applied;
  final int rejected;
  final bool stoppedOffline;
}
