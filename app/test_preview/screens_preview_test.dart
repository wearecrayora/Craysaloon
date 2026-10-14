// Screenshots of every screen, with REAL fonts, for design review.
//
//   FONTS_DIR=<dir with Inter.ttf, Fraunces.ttf, NotoDeva.ttf> \
//   PREVIEW_DIR=<out dir> flutter test test_preview/screens_preview_test.dart
//
// Not a gate - it asserts nothing and is not in CI (it lives outside test/).
// Widget tests render text in a box font; this loads the families the theme
// names, plus Flutter's Material icons, so the PNGs look like the phone.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:craysalon/app/providers.dart';
import 'package:craysalon/app/router.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/outbox.dart';
import 'package:craysalon/data/repositories/day_repository.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/owner/hours_screens.dart';
import 'package:craysalon/features/owner/logins_screen.dart';
import 'package:craysalon/features/salon/salon_account.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/day_screen_test.dart' show FakeAccount;
import '../test/logins_screen_test.dart' show FakeLogins;
import '../test/outbox_test.dart' show FakeBookings;
import '../test/owner_more_test.dart' show FakeHours;
import '../test/salon_home_test.dart' show FakeNotifications, FakeShortcut;
import '../test/support/fake_cray_api.dart';
import '../test/support/fake_customer_api.dart';
import '../test/wallet_test.dart' show FakeWalletApi;

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final f = File(p);
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await loader.load();
}

