import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/dashboard/dashboard.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/features/dashboard/dashboard_screen.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outbox_test.dart' show FakeBookings;
import 'support/fake_cray_api.dart';

/// O6 - the owner's dashboard.
///
/// Four of these are gates rather than checks (PRD 9.5, DESIGN 6.6 and 9.4):
///
///   * **messaging spend is never shown without the conversion it bought**
///   * **an unripe cohort reads "not yet", never 0%** - a zero there calls
///     people who have not had the chance to return "lost"
///   * **the cohort chart has a legend, direct labels, an n and a table**
///   * **nothing on this screen can move money** - the outstanding-credit tile
///     has no control, and says so
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;

  setUp(() => cache = CacheDb(NativeDatabase.memory()));
  tearDown(() => cache.close());

  Dashboard sample({List<String> drift = const []}) => Dashboard(
        revenuePaise: 1245000,
        completed: 18,
        avgBillPaise: 69166,
        bookingsLive: 22,
        cancelled: 2,
        noShow: 1,
        newCustomers: 7,
        repeatCustomers: 31,
        walletCollectedPaise: 850000,
        outstandingCreditPaise: 1420000,
        reminderBookings: 9,
        binds: 12,
        spendByChannel: const {'push': 0, 'sms': 4400, 'whatsapp': 1700},
        remindersSent: 64,
        ackedPushes: 51,
        cohorts: [
          CohortRow(month: DateTime(2026, 5), segment: 'wallet', n: 14, d30: 71.4, d60: 78.6, d90: 85.7),
          CohortRow(month: DateTime(2026, 5), segment: 'no_wallet', n: 23, d30: 34.8, d60: 43.5, d90: 47.8),
          // The newest cohort: nobody has had 30 days yet.
          CohortRow(month: DateTime(2026, 9), segment: 'wallet', n: 3),
          CohortRow(month: DateTime(2026, 9), segment: 'no_wallet', n: 5),
        ],
        driftDays: drift,
      );

  Future<void> pump(
    WidgetTester tester, {
    String role = 'owner',
    Dashboard? data,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final outbox = Outbox(cache);
    final api = FakeDashboardApi(data ?? sample());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(AppSession(appRole: role, salonId: 'salon-a')),
          cacheDbProvider.overrideWithValue(cache),
          outboxProvider.overrideWithValue(outbox),
          dayRepositoryProvider.overrideWithValue(
            DayRepository(remote: FakeBookings(), cache: cache, outbox: outbox, salonId: 'salon-a'),
          ),
          dashboardApiProvider.overrideWithValue(api),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 150, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('an owner reaches it in one tap from the day view', (tester) async {
    await pump(tester);
    await open(tester);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('₹12,450'), findsOneWidget);
  });

  testWidgets('staff are not offered a door the server would slam', (tester) async {
    await pump(tester, role: 'staff');
    // owner_dashboard refuses staff; a button that answers "not allowed" is
    // worse than no button.
    expect(find.byIcon(Icons.insights_outlined), findsNothing);
  });

  testWidgets('money is written the Indian way, in tabular figures', (tester) async {
    await pump(tester);
    await open(tester);
    expect(find.text('₹14,200'), findsOneWidget, reason: 'outstanding credit, lakh grouping');
    expect(find.text('₹8,500'), findsOneWidget);
  });

  testWidgets('an average of nothing is a dash, not ₹0', (tester) async {
    await pump(
      tester,
      data: Dashboard(
        revenuePaise: 0, completed: 0, bookingsLive: 3, cancelled: 0, noShow: 0,
        newCustomers: 0, repeatCustomers: 0, walletCollectedPaise: 0,
        outstandingCreditPaise: 0, reminderBookings: 0, binds: 0,
        spendByChannel: const {}, remindersSent: 0, ackedPushes: 0,
        cohorts: const [], driftDays: const [],
      ),
    );
    await open(tester);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('outstanding credit is shown and CANNOT be adjusted - absent, not disabled',
      (tester) async {
    await pump(tester);
    await open(tester);

    expect(find.text('Credit customers hold'), findsOneWidget);
    expect(
      find.text('Shown, not adjustable. Balances change only through top-ups and visits.'),
      findsOneWidget,
    );
    // No control of any kind that could move a balance (PRD 9.5 AC).
    for (final word in ['Adjust', 'Correct', 'Add credit', 'Edit balance', 'Refund']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('what reminders cost is never shown without what they brought', (tester) async {
    await pump(tester);
    await open(tester);
    await scrollTo(tester, find.text('Reminders: what they cost and what they brought'));

    final card = find.ancestor(
      of: find.text('Reminders: what they cost and what they brought'),
      matching: find.byType(Card),
    );
    // Spend and conversion live in the SAME card (PRD 9.5).
    expect(find.descendant(of: card, matching: find.text('₹61')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('9 bookings from reminders')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('64 reminders sent')), findsOneWidget);
  });

  testWidgets('drift is shown to the owner, with a word and not only a colour', (tester) async {
    await pump(tester, data: sample(drift: ['2026-09-27']));
    await open(tester);
    expect(
      find.text('Some past figures disagree with the records and are being checked.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('the cohort chart has a legend, direct labels, an n and a table',
      (tester) async {
    await pump(tester);
    await open(tester);
    await scrollTo(tester, find.text('Do customers come back?'));

    // It opens on the newest cohort with a KNOWN rate, not on "not yet".
    expect(find.text('71%'), findsOneWidget, reason: 'direct label on the wallet bar');
    expect(find.text('35%'), findsOneWidget, reason: 'and on the no-wallet bar');
    expect(find.text('Use the wallet'), findsWidgets, reason: 'legend');
    expect(find.text('No wallet'), findsWidgets);
    expect(find.text('% who returned'), findsOneWidget, reason: 'the axis says what it is');

    await scrollTo(tester, find.text('The same numbers'));
    expect(find.byType(DataTable), findsOneWidget, reason: 'the table view (DESIGN 9.4)');
    expect(find.text('14'), findsOneWidget, reason: 'the n, visible');
  });

  testWidgets('an unripe cohort reads "not yet" - never 0%', (tester) async {
    await pump(tester);
    await open(tester);
    await scrollTo(tester, find.text('Do customers come back?'));

    await tester.tap(find.byWidgetPredicate(
      (w) => w is ChoiceChip && (w.label as Text).data!.contains('2026'),
    ).last);
    await tester.pumpAndSettle();

    expect(find.text('not yet'), findsWidgets);
    expect(find.text('0%'), findsNothing,
        reason: 'a zero here calls people who have not had the chance to return "lost"');
  });

  testWidgets('nothing clips at 200% text scale', (tester) async {
    await pump(tester, textScale: 2.0);
    await open(tester);
    expect(tester.takeException(), isNull);
  });
}

class FakeDashboardApi implements DashboardApi {
  FakeDashboardApi(this.data);

  final Dashboard data;

  @override
  Future<Dashboard> dashboard() async => data;
}
