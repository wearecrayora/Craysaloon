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
import 'package:craysalon/features/salon/salon_account.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'day_screen_test.dart' show FakeAccount;
import 'outbox_test.dart' show FakeBookings;
import 'owner_more_test.dart' show FakeHours;
import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';
import 'support/fake_customer_api.dart';
import 'wallet_test.dart' show FakeWalletApi;

/// IMPLEMENTATION 7, for the screens built in the redesign, on a small phone:
///
///   * every screen in `en`, `hi` (Devanagari) and `hi_Latn` (the longest
///     strings), at normal and 200% text - and not one overflow. Flutter
///     reports a clipped row as an exception; `takeException` turns it into a
///     failure naming the screen, the language and the scale.
///   * every screen in light, dark and the neutral (unbranded) default -
///     targets at least 48dp, every tappable thing labelled, text readable.
typedef _Variant = ({String name, Locale locale, double scale, bool dark, bool branded});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'cray.shortcut_offered': true}));

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Unisex Family Salon',
    version: 3,
    document: publishedBranding(displayName: 'Studio Nine Unisex Family Salon'),
  );

  final locales = {'en': kEnglish, 'hi': kHindi, 'hi_Latn': kHinglish};

  final List<_Variant> textVariants = [
    for (final MapEntry(key: name, value: locale) in locales.entries)
      for (final scale in [1.0, 2.0])
        (name: '$name ${scale}x', locale: locale, scale: scale, dark: false, branded: true),
  ];

  final List<_Variant> lookVariants = [
    (name: 'light', locale: kEnglish, scale: 1.0, dark: false, branded: true),
    (name: 'dark', locale: kEnglish, scale: 1.0, dark: true, branded: true),
    (name: 'neutral', locale: kEnglish, scale: 1.0, dark: false, branded: false),
  ];

  Future<void> sweep(
    WidgetTester tester, {
    required String role,
    required List<String> routes,
    required List<Override> overrides,
    required List<_Variant> variants,
    required Future<void> Function(WidgetTester tester, String where) check,
  }) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final v in variants) {
      await tester.pumpWidget(
        ProviderScope(
          // A fresh scope per variant: the overrides differ (branded or not).
          key: ValueKey(v.name),
          overrides: [
            sessionProvider.overrideWithValue(
              AppSession(appRole: role, salonId: '11111111-0000-4000-8000-000000000001'),
            ),
            if (v.branded) initialBrandingProvider.overrideWithValue(branding),
            homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
            salonNotificationsProvider.overrideWithValue(FakeNotifications()),
            ...overrides,
          ],
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 740),
              textScaler: TextScaler.linear(v.scale),
              platformBrightness: v.dark ? Brightness.dark : Brightness.light,
            ),
            child: const CraySalonApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(CraySalonApp)));
      container.read(localeProvider.notifier).select(v.locale);
      await tester.pumpAndSettle();

      for (final route in routes) {
        container.read(routerProvider).go(route);
        await tester.pumpAndSettle();
        await check(tester, '$route (${v.name})');
      }
    }
  }

  Future<void> noOverflow(WidgetTester tester, String where) async {
    final error = tester.takeException();
    expect(error, isNull, reason: '$where: $error');
  }

  Future<void> accessible(WidgetTester tester, String where) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: where);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: where);
    await expectLater(tester, meetsGuideline(textContrastGuideline), reason: where);
  }

  List<Override> customer() {
    final soon = DateTime.now().add(const Duration(days: 2));
    final api = FakeCustomerApi()
      ..due = NextDue(dueOn: DateTime(2026, 10, 14), serviceName: 'Hair spa and head massage')
      ..upcomingList = [
        UpcomingBooking(
          id: 'b-9',
          startsAt: DateTime(soon.year, soon.month, soon.day, 16, 30),
          endsAt: DateTime(soon.year, soon.month, soon.day, 17, 30),
          status: 'confirmed',
          totalPaise: 1250000,
          serviceNames: 'Haircut + Head massage + Beard shape and colour',
          staffName: 'Suresh Kumar',
        ),
      ]
      ..visitsList = [
        PastVisit(
          id: 'v1',
          completedAt: DateTime(2026, 9, 12),
          amountPaise: 1250000,
          paid: false,
          serviceNames: 'Haircut + Beard shape and colour + Hair spa',
          staffName: 'Suresh Kumar',
        ),
      ]
      ..documentList = [
        SalonDocument(
          kind: DocumentKind.taxInvoice,
          number: 'INV/2627/00001',
          issuedAt: DateTime(2026, 9, 12),
          visitId: 'v1',
          totalPaise: 1250000,
          taxablePaise: 1190476,
          cgstPaise: 29762,
          sgstPaise: 29762,
          gstRateBp: 500,
          gstin: '29ABCDE1234F1Z5',
          lines: const [DocumentLine(kind: 'service', name: 'Haircut', pricePaise: 1250000)],
        ),
      ];
    return [
      crayApiProvider.overrideWithValue(api),
      walletApiProvider.overrideWithValue(FakeWalletApi()),
    ];
  }

  const customerRoutes = [
    '/home',
    '/book',
    '/wallet',
    '/me',
    '/visits',
    '/documents',
    '/booking/b-9',
    '/your-data',
  ];

  List<Override> owner(CacheDb cache) {
    final remote = FakeBookings();
    final outbox = Outbox(cache);
    final hours = FakeHours()
      ..shiftList = const [
        Shift(staffId: 'st-1', day: 1, starts: '10:00', ends: '20:00'),
        Shift(staffId: 'st-1', day: 6, starts: '09:00', ends: '21:00'),
      ]
      ..offList = [
        TimeOff(
          id: 'h1',
          startsAt: DateTime(2026, 11, 8),
          endsAt: DateTime(2026, 11, 11),
          reason: 'Diwali and Bhai Dooj, the whole family is away',
        ),
      ];
    return [
      crayApiProvider.overrideWithValue(FakeCrayApi()),
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
      salonHoursApiProvider.overrideWithValue(hours),
      staffProvider.overrideWith(
        (ref) async => const Cached(
          [StaffMember(id: 'st-1', name: 'Suresh Kumar Venkataraman', active: true)],
          fromCache: false,
        ),
      ),
      salonAccountApiProvider.overrideWithValue(
        FakeAccount(
          const SalonBilling(
            state: 'grace',
            readOnly: true,
            plan: 'Salon with three stylists',
            monthlyPricePaise: 149900,
          ),
          profile: const SalonProfile(
            displayName: 'Studio Nine Unisex Family Salon',
            legalName: 'Studio Nine Unisex Family Salon Private Limited',
            address: '12th Main Road, HAL 2nd Stage, Indiranagar, Bengaluru 560038',
            email: 'privacy.officer@studionine.example',
            gstNumber: '29ABCDE1234F1Z5',
            gstRateBp: 500,
            walletRule: {'topup_paise': 100000, 'bonus_paise': 15000, 'min_topup_paise': 20000},
            rewardRule: {'referrer_paise': 10000, 'referred_paise': 5000},
            reminderCycleDays: 45,
            cancellationPolicy:
                'Free to cancel up to two hours before your time. Closer than that, please call the salon.',
            grievanceName: 'Sunita Rao',
            grievanceEmail: 'privacy.officer@studionine.example',
          ),
        ),
      ),
    ];
  }

  const ownerRoutes = [
    '/day',
    '/more',
    '/more/rules',
    '/more/hours',
    '/more/billing',
    '/more/profile',
    '/staff',
    '/staff/st-1/hours',
  ];

  testWidgets('customer screens: no clipping in any language, at 200% text', (tester) async {
    await sweep(
      tester,
      role: 'customer',
      routes: customerRoutes,
      overrides: customer(),
      variants: textVariants,
      check: noOverflow,
    );
  });

  testWidgets('owner screens: no clipping in any language, at 200% text', (tester) async {
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    await sweep(
      tester,
      role: 'owner',
      routes: ownerRoutes,
      overrides: owner(cache),
      variants: textVariants,
      check: noOverflow,
    );
  });

  testWidgets('customer screens: 48dp targets, labels and contrast - light, dark, unbranded',
      (tester) async {
    final handle = tester.ensureSemantics();
    await sweep(
      tester,
      role: 'customer',
      routes: customerRoutes,
      overrides: customer(),
      variants: lookVariants,
      check: accessible,
    );
    handle.dispose();
  });

  testWidgets('owner screens: 48dp targets, labels and contrast - light, dark, unbranded',
      (tester) async {
    final handle = tester.ensureSemantics();
    final cache = CacheDb(NativeDatabase.memory());
    addTearDown(cache.close);
    await sweep(
      tester,
      role: 'owner',
      routes: ownerRoutes,
      overrides: owner(cache),
      variants: lookVariants,
      check: accessible,
    );
    handle.dispose();
  });
}
