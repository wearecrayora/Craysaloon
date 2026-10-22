import 'package:craysalon/app/providers.dart';
import 'package:craysalon/app/router.dart';
import 'package:craysalon/core/platform/otp_autofill.dart';
import 'package:craysalon/core/ui/service_icon.dart';
import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/features/join/deep_link_listener.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/join/join_screen.dart';
import 'package:craysalon/features/privacy/your_data_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';
import 'support/fake_customer_api.dart';
import 'your_data_test.dart' show FakePrivacyApi;

/// The 21 Oct 2026 redesign: what it promises, held.
///
///   * the profile edits the name and language - never the phone, whose change
///     is a correction REQUEST (0118, RULES 4)
///   * the code is read from the SMS only through Android's consent prompt,
///     and only the code is taken from it
///   * search finds the salon's services and books one with only that chosen
///   * every service gets a picture, without the salon uploading one
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'cray.shortcut_offered': true}));

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    FakeCustomerApi api, {
    FakePrivacyApi? privacy,
  }) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          sessionProvider.overrideWithValue(api.session),
          initialBrandingProvider.overrideWithValue(branding),
          homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
          salonNotificationsProvider.overrideWithValue(FakeNotifications()),
          if (privacy != null) privacyApiProvider.overrideWithValue(privacy),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(CraySalonApp)));
  }

  group('edit profile (0118)', () {
    testWidgets('the name is saved, and Save waits for a change', (tester) async {
      final api = FakeCustomerApi();
      final app = await pump(tester, api);
      app.read(routerProvider).push('/me/edit');
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save changes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull,
          reason: 'nothing changed, nothing to save');

      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'Asha R Rao');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(api.savedProfile?.name, 'Asha R Rao');
      expect(find.text('Profile saved'), findsOneWidget);
    });

    testWidgets('a refused name says why, in words', (tester) async {
      final api = FakeCustomerApi();
      final app = await pump(tester, api);
      app.read(routerProvider).push('/me/edit');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Full name'), 'A');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('A name needs 2 to 60 characters.'), findsOneWidget);
    });

    testWidgets('the number is not a field: changing it is a correction request',
        (tester) async {
      final api = FakeCustomerApi();
      final privacy = FakePrivacyApi();
      final app = await pump(tester, api, privacy: privacy);
      app.read(routerProvider).push('/me/edit');
      await tester.pumpAndSettle();

      // Shown, masked, and not editable: only two fields exist on the form,
      // and neither is the number.
      expect(find.text('+91 98xxx x4821'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('Change your number'), findsOneWidget);
      await tester.tap(find.text('Ask for the change'));
      await tester.pumpAndSettle();

      expect(privacy.requested, ['correction']);
      expect(api.savedProfile, isNull, reason: 'no profile write carries a phone');
      expect(find.text('Asked. The salon has 30 days to answer.'), findsOneWidget);
    });
  });

  group('my bookings', () {
    FakeCustomerApi api0() {
      final soon = DateTime.now().add(const Duration(days: 3));
      return FakeCustomerApi()
        ..upcomingList = [
          UpcomingBooking(
            id: 'b-up',
            startsAt: DateTime(soon.year, soon.month, soon.day, 16, 30),
            endsAt: DateTime(soon.year, soon.month, soon.day, 17, 30),
            status: 'confirmed',
            totalPaise: 50000,
            serviceNames: 'Haircut',
          ),
        ]
        ..visitsList = [
          PastVisit(
            id: 'v-1',
            completedAt: DateTime(2026, 9, 12),
            amountPaise: 120000,
            paid: true,
            serviceNames: 'Haircut + Beard trim',
          ),
        ]
        ..closedList = [
          UpcomingBooking(
            id: 'b-x',
            startsAt: DateTime(2026, 8, 30, 11),
            endsAt: DateTime(2026, 8, 30, 12),
            status: 'cancelled',
            totalPaise: 80000,
            serviceNames: 'Gold facial',
          ),
        ];
    }

    testWidgets('upcoming, done and cancelled are in one place', (tester) async {
      final app = await pump(tester, api0());
      app.read(routerProvider).go('/bookings');
      await tester.pumpAndSettle();

      expect(find.text('My bookings'), findsWidgets);
      expect(find.text('In 3 days · 4:30 PM'), findsOneWidget);
      expect(find.text('Haircut + Beard trim'), findsOneWidget);
      expect(find.text('Gold facial'), findsOneWidget);
      expect(find.text('Book again'), findsNWidgets(2));

      // Narrowing to Cancelled keeps only the cancelled one.
      await tester.ensureVisible(find.text('Cancelled · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelled · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Gold facial'), findsOneWidget);
      expect(find.text('Haircut + Beard trim'), findsNothing);
      expect(find.text('In 3 days · 4:30 PM'), findsNothing);
    });

    testWidgets('book again chooses the same service, and nothing else', (tester) async {
      final api = api0();
      final app = await pump(tester, api);
      app.read(routerProvider).go('/bookings');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Completed · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book again'));
      await tester.pumpAndSettle();

      final haircut = api.serviceList.where((s) => s.name == 'Haircut').firstOrNull;
      expect(app.read(routerProvider).state.uri.queryParameters['service'], haircut?.id);
    });

    testWidgets('right after booking: the moment, then the journey', (tester) async {
      final app = await pump(tester, api0());
      app.read(routerProvider).push('/booking/b-up?new=1');
      await tester.pumpAndSettle();
      expect(find.text("You're booked!"), findsOneWidget);
      expect(find.text('Your visit day'), findsOneWidget);

      // Opened again later, it is just the booking.
      app.read(routerProvider).pop();
      await tester.pumpAndSettle();
      app.read(routerProvider).push('/booking/b-up');
      await tester.pumpAndSettle();
      expect(find.text("You're booked!"), findsNothing);
    });

    testWidgets('the Bookings tab counts what is still to come', (tester) async {
      await pump(tester, api0());
      final bar = find.byType(NavigationBar);
      expect(find.descendant(of: bar, matching: find.text('Bookings')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('1')), findsWidgets);
    });
  });

  group('search and booking', () {
    testWidgets('search finds a service and books it with only that chosen', (tester) async {
      final api = FakeCustomerApi();
      final app = await pump(tester, api);
      app.read(routerProvider).push('/search');
      await tester.pumpAndSettle();

      // Only what can be booked: an inactive service is not on the menu.
      final active = api.serviceList.where((s) => s.active).toList();
      final all = active.length;
      expect(find.text('All $all services'), findsOneWidget);

      final target = active.first;
      final word = target.name.split(' ').first;
      await tester.enterText(find.byType(TextField), word);
      await tester.pumpAndSettle();
      expect(find.text(target.name), findsWidgets);

      await tester.tap(find.text(target.name).first);
      await tester.pumpAndSettle();

      // On the booking, that service is the one ticked, and Continue is live.
      expect(app.read(routerProvider).state.uri.queryParameters['service'], target.id);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('nothing found says so, with the word they typed', (tester) async {
      final app = await pump(tester, FakeCustomerApi());
      app.read(routerProvider).push('/search');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzqq');
      await tester.pumpAndSettle();
      expect(find.textContaining('"zzqq"'), findsOneWidget);
    });
  });

  group('the code from the SMS', () {
    test('only the six-digit code is taken from the message', () {
      expect(codeIn('Your verification code is 482913. Valid for 1 minute.'), '482913');
      expect(codeIn('482913 is your code'), '482913');
      // A longer number is not a code, and neither is a phone number.
      expect(codeIn('Call 9812344821 for help'), isNull);
      expect(codeIn('No digits here'), isNull);
    });

    testWidgets('allowed on the phone, the code fills in and is checked at once',
        (tester) async {
      final api = FakeCrayApi(salon: fakeSalon(displayName: 'Studio Nine Salon'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            crayApiProvider.overrideWithValue(api),
            deviceKeyProvider.overrideWithValue('test-device'),
            otpAutofillProvider.overrideWithValue(_Autofill('573649')),
            appLinkStreamProvider.overrideWithValue(const Stream.empty()),
          ],
          child: const CraySalonApp(),
        ),
      );
      await tester.pumpAndSettle();
      final join = ProviderScope.containerOf(tester.element(find.byType(JoinScreen)))
          .read(joinControllerProvider.notifier);
      await join.submitCode('CRAY-22335S');
      join.confirmSalon();
      join.setAdult(true);
      await join.submitPhone('9812344821');
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Studio Nine Salon'), findsOneWidget);
    });
  });

  test('every service gets a picture, from its own words', () {
    expect(serviceIcon('Haircut'), Icons.content_cut);
    expect(serviceIcon('Beard shape and colour', category: 'Beard'), Icons.face_6_outlined);
    expect(serviceIcon('Gold facial'), Icons.face_retouching_natural);
    expect(serviceIcon('बाल कटिंग'), Icons.content_cut);
    expect(serviceIcon('Something new'), Icons.spa_outlined);
  });
}

class _Autofill implements OtpAutofill {
  _Autofill(this.code);

  final String code;

  @override
  Future<String?> listen() async => code;

  @override
  Future<void> cancel() async {}
}
