import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offline promise, tested where it lives.
///
/// `RULES.md` 9: capture works offline; money and binding never do; every write
/// carries a client_action_id; **a rejected action is never silently dropped**.
class FakeBookings implements SalonBookings {
  final List<Map<String, Object?>> sent = [];
  CrayApiException? failure;

  /// Fails only the first N attempts - the shape of a flaky connection.
  int failFirst = 0;

  /// Refuses ONE operation while the others go through, which is what a real
  /// refusal looks like: the slot was taken, but the completion behind it in
  /// the queue is still perfectly valid.
  final Map<String, CrayApiException> refuse = {};

  List<BookingRow> dayRows = const [];

  @override
  Future<List<BookingRow>> bookingsOn(DateTime day) async {
    if (failure != null) throw failure!;
    return dayRows;
  }

  @override
  Future<List<Slot>> slots({
    required String serviceId,
    required DateTime day,
    String? staffId,
    List<String> addOnIds = const [],
  }) async {
    if (failure != null) throw failure!;
    return const [];
  }

  void _maybeFail(String op, Map<String, Object?> args) {
    if (failFirst > 0) {
      failFirst--;
      throw const CrayApiException(CrayErrorKind.network);
    }
    final refusal = refuse[op];
    if (refusal != null) throw refusal;
    if (failure != null) throw failure!;
    sent.add({'op': op, ...args});
  }

  @override
  Future<String> createBooking({
    required String clientActionId,
    required String serviceId,
    required DateTime startsAt,
    String? staffId,
    String? customerId,
    List<String> addOnIds = const [],
    String? notes,
  }) async {
    _maybeFail('create_booking', {'id': clientActionId, 'service_id': serviceId});
    return 'booking-1';
  }

  @override
  Future<void> markComplete({
    required String clientActionId,
    required String bookingId,
    int? finalAmountPaise,
    int tipPaise = 0,
  }) async {
    _maybeFail('mark_visit_complete', {'id': clientActionId, 'booking_id': bookingId});
  }

  @override
  Future<void> cancelBooking({
    required String clientActionId,
    required String bookingId,
    String? reason,
  }) async {
    _maybeFail('cancel_booking', {'id': clientActionId, 'booking_id': bookingId});
  }
}

