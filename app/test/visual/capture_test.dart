// VISUAL CAPTURE - renders real screens, with real fonts and icons, to PNGs.
//
// Not a gate: it asserts nothing about pixels. It exists so the design can be
// looked at without a phone (there is no emulator on the build machine). Runs
// only when asked:
//
//   VISUAL_OUT=<dir> flutter test test/visual/capture_test.dart
//
// Wears the Claude Design project's Studio Nine (dusty rose, Poppins, 18dp),
// resolved the way the console publishes it.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/features/salon/salon_account.dart' show salonAccountApiProvider;
import 'package:craysalon/features/join/deep_link_listener.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/features/visit/visit_cards.dart';
import 'package:craysalon/features/wallet/add_money_screen.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../day_screen_test.dart' show FakeAccount;
import '../outbox_test.dart' show FakeBookings;
import '../salon_home_test.dart' show FakeNotifications, FakeShortcut;
import '../support/fake_cray_api.dart';
import '../support/fake_customer_api.dart';
import '../visit_test.dart' show FakeVisitApi;
import '../wallet_test.dart' show FakeSheet, FakeWalletApi;

final _out = Platform.environment['VISUAL_OUT'];

/// Studio Nine as the Claude Design project resolves it (29 Sep 2026).
Map<String, Object?> designBranding() {
  Map<String, Object?> set({
    required String primary,
    required String onPrimary,
    required String container,
    required String onContainer,
    required String ink,
    required String surface,
    required String surfaceAlt,
    required String sunken,
    required String border,
    required String borderStrong,
    required String divider,
    required String text,
    required String text2,
    required String muted,
  }) =>
      {
        'color': {
          'primary': primary,
          'onPrimary': onPrimary,
          'primaryContainer': container,
          'onPrimaryContainer': onContainer,
          'accent': '#E8B4A0',
          'onAccent': '#1C1B19',
          'brandInk': ink,
          'surface': surface,
          'surfaceAlt': surfaceAlt,
          'surfaceSunken': sunken,
          'border': border,
          'borderStrong': borderStrong,
          'divider': divider,
          'textPrimary': text,
          'textSecondary': text2,
          'textMuted': muted,
        },
        'radius': {'base': 18, 'chip': 9, 'sheet': 27, 'pill': 999},
        'typography': {
          'heading': {'family': 'Poppins', 'weight': 500},
          'body': {'family': 'Poppins', 'weight': 400},
          'script': 'latin',
          'lineHeightBonus': 0,
        },
      };

  return {
    'version': 7,
    'displayName': 'Studio Nine Salon',
    'brand': {
      'light': {'primary': '#B84F5E', 'accent': '#E8B4A0'},
      'dark': {'primary': '#F2A7B0', 'accent': '#E8B4A0'},
    },
    'resolved': {
      'light': set(
        primary: '#B84F5E', onPrimary: '#FDFCFA', container: '#F4DEDF',
        onContainer: '#A74050', ink: '#B84F5E', surface: '#FBF6F5',
        surfaceAlt: '#F3F2EE', sunken: '#ECEAE5', border: '#DEDCD6',
        borderStrong: '#8F8D85', divider: '#EBDCDD', text: '#1C1B19',
        text2: '#4A4843', muted: '#6E6B64',
      ),
      'dark': set(
        primary: '#F2A7B0', onPrimary: '#1C1B19', container: '#403232',
        onContainer: '#F2A7B0', ink: '#F2A7B0', surface: '#161614',
        surfaceAlt: '#1F1E1B', sunken: '#0F0F0E', border: '#35342F',
        borderStrong: '#7D7B73', divider: '#2A2927', text: '#EDEBE6',
        text2: '#C4C1BA', muted: '#9A968E',
      ),
    },
  };
}

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }

  final poppins = Platform.environment['VISUAL_FONT'] ?? r'C:\Windows\Fonts\segoeui.ttf';
  final poppinsBold = Platform.environment['VISUAL_FONT_BOLD'] ?? r'C:\Windows\Fonts\seguisb.ttf';
  for (final family in ['Poppins', 'Inter', 'Noto Sans Devanagari', 'Roboto']) {
    await load(family, poppins);
    await load(family, poppinsBold);
  }
  await load(
    'MaterialIcons',
    r'C:\Users\JYOTIRANJAN\dev\flutter\bin\cache\dart-sdk\bin\resources\devtools\assets\fonts\MaterialIcons-Regular.otf',
  );
}

