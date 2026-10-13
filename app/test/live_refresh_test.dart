import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/features/customer/customer_providers.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';
import 'support/fake_customer_api.dart';

/// "A change in any salon's console reaches the customer's app without an
/// update or a reinstall" (13 Oct 2026). Every read was a FutureProvider that
/// kept its first answer for as long as the app lived, so a price changed in
/// the console reached a phone only after the app was killed and reopened.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'cray.shortcut_offered': true}));

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(),
  );

  Future<ProviderContainer> pump(WidgetTester tester, FakeCustomerApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          sessionProvider.overrideWithValue(api.session),
          initialBrandingProvider.overrideWithValue(branding),
          homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
          salonNotificationsProvider.overrideWithValue(FakeNotifications()),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(CraySalonApp)));
  }

  int haircut(ProviderContainer c) => c
      .read(bookableServicesProvider)
      .requireValue
      .firstWhere((s) => s.id == 's-cut')
      .pricePaise;

  void repriceHaircut(FakeCustomerApi api, int paise) {
    api.serviceList = [
      for (final s in api.serviceList)
        s.id == 's-cut'
            ? Service(
                id: s.id,
                name: s.name,
                pricePaise: paise,
                durationMinutes: s.durationMinutes,
                active: s.active,
                category: s.category,
              )
            : s,
    ];
  }

  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('a price changed in the console shows once the app comes back - no reinstall',
      (tester) async {
    final api = FakeCustomerApi();
    final c = await pump(tester, api);
    c.listen(bookableServicesProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(haircut(c), 60000);

    await background(tester);
    repriceHaircut(api, 65000); // the owner edits the menu in the console
    await foreground(tester);

    expect(haircut(c), 65000);
  });

  testWidgets('and a phone left open catches it within minutes', (tester) async {
    final api = FakeCustomerApi();
    final c = await pump(tester, api);
    c.listen(bookableServicesProvider, (_, _) {});
    await tester.pumpAndSettle();

    repriceHaircut(api, 70000);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(haircut(c), 60000, reason: 'not on every frame - a refresh every few minutes');

    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();
    expect(haircut(c), 70000);
  });

  testWidgets('control: nothing is re-read while the app sits in the background', (tester) async {
    final api = FakeCustomerApi();
    final c = await pump(tester, api);
    c.listen(bookableServicesProvider, (_, _) {});
    await tester.pumpAndSettle();

    await background(tester);
    repriceHaircut(api, 80000);
    await tester.pump(const Duration(minutes: 10));

    expect(haircut(c), 60000,
        reason: 'a phone in a pocket does not spend battery and data polling a salon');
  });
}
