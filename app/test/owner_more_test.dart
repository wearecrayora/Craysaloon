import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/owner/more_screens.dart';
import 'package:craysalon/features/salon/salon_account.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'day_screen_test.dart' show FakeAccount;
import 'outbox_test.dart' show FakeBookings;
import 'support/fake_cray_api.dart';

/// The owner's shell (Today / Customers / Dashboard / More) and the read-only
/// pages under More (Claude Design O7-O13).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  setUp(() => cache = CacheDb(NativeDatabase.memory()));
  tearDown(() => cache.close());

  const profile = SalonProfile(
    displayName: 'Studio Nine Salon',
    legalName: 'Studio Nine Salon LLP',
    address: 'Indiranagar, Bengaluru',
    gstNumber: '29ABCDE1234F1Z5',
    gstRateBp: 500,
    walletRule: {
      'topup_paise': 50000,
      'bonus_paise': 5000,
      'min_topup_paise': 10000,
    },
    rewardRule: {'referrer_paise': 10000, 'referred_paise': 5000},
    reminderCycleDays: 30,
    grievanceName: 'Sunita Rao',
    grievanceEmail: 'privacy@studionine.example',
  );

  Future<void> pump(
    WidgetTester tester, {
    String role = 'owner',
    SalonProfile? salon = profile,
  }) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final remote = FakeBookings();
    final outbox = Outbox(cache);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(
            AppSession(appRole: role, salonId: 'salon-a'),
          ),
          cacheDbProvider.overrideWithValue(cache),
          outboxProvider.overrideWithValue(outbox),
          dayRepositoryProvider.overrideWithValue(
            DayRepository(
              remote: remote,
              cache: cache,
              outbox: outbox,
              salonId: 'salon-a',
            ),
          ),
          salonAccountApiProvider.overrideWithValue(
            FakeAccount(
              const SalonBilling(
                state: 'active',
                readOnly: false,
                plan: 'Salon',
                monthlyPricePaise: 149900,
              ),
              profile: salon,
            ),
          ),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('an owner has Today, Customers, Dashboard and More', (
    tester,
  ) async {
    await pump(tester);
    for (final label in ['Today', 'Customers', 'Dashboard', 'More']) {
      expect(tab(label), findsOneWidget, reason: label);
    }
    // The catalogue moved under More: it is set up once, not used all day.
    expect(tab('Services'), findsNothing);
  });

  testWidgets('a stylist gets no Dashboard tab and no Billing row', (
    tester,
  ) async {
    await pump(tester, role: 'staff');
    expect(tab('Dashboard'), findsNothing);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    expect(find.text('Rules'), findsOneWidget);
    expect(
      find.text('Billing'),
      findsNothing,
      reason: 'what the salon pays Crayora is not a stylist\'s business',
    );
  });

  testWidgets('More reaches the catalogue and stays highlighted there', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3, reason: 'the catalogue belongs to More');
  });

  testWidgets(
    'Rules show what the money actually applies - and paid credit never expires',
    (tester) async {
      await pump(tester);
      await tester.tap(tab('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rules'));
      await tester.pumpAndSettle();

      expect(find.byType(RulesScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget, reason: 'a page opened from More has a way back');
      expect(find.text('₹50 for every ₹500'), findsOneWidget);
      expect(find.text('₹100'), findsWidgets);
      expect(find.text('Never expires'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      // Read-only, and says who changes it: no field here pretends to be editable.
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Ask your Crayora contact'), findsOneWidget);
    },
  );

  testWidgets('hours not recorded say so, rather than showing a closed week', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();

    expect(find.text('Your hours are not recorded yet.'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
  });

  test('the hours reader takes the shapes the console can store', () {
    expect(HoursScreen.describe(['10:00', '20:00'], 'Closed'), '10:00 – 20:00');
    expect(
      HoursScreen.describe({'open': '09:00', 'close': '21:00'}, 'Closed'),
      '09:00 – 21:00',
    );
    expect(HoursScreen.describe(null, 'Closed'), 'Closed');
    expect(HoursScreen.describe(false, 'Closed'), 'Closed');
  });

  testWidgets(
    'billing shows the plan and price, and whose account customer money reaches',
    (tester) async {
      await pump(tester);
      await tester.tap(tab('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Billing'));
      await tester.pumpAndSettle();

      expect(find.text('Salon'), findsOneWidget);
      expect(find.text('₹1,499'), findsOneWidget);
      expect(find.textContaining('never to Crayora'), findsOneWidget);
    },
  );

  testWidgets('the salon profile shows GST and the privacy contact', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salon profile'));
    await tester.pumpAndSettle();

    expect(find.text('29ABCDE1234F1Z5 · 5%'), findsOneWidget);
    expect(
      find.text('Sunita Rao · privacy@studionine.example'),
      findsOneWidget,
    );
  });
}
