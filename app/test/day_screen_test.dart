import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outbox_test.dart' show FakeBookings;
import 'support/fake_cray_api.dart';

/// O1, O3 - the day view and "Needs attention", as the owner meets them.
///
/// The gates here, rather than checks:
///   * **one tap completes**, with no confirmation dialog (`DESIGN.md` 6.4)
///   * it works with **no connection**, and the screen says work is waiting
///     rather than leaving the owner wondering (`RULES.md` 9.1)
///   * a refusal reaches **Needs attention** with a reason and a one-tap fix,
///     and is never dropped (`RULES.md` 9.6)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  late FakeBookings remote;

  setUp(() {
    cache = CacheDb(NativeDatabase.memory());
    remote = FakeBookings();
  });

  tearDown(() => cache.close());

  BookingRow booking({String id = 'b1', String status = 'confirmed'}) {
    final start = DateTime.now().add(const Duration(hours: 2));
    return BookingRow(
      id: id,
      customerId: 'c1',
      startsAt: start,
      endsAt: start.add(const Duration(minutes: 30)),
      status: status,
      totalPaise: 40000,
      customerName: 'Asha',
      serviceNames: 'Haircut',
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final outbox = Outbox(cache);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'owner', salonId: 'salon-a'),
          ),
          cacheDbProvider.overrideWithValue(cache),
          outboxProvider.overrideWithValue(outbox),
          dayRepositoryProvider.overrideWithValue(
            DayRepository(remote: remote, cache: cache, outbox: outbox, salonId: 'salon-a'),
          ),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the day lists what is booked, with the time and the money', (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('₹400'), findsOneWidget);
    expect(find.text('Mark complete'), findsOneWidget);
  });

  testWidgets('ONE TAP completes - no dialog, no confirmation step', (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    // No dialog appeared, and the row already reads as done.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Mark complete'), findsNothing);
    expect(remote.sent.single['op'], 'mark_visit_complete');
  });

  testWidgets('it works with NO connection, and says work is waiting', (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    remote.failure = const CrayApiException(CrayErrorKind.network);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget, reason: 'the screen agrees with the room');
    expect(find.text('1 change waiting to sync'), findsOneWidget,
        reason: 'the owner must never wonder whether the tap was lost');
    expect(remote.sent, isEmpty);
  });

  testWidgets('a refusal reaches Needs attention, with a reason and a fix',
      (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    remote.refuse['mark_visit_complete'] =
        const CrayApiException(CrayErrorKind.notCompletable);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    // The badge appears on the day view...
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pumpAndSettle();

    // ...and the inbox says what it was and why, in words, not error codes.
    expect(find.text('Mark complete'), findsOneWidget);
    expect(find.text('That appointment was already finished or cancelled.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('retrying from Needs attention reuses the same action id', (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    remote.refuse['mark_visit_complete'] = const CrayApiException(CrayErrorKind.slotTaken);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    final rejectedId = (await Outbox(cache).rejected()).single.clientActionId;

    // Whatever it was is fixed; the owner taps Try again.
    remote.refuse.clear();
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(remote.sent.single['id'], rejectedId,
        reason: 'the same id means the server can recognise a replay (RULES 9.3)');
    expect(find.text('Nothing needs attention.'), findsOneWidget);
  });

  testWidgets('discarding is a deliberate act, and then it is gone', (tester) async {
    remote.dayRows = [booking()];
    await pump(tester);

    remote.refuse['mark_visit_complete'] = const CrayApiException(CrayErrorKind.forbidden);
    await tester.tap(find.text('Mark complete'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pumpAndSettle();
    expect(find.text('Your account cannot do this. Ask the owner.'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing needs attention.'), findsOneWidget);
  });

  testWidgets('an empty day says so rather than showing a spinner forever',
      (tester) async {
    remote.dayRows = const [];
    await pump(tester);
    expect(find.text('Nothing booked today.'), findsOneWidget);
  });

  testWidgets('nothing clips at 200% text scale', (tester) async {
    remote.dayRows = [booking()];
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final outbox = Outbox(cache);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'owner', salonId: 'salon-a'),
          ),
          cacheDbProvider.overrideWithValue(cache),
          outboxProvider.overrideWithValue(outbox),
          dayRepositoryProvider.overrideWithValue(
            DayRepository(remote: remote, cache: cache, outbox: outbox, salonId: 'salon-a'),
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
