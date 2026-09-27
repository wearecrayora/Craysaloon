import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/features/customers/customers_controller.dart';
import 'package:craysalon/features/customers/customers_screen.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'records_repository_test.dart' show FakeReads, customer;
import 'support/fake_cray_api.dart';

/// The owner's customer list and a customer's record (O4, O5).
///
/// Three of these are gates rather than checks:
///   * **the balance cannot be edited** - no control, no endpoint, no permission
///     (`RULES.md` §2, §5.2)
///   * **cached rows are labelled** rather than passed off as live
///   * **nothing clips at 200% text scale** (`DESIGN.md` 13)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  late FakeReads reads;

  setUp(() {
    cache = CacheDb(NativeDatabase.memory());
    reads = FakeReads();
  });

  tearDown(() => cache.close());

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          hasSessionProvider.overrideWithValue(true),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'owner', salonId: 'salon-a'),
          ),
          cacheDbProvider.overrideWithValue(cache),
          recordsRepositoryProvider.overrideWithValue(
            RecordsRepository(remote: reads, cache: cache, salonId: 'salon-a'),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an owner lands on their own shell, not the join flow', (tester) async {
    await pump(tester);
    // The role decides the shell (ARCH 9.1): an owner never sees the join screen.
    expect(find.text('Find your salon'), findsNothing);
    expect(find.text('Customers'), findsWidgets);
  });

  testWidgets('the list shows who was in last, with their balance', (tester) async {
    reads.customerRows = [
      customer('c1', lastVisit: DateTime(2026, 9, 20), balance: 12050000),
      customer('c2', lastVisit: DateTime(2026, 9, 1)),
    ];

    await pump(tester);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();

    expect(find.text('Customer c1'), findsOneWidget);
    expect(find.text('Customer c2'), findsOneWidget);
    // Indian grouping, and no balance chip at all for a customer with nothing.
    expect(find.text('₹1,20,500'), findsOneWidget);
  });

  testWidgets('a customer record shows the balance and CANNOT change it', (tester) async {
    reads.customerRows = [customer('c1', lastVisit: DateTime(2026, 9, 20), balance: 55000)];
    reads.visitRows = [
      Visit(
        id: 'v1',
        customerId: 'c1',
        completedAt: DateTime(2026, 9, 20),
        finalAmountPaise: 40000,
      ),
    ];

    await pump(tester);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer c1'));
    await tester.pumpAndSettle();

    expect(find.text('₹550'), findsOneWidget);
    expect(
      find.text('Balance is set by top-ups and visits. It cannot be edited here.'),
      findsOneWidget,
    );

    // The gate: nothing on this screen can change money. Not disabled - absent.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    for (final label in ['Adjust', 'Edit balance', 'Add money', 'Top up', 'Refund']) {
      expect(find.text(label), findsNothing, reason: '$label must not exist on O5');
    }

    // The visit is there, at its own amount.
    expect(find.text('₹400'), findsOneWidget);
  });

  testWidgets('cached rows say so, with the time they were fetched', (tester) async {
    reads.customerRows = [customer('c1', lastVisit: DateTime(2026, 9, 20))];

    // Once online, so the cache has something in it.
    await pump(tester);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Shown from this device'), findsNothing);

    // Now the connection drops and the list is refreshed - the train, the
    // basement, the salon whose wi-fi is down. Driven through the controller
    // rather than a fling, because this asserts what the screen does with the
    // result, not how a gesture is recognised.
    reads.failure = const CrayApiException(CrayErrorKind.network);
    final container = ProviderScope.containerOf(tester.element(find.byType(CustomersScreen)));
    await container.read(customersControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.textContaining('Shown from this device'), findsOneWidget);
    expect(find.text('Customer c1'), findsOneWidget,
        reason: 'the cached row is still useful - it is just labelled');
  });

  testWidgets('a search that finds nobody says what to try, and does not blame them',
      (tester) async {
    reads.customerRows = [customer('c1', lastVisit: DateTime(2026, 9, 20))];
    await pump(tester);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Nobody matched that. Try the full number, or fewer letters.'),
        findsOneWidget);
  });

  testWidgets('nothing clips at 200% text scale (DESIGN 13)', (tester) async {
    reads.customerRows = [
      customer('c1', lastVisit: DateTime(2026, 9, 20), balance: 12050000),
      customer('c2'),
    ];

    await pump(tester, textScale: 2.0);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();

    // A RenderFlex overflow is reported as an exception by the test binding, so
    // this asserts the real failure mode rather than eyeballing a screenshot.
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Customer c1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