void main() {
  late CacheDb cache;
  late Outbox outbox;
  late FakeBookings remote;
  late DayRepository repo;

  setUp(() {
    cache = CacheDb(NativeDatabase.memory());
    outbox = Outbox(cache);
    remote = FakeBookings();
    repo = DayRepository(remote: remote, cache: cache, outbox: outbox, salonId: 'salon-a');
  });

  tearDown(() => cache.close());

  group('mark complete', () {
    test('works with no connection, and is sent when there is one', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);

      await repo.markComplete('booking-1');

      // The owner's tap is not lost: it is queued, and the screen already shows
      // it done because the cached row was updated.
      expect(remote.sent, isEmpty);
      expect((await outbox.pending()).single.op, 'mark_visit_complete');

      // The wi-fi comes back.
      remote.failure = null;
      final report = await repo.drain();

      expect(report.applied, 1);
      expect(remote.sent.single['booking_id'], 'booking-1');
      expect(await outbox.pending(), isEmpty);
    });

    test('a retry reuses the SAME action id - that is what makes it a no-op',
        () async {
      remote.failFirst = 2;
      await repo.markComplete('booking-1');

      await repo.drain();
      await repo.drain();

      expect(remote.sent.length, 1, reason: 'sent once, after two failures');
      final pendingAfter = await outbox.pending();
      expect(pendingAfter, isEmpty);
    });

    test('the id is generated once per intent, not once per attempt', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.markComplete('booking-1');
      final first = (await outbox.pending()).single.clientActionId;

      await repo.drain();
      await repo.drain();
      final after = (await outbox.pending()).single;

      expect(after.clientActionId, first);
      expect(after.attempts, greaterThan(1), reason: 'attempts counted, id unchanged');
    });
  });

  group('a refusal is not a network failure', () {
    test('a taken slot goes to Needs attention with its reason, and is not retried',
        () async {
      remote.failure = const CrayApiException(CrayErrorKind.slotTaken);

      await repo.book(serviceId: 'service-1', startsAt: DateTime.now().add(const Duration(days: 1)));

      final rejected = await outbox.rejected();
      expect(rejected.single.lastError, 'slotTaken');
      expect(await outbox.pending(), isEmpty, reason: 'it will never succeed by asking again');
    });

    test('no signal keeps it pending, so it does NOT clutter Needs attention', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);

      await repo.markComplete('booking-1');

      expect(await outbox.rejected(), isEmpty);
      expect((await outbox.pending()).single.status, 'pending');
    });

    test('a drain stops at the first unreachable row rather than hammering', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.markComplete('booking-1');
      await repo.markComplete('booking-2');
      await repo.markComplete('booking-3');

      final report = await repo.drain();

      expect(report.stoppedOffline, isTrue);
      expect(report.applied, 0);
      expect((await outbox.pending()).length, 3, reason: 'all three still waiting');
    });

    test('a refusal does not stop the queue - the work behind it still goes', () async {
      // Queue two things while offline: a booking, then a completion.
      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.book(serviceId: 'service-1', startsAt: DateTime.now().add(const Duration(days: 1)));
      await repo.markComplete('booking-9');
      expect((await outbox.pending()).length, 2);

      // The connection returns, but in the meantime someone else took the slot.
      remote.failure = null;
      remote.refuse['create_booking'] = const CrayApiException(CrayErrorKind.slotTaken);

      final report = await repo.drain();

      expect(report.rejected, 1, reason: 'the booking cannot succeed and is parked');
      expect(report.applied, 1, reason: 'the completion behind it is still valid');
      expect(remote.sent.single['op'], 'mark_visit_complete');
      expect((await outbox.rejected()).single.lastError, 'slotTaken');
    });
  });

  group('nothing is dropped', () {
    test('a rejected action can be retried by hand, keeping its id', () async {
      remote.failure = const CrayApiException(CrayErrorKind.slotTaken);
      await repo.book(serviceId: 'service-1', startsAt: DateTime.now().add(const Duration(days: 1)));

      final row = (await outbox.rejected()).single;
      // The owner fixed the cause - picked a different time, or the other
      // booking was cancelled - and taps "try again".
      remote.failure = null;
      await outbox.retry(row.clientActionId);
      await repo.drain();

      expect(remote.sent.single['id'], row.clientActionId,
          reason: 'the same id: if the server HAD applied it, this is a replay');
      expect(await outbox.rejected(), isEmpty);
    });

    test('discarding is explicit - only from Needs attention, never automatic', () async {
      remote.failure = const CrayApiException(CrayErrorKind.slotTaken);
      await repo.book(serviceId: 'service-1', startsAt: DateTime.now().add(const Duration(days: 1)));

      final row = (await outbox.rejected()).single;
      await outbox.discard(row.clientActionId);

      expect(await outbox.rejected(), isEmpty);
      expect(await outbox.pending(), isEmpty);
    });

    test('the outbox survives a cache wipe - it is not a copy of anything', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.markComplete('booking-1');

      await cache.wipe();

      expect((await outbox.pending()).length, 1,
          reason: 'unsent work is the only local source of truth (ARCH 10.2)');
    });

    test('work for a salon this device left is MARKED, not deleted', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.markComplete('booking-1');

      await cache.rejectOutboxFor('salon-a', 'salon_changed');

      expect(await outbox.pending(), isEmpty);
      expect((await outbox.rejected()).single.lastError, 'salon_changed');
    });
  });

  group('the day list', () {
    test('comes from the cache when the server cannot be reached', () async {
      final start = DateTime.now().add(const Duration(hours: 2));
      remote.dayRows = [
        BookingRow(
          id: 'b1',
          customerId: 'c1',
          startsAt: start,
          endsAt: start.add(const Duration(minutes: 30)),
          status: 'confirmed',
          totalPaise: 40000,
          customerName: 'Asha',
          serviceNames: 'Haircut',
        ),
      ];

      final fresh = await repo.day(start);
      expect(fresh.fromCache, isFalse);

      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.day(start);

      expect(cached.fromCache, isTrue);
      expect(cached.value.single.customerName, 'Asha');
    });

    test('a completed booking shows as completed immediately, before it is sent',
        () async {
      final start = DateTime.now().add(const Duration(hours: 2));
      remote.dayRows = [
        BookingRow(
          id: 'b1',
          customerId: 'c1',
          startsAt: start,
          endsAt: start.add(const Duration(minutes: 30)),
          status: 'confirmed',
          totalPaise: 40000,
        ),
      ];
      await repo.day(start);

      remote.failure = const CrayApiException(CrayErrorKind.network);
      await repo.markComplete('b1');

      final cached = await repo.day(start);
      expect(cached.value.single.status, 'completed',
          reason: 'the screen agrees with the room while the queue catches up');
    });
  });
}