void main() {
  final fonts = Platform.environment['FONTS_DIR'] ?? '';
  final out = Platform.environment['PREVIEW_DIR'] ?? '.';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final material = '$flutterRoot/bin/cache/artifacts/material_fonts';

  setUpAll(() async {
    await _loadFont('Inter', ['$fonts/Inter.ttf']);
    await _loadFont('Fraunces', ['$fonts/Fraunces.ttf']);
    await _loadFont('Noto Sans Devanagari', ['$fonts/NotoDeva.ttf']);
    await _loadFont('Roboto', [
      '$material/roboto-regular.ttf',
      '$material/roboto-medium.ttf',
      '$material/roboto-bold.ttf',
    ]);
    await _loadFont('MaterialIcons', ['$material/materialicons-regular.otf']);
  });
  setUp(
    // ignore: invalid_use_of_visible_for_testing_member
    () => SharedPreferences.setMockInitialValues({'cray.shortcut_offered': true}),
  );

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(displayName: 'Studio Nine Salon'),
  );

  List<Override> customer() {
    final soon = DateTime.now().add(const Duration(days: 2));
    final api = FakeCustomerApi()
      ..due = NextDue(
        dueOn: DateTime.now().add(const Duration(days: 5)),
        serviceName: 'Hair spa',
      )
      ..upcomingList = [
        UpcomingBooking(
          id: 'b-9',
          startsAt: DateTime(soon.year, soon.month, soon.day, 16, 30),
          endsAt: DateTime(soon.year, soon.month, soon.day, 17, 30),
          status: 'confirmed',
          totalPaise: 125000,
          serviceNames: 'Haircut + Head massage',
          staffName: 'Suresh Kumar',
        ),
      ]
      ..visitsList = [
        PastVisit(
          id: 'v1',
          completedAt: DateTime(2026, 9, 12),
          amountPaise: 85000,
          paid: true,
          serviceNames: 'Haircut + Beard trim',
          staffName: 'Suresh Kumar',
        ),
        PastVisit(
          id: 'v2',
          completedAt: DateTime(2026, 8, 20),
          amountPaise: 120000,
          paid: true,
          serviceNames: 'Hair spa',
          staffName: 'Priya',
        ),
      ];
    return [
      crayApiProvider.overrideWithValue(api),
      walletApiProvider.overrideWithValue(FakeWalletApi()),
    ];
  }

  List<Override> owner(CacheDb cache, {bool busy = false}) {
    final n = DateTime.now();
    BookingRow row(
      String id,
      int hour,
      int minute,
      String status,
      String who,
      String what,
      int paise, {
      String? paid,
    }) => BookingRow(
      id: id,
      customerId: 'c-$id',
      startsAt: DateTime(n.year, n.month, n.day, hour, minute),
      endsAt: DateTime(n.year, n.month, n.day, hour, minute + 45),
      status: status,
      totalPaise: paise,
      customerName: who,
      staffName: 'Suresh Kumar',
      serviceNames: what,
      paymentStatus: paid,
      customerHasApp: true,
    );
    final remote = FakeBookings()
      ..dayRows = busy
          ? [
              row(
                'b1',
                10,
                30,
                'completed',
                'Asha Rao',
                'Haircut + Beard trim',
                85000,
                paid: 'paid',
              ),
              row('b2', 12, 0, 'in_progress', 'Meera Iyer', 'Hair spa', 120000),
              row('b3', 15, 30, 'confirmed', 'Rohan Das', 'Haircut', 40000),
            ]
          : const [];
    final outbox = Outbox(cache);
    return [
      crayApiProvider.overrideWithValue(FakeCrayApi()),
      staffLoginsApiProvider.overrideWithValue(FakeLogins()),
      cacheDbProvider.overrideWithValue(cache),
      outboxProvider.overrideWithValue(outbox),
      dayRepositoryProvider.overrideWithValue(
        DayRepository(
          remote: remote,
          cache: cache,
          outbox: outbox,
          salonId: '11111111-0000-4000-8000-000000000001',
        ),
      ),
      salonHoursApiProvider.overrideWithValue(
        FakeHours()
          ..shiftList = const [
            Shift(staffId: 'st-1', day: 1, starts: '10:00', ends: '17:00'),
          ],
      ),
      staffProvider.overrideWith(
        (ref) async => const Cached([
          StaffMember(id: 'st-1', name: 'Suresh Kumar', active: true),
          StaffMember(id: 'st-2', name: 'Priya', active: true),
        ], fromCache: false),
      ),
      salonAccountApiProvider.overrideWithValue(
        FakeAccount(
          const SalonBilling(
            state: 'active',
            readOnly: false,
            plan: 'Growth',
            monthlyPricePaise: 149900,
          ),
          profile: const SalonProfile(
            displayName: 'Studio Nine Salon',
            legalName: 'Studio Nine Salon LLP',
            address: 'Indiranagar, Bengaluru',
            walletRule: {
              'topup_paise': 100000,
              'bonus_paise': 15000,
              'min_topup_paise': 20000,
            },
            rewardRule: {'referrer_paise': 10000, 'referred_paise': 5000},
            reminderCycleDays: 30,
            grievanceName: 'Sunita Rao',
            grievanceEmail: 'privacy@studionine.example',
          ),
        ),
      ),
    ];
  }

  Future<void> shoot(
    WidgetTester tester,
    String role,
    List<Override> overrides,
    List<String> routes, {
    bool dark = false,
    bool branded = true,
    String tag = '',
  }) async {
    // Tests draw elevation as a hard black outline; the phone does not.
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(
              role == 'join'
                  ? null
                  : AppSession(
                      appRole: role,
                      salonId: role == 'platform_admin' ? null : '11111111-0000-4000-8000-000000000001',
                    ),
            ),
            if (branded) initialBrandingProvider.overrideWithValue(branding),
            homeShortcutProvider.overrideWithValue(
              FakeShortcut(supported: false),
            ),
            salonNotificationsProvider.overrideWithValue(FakeNotifications()),
            ...overrides,
          ],
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              devicePixelRatio: 3,
              platformBrightness: dark ? Brightness.dark : Brightness.light,
            ),
            child: const CraySalonApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CraySalonApp)),
    );
    for (final route in routes) {
      if (role != 'join' && role != 'platform_admin') container.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final name =
            '$role$tag${dark ? '_dark' : ''}${route.replaceAll('/', '_')}.png';
        File('$out/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    debugDisableShadows = true;
  }

  const customerRoutes = [
    '/home', '/book', '/wallet', '/me', '/visits', '/documents', '/booking/b-9', '/wallet/add', '/refer', '/your-data',
  ];
  const ownerRoutes = [
    '/day', '/day/walk-in', '/attention', '/dashboard', '/customers', '/catalogue/services', '/catalogue/addons',
    '/staff', '/staff/st-1/hours', '/staff/logins', '/more', '/more/rules', '/more/hours', '/more/billing', '/more/profile',
  ];

  testWidgets('customer', (tester) async {
    await shoot(tester, 'customer', customer(), customerRoutes);
  });
  testWidgets('customer dark', (tester) async {
    await shoot(tester, 'customer', customer(), const [
      '/home',
      '/wallet',
    ], dark: true);
  });
  testWidgets('owner', (tester) async {
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    await shoot(tester, 'owner', owner(cache), ownerRoutes);
  });
  testWidgets('owner busy', (tester) async {
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    await shoot(tester, 'owner', owner(cache, busy: true), const [
      '/day',
    ], tag: '_busy');
  });
  testWidgets('stylist', (tester) async {
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    await shoot(tester, 'staff', owner(cache, busy: true), const ['/day', '/customers', '/more']);
  });
  testWidgets('platform admin', (tester) async {
    await shoot(tester, 'platform_admin', const [], const ['/console-only']);
  });
  testWidgets('join', (tester) async {
    await shoot(
      tester,
      'join',
      [
        crayApiProvider.overrideWithValue(
          FakeCrayApi(salon: fakeSalon(displayName: 'Studio Nine Salon')),
        ),
      ],
      const ['/join'],
      branded: false,
    );
  });
}
