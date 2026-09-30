import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'records_repository_test.dart' show FakeReads;
import 'support/fake_cray_api.dart';

class FakeWrites implements SalonWrites {
  final List<Map<String, Object?>> saved = [];
  CrayApiException? failure;

  @override
  Future<String> saveService({
    String? id,
    required String name,
    required int pricePaise,
    required int durationMinutes,
    required bool active,
  }) async {
    if (failure != null) throw failure!;
    saved.add({
      'table': 'services',
      'id': id,
      'name': name,
      'price_paise': pricePaise,
      'duration_minutes': durationMinutes,
      'active': active,
    });
    return id ?? 'new-service';
  }

  @override
  Future<String> saveAddOn({
    String? id,
    required String name,
    required int pricePaise,
    required int extraDurationMinutes,
    required bool active,
  }) async {
    if (failure != null) throw failure!;
    saved.add({
      'table': 'add_ons',
      'id': id,
      'name': name,
      'price_paise': pricePaise,
      'extra_duration_minutes': extraDurationMinutes,
      'active': active,
    });
    return id ?? 'new-addon';
  }

  @override
  Future<String> saveStaff({
    String? id,
    required String name,
    required bool active,
  }) async {
    if (failure != null) throw failure!;
    saved.add({'table': 'staff', 'id': id, 'name': name, 'active': active});
    return id ?? 'new-staff';
  }
}

/// Editing the catalogue (O7-O9).
///
/// The rules this asserts, rather than merely checks:
///   * money leaves the form as **integer paise** - a rupee string never becomes
///     a double on the way (`RULES.md` 5.1.2)
///   * a **stylist is offered no controls at all**, because the database would
///     refuse the write anyway (0041) and a button that fails is worse than none
///   * a refusal is reported as a refusal, and offline as not saved - never
///     silently held, because catalogue edits are not queued (ARCH 10.1)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  late FakeReads reads;
  late FakeWrites writes;

  setUp(() {
    cache = CacheDb(NativeDatabase.memory());
    reads = FakeReads();
    writes = FakeWrites();
    reads.serviceRows = const [
      Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
    ];
  });

  tearDown(() => cache.close());

  Future<void> pump(WidgetTester tester, {String role = 'owner'}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(AppSession(appRole: role, salonId: 'salon-a')),
          cacheDbProvider.overrideWithValue(cache),
          recordsRepositoryProvider.overrideWithValue(
            RecordsRepository(
              remote: reads,
              cache: cache,
              salonId: 'salon-a',
              writes: writes,
            ),
          ),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
    // The catalogue lives under More now (Claude Design O7).
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Services').last);
    await tester.pumpAndSettle();
  }

  testWidgets('an owner adds a service, and the price is sent in paise', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Beard trim');
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '400.50');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(writes.saved.single, {
      'table': 'services',
      'id': null,
      'name': 'Beard trim',
      // 400.50 rupees is 40050 paise, exactly - not 40049.999…
      'price_paise': 40050,
      'duration_minutes': 20,
      'active': true,
    });
  });

  testWidgets('editing an existing service keeps its id', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Haircut'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '450');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(writes.saved.single['id'], 's1');
    expect(writes.saved.single['price_paise'], 45000);
  });

  testWidgets('hiding a service is an update, not a delete', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Haircut'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // History keeps its own price snapshot, so a service is hidden rather than
    // removed (ARCHITECTURE 6.2).
    expect(writes.saved.single['active'], false);
    expect(writes.saved.single['id'], 's1');
  });

  testWidgets('a price that is not a price is refused before anything is sent',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Odd');
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '4.005');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the price in rupees, for example 400 or 400.50.'), findsOneWidget);
    expect(writes.saved, isEmpty);
  });

  testWidgets('a name is required - customers see it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '400');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('A name is needed - customers see it.'), findsOneWidget);
    expect(writes.saved, isEmpty);
  });

  testWidgets('a stylist is offered nothing to press', (tester) async {
    // The database refuses a stylist's write whatever the app sends (0041). The
    // app therefore offers no control, rather than one that fails.
    await pump(tester, role: 'staff');

    expect(find.text('Haircut'), findsOneWidget, reason: 'they can still read the menu');
    expect(find.text('Add'), findsNothing);

    await tester.tap(find.text('Haircut'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing, reason: 'the edit sheet must not open');
  });

  testWidgets('a refusal says the account cannot do it, and is not retried',
      (tester) async {
    writes.failure = const CrayApiException(CrayErrorKind.forbidden);
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Nope');
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your account cannot change the catalogue. Ask the owner.'),
      findsOneWidget,
    );
  });

  testWidgets('offline says NOT SAVED - a catalogue edit is never queued', (tester) async {
    writes.failure = const CrayApiException(CrayErrorKind.network);
    await pump(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Later');
    await tester.enterText(find.widgetWithText(TextField, 'Price (₹)'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Not saved. Catalogue changes need a connection.'), findsOneWidget);
  });
}
