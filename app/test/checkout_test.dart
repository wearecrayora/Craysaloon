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

/// Taking the money for a completed visit, from the day view.
///
/// The gates, rather than checks (RULES 9, 9.5; 0069, 0079, 0080):
///   * the cash to collect comes from the SERVER, and **offline the sheet does
///     not guess a split** - a wrong guess records cash nobody collected
///   * recording is queued through the outbox, by BOOKING, because offline the
///     app has no visit id yet
///   * a row reads "Paid" only when the server says so, never because of a tap
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  late FakeBookings remote;

  setUp(() {
    cache = CacheDb(NativeDatabase.memory());
    remote = FakeBookings();
  });

  tearDown(() => cache.close());

  BookingRow completed({String? paymentStatus}) {
    final start = DateTime.now().subtract(const Duration(hours: 1));
    return BookingRow(
      id: 'b1',
      customerId: 'c1',
      startsAt: start,
      endsAt: start.add(const Duration(minutes: 30)),
      status: 'completed',
      totalPaise: 45000,
      customerName: 'Asha',
      serviceNames: 'Haircut',
      paymentStatus: paymentStatus,
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

  testWidgets('a completed, unpaid visit offers to take payment', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'unpaid')];
    await pump(tester);
    expect(find.text('Take payment'), findsOneWidget);
  });

  testWidgets('a paid visit says so, and offers nothing more', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'paid')];
    await pump(tester);
    expect(find.text('Done · Paid'), findsOneWidget);
    expect(find.text('Take payment'), findsNothing);
  });

  testWidgets('online, the SERVER says how much cash to collect', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'unpaid')];
    remote.quote = const CheckoutQuote(
      duePaise: 45000,
      walletAvailablePaise: 20000,
      fromWalletPaise: 20000,
      fromCounterPaise: 25000,
    );
    await pump(tester);

    await tester.tap(find.text('Take payment'));
    await tester.pumpAndSettle();

    // ₹200 credit against a ₹450 bill: the case the whole wallet design is for.
    expect(find.text('Wallet pays ₹200. Collect ₹250.'), findsOneWidget);
  });

  testWidgets('offline, the sheet does NOT guess a split', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'unpaid')];
    remote.quote = null; // no connection
    await pump(tester);

    await tester.tap(find.text('Take payment'));
    await tester.pumpAndSettle();

    expect(find.textContaining('the wallet balance cannot be checked'), findsOneWidget);
    // The full amount, because a guessed split that ran high would have the
    // server record cash the owner never collected.
    expect(find.text('Collect ₹450.'), findsOneWidget);
    expect(find.textContaining('Wallet pays'), findsNothing);

    final walletSwitch = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(walletSwitch.value, isFalse, reason: 'off offline - the safe default');
    expect(walletSwitch.onChanged, isNull, reason: 'and cannot be turned on without a quote');
  });

  testWidgets('recording is queued BY BOOKING with the chosen method', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'unpaid')];
    remote.quote = const CheckoutQuote(
      duePaise: 45000,
      walletAvailablePaise: 0,
      fromWalletPaise: 0,
      fromCounterPaise: 45000,
    );
    await pump(tester);

    await tester.tap(find.text('Take payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();

    final sent = remote.sent.where((s) => s['op'] == 'checkout_booking').toList();
    expect(sent, hasLength(1));
    expect(sent.single['booking_id'], 'b1',
        reason: 'by booking - offline there is no visit id yet (0079)');
    expect(sent.single['method'], 'upi');
  });

  testWidgets('a tap never turns the row "Paid" - only the server does', (tester) async {
    remote.dayRows = [completed(paymentStatus: 'unpaid')];
    remote.quote = const CheckoutQuote(
      duePaise: 45000,
      walletAvailablePaise: 0,
      fromWalletPaise: 0,
      fromCounterPaise: 45000,
    );
    await pump(tester);

    await tester.tap(find.text('Take payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();

    // The server (the fake) still reports unpaid, so the row must too.
    expect(find.text('Done · Paid'), findsNothing);
    expect(
      find.text('Payment recorded. It will show as paid once it reaches the server.'),
      findsOneWidget,
    );
  });
}
