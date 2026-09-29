import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_account.dart';
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

  // In progress by default: since the start code (0084), Mark complete lives on
  // the in-progress row, and a booked row offers Start instead. Most of these
  // tests are about mark-complete, so that is where they begin.
  BookingRow booking({
    String id = 'b1',
    String status = 'in_progress',
    bool customerHasApp = true,
  }) {
    // A fixed hour TODAY: 'now plus two hours' crosses midnight after 22:00.
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day, 12);
    return BookingRow(
      id: id,
      customerId: 'c1',
      startsAt: start,
      endsAt: start.add(const Duration(minutes: 30)),
      status: status,
      totalPaise: 40000,
      customerName: 'Asha',
      serviceNames: 'Haircut',
      customerHasApp: customerHasApp,
    );
  }

  Future<void> pump(WidgetTester tester, {SalonAccountApi? account}) async {
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
          if (account != null) salonAccountApiProvider.overrideWithValue(account),
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

  group('start (0084)', () {
    testWidgets('a booked row offers Start, not Mark complete', (tester) async {
      remote.dayRows = [booking(status: 'confirmed')];
      await pump(tester);

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Mark complete'), findsNothing,
          reason: 'a service that never started cannot be completed from here');
    });

    testWidgets("the customer's code starts it, and the row moves on at once", (tester) async {
      remote.dayRows = [booking(status: 'confirmed')];
      await pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Start with this code'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '4821');
      await tester.pump();
      await tester.tap(find.text('Start with this code'));
      await tester.pumpAndSettle();

      expect(find.text('Start with this code'), findsNothing, reason: 'the sheet closed');
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Mark complete'), findsOneWidget);
      expect(remote.sent.single['code'], '4821');
    });

    testWidgets('a wrong code is answered while the customer is still there', (tester) async {
      remote.dayRows = [booking(status: 'confirmed')];
      remote.startAnswer = const StartResult.refused(StartRefusal.wrongCode, attemptsLeft: 2);
      await pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1111');
      await tester.pump();
      await tester.tap(find.text('Start with this code'));
      await tester.pumpAndSettle();

      expect(find.text('That is not their code. 2 tries left.'), findsOneWidget);
      expect(find.text('Start without the code'), findsNothing,
          reason: 'one wrong guess is not a reason to skip the code');
    });

    testWidgets('a locked code offers to start without it', (tester) async {
      remote.dayRows = [booking(status: 'confirmed')];
      remote.startAnswer = const StartResult.refused(StartRefusal.codeLocked);
      await pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.pump();
      await tester.tap(find.text('Start with this code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('this code is locked'), findsOneWidget);
      expect(find.text('Start without the code'), findsOneWidget);
    });

    testWidgets('with no connection, nobody is turned away', (tester) async {
      remote.dayRows = [booking(status: 'confirmed')];
      remote.startAnswer = null; // offline, for a start that needs the server
      await pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '4821');
      await tester.pump();
      await tester.tap(find.text('Start with this code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the code cannot be checked'), findsOneWidget);
      await tester.tap(find.text('Start without the code'));
      await tester.pumpAndSettle();

      expect(find.text('In progress'), findsOneWidget);
      expect(remote.sent.single['op'], 'start_service');
      expect(remote.sent.single['code'], isNull,
          reason: 'started WITHOUT a code - the server records why');
    });

    testWidgets('a customer without the app is started without a code, and no box to type in',
        (tester) async {
      remote.dayRows = [booking(status: 'confirmed', customerHasApp: false)];
      await pump(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('does not have the app'), findsOneWidget);
      await tester.tap(find.text('Start without the code'));
      await tester.pumpAndSettle();

      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Mark complete'), findsOneWidget);
    });
  });

  group('billing (0087)', () {
    testWidgets('a lapsed salon is TOLD it is read-only, before a tap is refused',
        (tester) async {
      remote.dayRows = [booking()];
      await pump(tester,
          account: FakeAccount(SalonBilling(
            state: 'grace',
            readOnly: true,
            graceEndsAt: DateTime(2026, 10, 7),
          )));

      expect(find.text('Read-only for now'), findsOneWidget);
      expect(find.textContaining('Pay Crayora before Oct 7, 2026'), findsOneWidget);
      // Reading still works: the day is on screen.
      expect(find.text('Asha'), findsOneWidget);
    });

    testWidgets('a paid-up salon shows no banner', (tester) async {
      remote.dayRows = [booking()];
      await pump(tester, account: FakeAccount(const SalonBilling(state: 'active', readOnly: false)));
      expect(find.text('Read-only for now'), findsNothing);
    });

    testWidgets('a feature outside the plan has no button', (tester) async {
      remote.dayRows = [booking()];
      await pump(tester,
          account: FakeAccount(const SalonBilling(state: 'active', readOnly: false),
              features: const {'referrals'}));
      expect(find.byTooltip('Dashboard'), findsNothing);
    });

    testWidgets('and one inside it does', (tester) async {
      remote.dayRows = [booking()];
      await pump(tester,
          account: FakeAccount(const SalonBilling(state: 'active', readOnly: false),
              features: const {'dashboard', 'referrals'}));
      expect(find.byTooltip('Dashboard'), findsOneWidget);
    });
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

class FakeAccount implements SalonAccountApi {
  FakeAccount(this.billing, {this.features = const {'dashboard', 'referrals'}});

  final SalonBilling billing;
  final Set<String> features;

  @override
  Future<SalonBilling> myBilling() async => billing;

  @override
  Future<Set<String>> myFeatures() async => features;
}