Future<void> _save(WidgetTester tester, String name) async {
  // Asset images decode off the test clock: give them real time, then a frame.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('capture')));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// flutter_test draws every shadow as a solid black outline by default. The
/// captures are for looking at, so real shadows for the whole test - restored
/// before the body ends, as the framework requires.
void capture(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  if (_out == null) {
    test('visual capture (set VISUAL_OUT to run)', () {}, skip: 'VISUAL_OUT not set');
    return;
  }

  setUpAll(_loadFonts);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1740);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  CachedBranding branding() => CachedBranding(
        salonId: 'salon-a',
        displayName: 'Studio Nine Salon',
        version: 7,
        document: designBranding(),
      );

  Future<void> customer(WidgetTester tester, FakeVisitApi visits, {ThemeMode? mode}) async {
    phone(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: ProviderScope(
          overrides: [
            crayApiProvider.overrideWithValue(FakeCrayApi()),
            sessionProvider.overrideWithValue(
              const AppSession(appRole: 'customer', salonId: 'salon-a'),
            ),
            initialBrandingProvider.overrideWithValue(branding()),
            homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
            salonNotificationsProvider.overrideWithValue(FakeNotifications()),
            visitApiProvider.overrideWithValue(visits),
            walletApiProvider.overrideWithValue(FakeWalletApi()),
            paymentSheetProvider.overrideWithValue(FakeSheet()),
          ],
          child: mode == ThemeMode.dark
              ? const MediaQuery(
                  data: MediaQueryData(platformBrightness: Brightness.dark),
                  child: CraySalonApp(),
                )
              : const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  capture('C1 home - a booking today, with the start code', (tester) async {
    final v = FakeVisitApi()..today = [FakeVisitApi().visit(code: '4821')];
    await customer(tester, v);
    await _save(tester, 'c1_home_today');
  });

  capture('C14 pay sheet - opens by itself when the bill arrives', (tester) async {
    final v = FakeVisitApi()..billList = [FakeVisitApi().bill(due: 100000)];
    await customer(tester, v);
    await _save(tester, 'c14_pay_sheet');
    Navigator.of(tester.element(find.text('How would you like to pay?'))).pop();
    await tester.pumpAndSettle();
    await _save(tester, 'c1_home_bill');
  });

  capture('C1 home - dark', (tester) async {
    final v = FakeVisitApi()..today = [FakeVisitApi().visit(code: '4821')];
    await customer(tester, v, mode: ThemeMode.dark);
    await _save(tester, 'c1_home_dark');
  });

  Future<void> shopper(WidgetTester tester, FakeCustomerApi api, {ThemeMode? mode}) async {
    phone(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: ProviderScope(
          overrides: [
            crayApiProvider.overrideWithValue(api),
            sessionProvider.overrideWithValue(api.session),
            initialBrandingProvider.overrideWithValue(branding()),
            homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
            salonNotificationsProvider.overrideWithValue(FakeNotifications()),
            walletApiProvider.overrideWithValue(FakeWalletApi()),
            paymentSheetProvider.overrideWithValue(FakeSheet()),
          ],
          child: mode == ThemeMode.dark
              ? const MediaQuery(
                  data: MediaQueryData(platformBrightness: Brightness.dark),
                  child: CraySalonApp(),
                )
              : const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeCustomerApi asha() => FakeCustomerApi()
    ..due = NextDue(dueOn: DateTime(2026, 10, 14), serviceName: 'Haircut');

  capture('C1 home - redesign', (tester) async {
    await shopper(tester, asha());
    await _save(tester, 'c1_home_v2');
  });

  capture('C1 home - redesign, dark', (tester) async {
    await shopper(tester, asha(), mode: ThemeMode.dark);
    await _save(tester, 'c1_home_v2_dark');
  });

  capture('C1 home - brand-new customer', (tester) async {
    await shopper(tester, FakeCustomerApi());
    await _save(tester, 'c1_home_new');
  });

  capture('C5-C8 booking', (tester) async {
    await shopper(tester, asha());
    await tester.tap(find.text('Book').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haircut'));
    await tester.pumpAndSettle();
    await _save(tester, 'c5_service');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Head massage'));
    await tester.pumpAndSettle();
    await _save(tester, 'c6_addons');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00 AM'));
    await tester.pumpAndSettle();
    await _save(tester, 'c7_time');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await _save(tester, 'c8_review');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm booking'));
    await tester.pumpAndSettle();
    await _save(tester, 'c9_detail');
  });

  capture('C10 history and C12 me', (tester) async {
    final api = asha()
      ..visitsList = [
        PastVisit(id: 'v1', completedAt: DateTime(2026, 9, 12), amountPaise: 60000, paid: true,
            serviceNames: 'Haircut', staffName: 'Suresh'),
        PastVisit(id: 'v2', completedAt: DateTime(2026, 8, 14), amountPaise: 100000, paid: true,
            serviceNames: 'Haircut + Beard trim', staffName: 'Priya'),
        PastVisit(id: 'v3', completedAt: DateTime(2026, 7, 18), amountPaise: 60000, paid: false,
            serviceNames: 'Haircut', staffName: 'Suresh'),
      ];
    await shopper(tester, api);
    await tester.tap(find.text('Me').last);
    await tester.pumpAndSettle();
    await _save(tester, 'c12_me');
    await tester.tap(find.text('Visit history'));
    await tester.pumpAndSettle();
    await _save(tester, 'c10_history');
  });

  capture('U2-U4 join', (tester) async {
    phone(tester);
    final api = FakeCrayApi(
      salon: SalonSummary(
        salonId: 'salon-a',
        displayName: 'Studio Nine Salon',
        brandingVersion: 7,
        branding: designBranding(),
        grievance: const GrievanceContact(name: 'Sunita Rao', email: 'privacy@studionine.example'),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: ProviderScope(
          overrides: [
            crayApiProvider.overrideWithValue(api),
            appLinkStreamProvider.overrideWithValue(const Stream.empty()),
          ],
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'u2_code');
    await tester.enterText(find.byType(TextField), 'CRAY-7KQ2MX');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _save(tester, 'u3_confirm');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _save(tester, 'u4_phone');
  });

  capture('O1 today - every row state', (tester) async {
    phone(tester);
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    final remote = FakeBookings();
    final now = DateTime.now();
    BookingRow row(String id, String name, String status, int h,
            {String? pay, bool app = true, bool counter = false}) =>
        BookingRow(
          id: id,
          customerId: 'c-$id',
          startsAt: DateTime(now.year, now.month, now.day, h, 30),
          endsAt: DateTime(now.year, now.month, now.day, h + 1),
          status: status,
          totalPaise: 45000 + h * 5000,
          customerName: name,
          staffName: h.isEven ? 'Suresh' : 'Priya',
          serviceNames: h.isEven ? 'Haircut + Beard trim' : 'Hair colour',
          paymentStatus: pay,
          customerHasApp: app,
          counterRequested: counter,
        );
    remote.dayRows = [
      row('1', 'Ravi Kumar', 'completed', 9, pay: 'paid'),
      row('2', 'Meera', 'completed', 10, pay: 'unpaid', counter: true),
      row('3', 'Asha Rao', 'in_progress', 11),
      row('4', 'Nikhil', 'confirmed', 13, app: false),
      row('5', 'Sana', 'confirmed', 15),
    ];
    final outbox = Outbox(cache);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: ProviderScope(
          overrides: [
            crayApiProvider.overrideWithValue(FakeCrayApi()),
            sessionProvider.overrideWithValue(
              const AppSession(appRole: 'owner', salonId: 'salon-a'),
            ),
            initialBrandingProvider.overrideWithValue(branding()),
            cacheDbProvider.overrideWithValue(cache),
            outboxProvider.overrideWithValue(outbox),
            dayRepositoryProvider.overrideWithValue(
              DayRepository(remote: remote, cache: cache, outbox: outbox, salonId: 'salon-a'),
            ),
            salonAccountApiProvider.overrideWithValue(FakeAccount(
              const SalonBilling(state: 'active', readOnly: false, plan: 'Salon', monthlyPricePaise: 149900),
              profile: const SalonProfile(
                displayName: 'Studio Nine Salon',
                legalName: 'Studio Nine Salon LLP',
                address: 'Indiranagar, Bengaluru',
                walletRule: {'topup_paise': 50000, 'bonus_paise': 5000, 'min_topup_paise': 10000},
                rewardRule: {'referrer_paise': 10000, 'referred_paise': 5000},
                reminderCycleDays: 30,
                cancellationPolicy: 'Free to cancel up to 2 hours before. Closer than that, call us.',
                grievanceName: 'Sunita Rao',
                grievanceEmail: 'privacy@studionine.example',
              ),
            )),
          ],
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'o1_today');
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await _save(tester, 'o_more');
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    await _save(tester, 'o10_rules');
  });
}
