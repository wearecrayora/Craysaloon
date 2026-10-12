import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/owner/hours_screens.dart';
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
    FakeAccount? account,
    String role = 'owner',
    SalonProfile? salon = profile,
    FakeHours? hours,
    List<StaffMember>? staff,
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
          if (hours != null) salonHoursApiProvider.overrideWithValue(hours),
          if (staff != null)
            staffProvider.overrideWith((ref) async => Cached(staff, fromCache: false)),
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
            account ??
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
      expect(
        find.byType(BackButton),
        findsOneWidget,
        reason: 'a page opened from More has a way back',
      );
      expect(find.text('₹50 for every ₹500'), findsOneWidget);
      expect(find.text('₹100'), findsWidgets);
      expect(find.text('Never expires'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      // Read-only, and says who changes it: no field here pretends to be editable.
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('ask your Crayora contact'), findsOneWidget);
    },
  );

  testWidgets('with no stylist hours, Hours says nobody can book - and where to fix it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();

    expect(find.textContaining('customers cannot book'), findsOneWidget);
    expect(find.text('Set hours in Team'), findsOneWidget);
  });

  testWidgets('Hours shows when each day can actually be booked, and the holidays', (
    tester,
  ) async {
    final hours = FakeHours()
      ..shiftList = const [
        Shift(staffId: 'st-1', day: 1, starts: '10:00', ends: '13:00'),
        Shift(staffId: 'st-2', day: 1, starts: '12:00', ends: '20:00'),
      ]
      ..offList = [
        TimeOff(
          id: 'h1',
          startsAt: DateTime(2026, 11, 8),
          endsAt: DateTime(2026, 11, 9),
          reason: 'Diwali',
        ),
      ];
    await pump(tester, hours: hours);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();

    // Monday: earliest start to latest end across the stylists.
    expect(find.text('10:00 AM – 8:00 PM'), findsOneWidget);
    expect(find.text('Closed'), findsNWidgets(6));
    expect(find.text('Salon closed'), findsOneWidget);
    expect(find.textContaining('Diwali'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(hours.removed, ['h1']);
  });

  testWidgets("the owner sets a stylist's week from Team", (tester) async {
    final hours = FakeHours();
    await pump(tester, hours: hours, staff: const [StaffMember(id: 'st-1', name: 'Suresh', active: true)]);
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    // A stylist with no week cannot be booked, and the row says so.
    expect(find.text('No hours set - cannot be booked'), findsOneWidget);
    await tester.tap(find.byTooltip('Working hours'));
    await tester.pumpAndSettle();

    expect(find.text("Suresh's week"), findsOneWidget);
    // Monday on, at the default 10:00-20:00.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save hours'));
    await tester.pumpAndSettle();

    expect(hours.weeks, hasLength(1));
    final week = hours.weeks.single;
    expect(week.$1, 'st-1');
    expect(week.$2.map((s) => '${s.day} ${s.starts}-${s.ends}'), ['1 10:00-20:00']);
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

  Future<void> openRules(WidgetTester tester) async {
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the OWNER sets how long bonus lasts - and is told old bonus keeps its date',
    (tester) async {
      final account = FakeAccount(
        const SalonBilling(state: 'active', readOnly: false),
        profile: profile,
      );
      await pump(tester, account: account);
      await openRules(tester);

      // Never set: the ledger's own default, shown as such.
      expect(find.text('180 days'), findsOneWidget);
      await tester.tap(find.text('Bonus lasts'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bonus already given keeps the date it came with'),
        findsOneWidget,
      );
      await tester.tap(find.text('90 days'));
      await tester.pumpAndSettle();

      expect(account.expirySet, [90]);
      expect(find.text('Saved. New bonus: 90 days.'), findsOneWidget);
    },
  );

  testWidgets('a manager sees the expiry but cannot change it', (tester) async {
    final account = FakeAccount(
      const SalonBilling(state: 'active', readOnly: false),
      profile: profile,
    );
    await pump(tester, role: 'manager', account: account);
    await openRules(tester);

    expect(find.text('180 days'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(find.text('Bonus lasts'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('How long should bonus credit last'),
      findsNothing,
    );
    expect(account.expirySet, isEmpty);
  });
}

/// Stylist hours and time off, as the server would keep them (0098).
class FakeHours implements SalonHoursApi {
  List<Shift> shiftList = const [];
  List<TimeOff> offList = const [];
  final List<(String, List<Shift>)> weeks = [];
  final List<String> removed = [];

  @override
  Future<List<Shift>> shifts() async => shiftList;

  @override
  Future<List<TimeOff>> timeOff() async => offList.where((t) => !removed.contains(t.id)).toList();

  @override
  Future<void> setStaffWeek(String staffId, List<Shift> week) async {
    weeks.add((staffId, week));
    shiftList = [...shiftList.where((s) => s.staffId != staffId), ...week];
  }

  @override
  Future<void> addTimeOff({
    String? staffId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? reason,
  }) async {}

  @override
  Future<void> removeTimeOff(String id) async => removed.add(id);
}
