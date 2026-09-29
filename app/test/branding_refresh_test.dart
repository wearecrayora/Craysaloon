import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';

/// PRD 20: "branding published in the console reaches the app on next open".
///
/// Before 0093 the app stored its salon's branding at join and never asked
/// again, so a salon that republished kept its old look on every phone.
void main() {
  const salonId = '11111111-0000-4000-8000-000000000001';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final cached = CachedBranding(
    salonId: salonId,
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(),
    grievance: const GrievanceContact(name: 'Sunita Rao', email: 'privacy@studionine.example'),
  );

  SalonSummary published({
    String salon = salonId,
    int version = 4,
    String name = 'Studio Nine',
    String primary = '#7a3b8f',
    GrievanceContact? grievance =
        const GrievanceContact(name: 'Sunita Rao', email: 'privacy@studionine.example'),
  }) =>
      SalonSummary(
        salonId: salon,
        displayName: name,
        brandingVersion: version,
        branding: publishedBranding(displayName: name, primaryLight: primary),
        grievance: grievance,
      );

  Future<ProviderContainer> pump(WidgetTester tester, FakeCrayApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'customer', salonId: salonId),
          ),
          initialBrandingProvider.overrideWithValue(cached),
          homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
          salonNotificationsProvider.overrideWithValue(FakeNotifications()),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(CraySalonApp)));
  }

  testWidgets('a republished brand is worn on open, and stored for offline', (tester) async {
    final api = FakeCrayApi()..mine = published();
    final container = await pump(tester, api);

    expect(api.myBrandingCalls, 1);
    final worn = container.read(resolvedBrandingProvider)!;
    expect(worn.version, 4);
    expect(worn.displayName, 'Studio Nine');

    // The theme follows - the new primary is on screen, not just in memory.
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).colorScheme.primary, const Color(0xFF7A3B8F));

    // And the next cold start, offline, opens in the new brand.
    final stored = await BrandingStore().read();
    expect(stored!.version, 4);
    expect(stored.displayName, 'Studio Nine');
  });

  testWidgets('coming back to the foreground is an "open" too', (tester) async {
    final api = FakeCrayApi()..mine = published();
    final container = await pump(tester, api);
    expect(container.read(resolvedBrandingProvider)!.version, 4);

    api.mine = published(version: 5, name: 'Studio Nine Unisex');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.myBrandingCalls, 2);
    expect(container.read(resolvedBrandingProvider)!.displayName, 'Studio Nine Unisex');
  });

  testWidgets('a changed privacy contact travels the same way', (tester) async {
    final api = FakeCrayApi()
      ..mine = published(
        version: 3,
        name: 'Studio Nine Salon',
        primary: '#1f6f5c',
        grievance: const GrievanceContact(name: 'Meena Iyer', phone: '9800012345'),
      );
    final container = await pump(tester, api);

    expect(container.read(resolvedBrandingProvider)!.grievance!.name, 'Meena Iyer');
    expect((await BrandingStore().read())!.grievance!.name, 'Meena Iyer');
  });

  testWidgets('offline, the cached brand stays - never the neutral fallback', (tester) async {
    final api = FakeCrayApi()..myBrandingError = const CrayApiException(CrayErrorKind.network);
    final container = await pump(tester, api);

    expect(api.myBrandingCalls, 1);
    expect(container.read(resolvedBrandingProvider), same(cached));
    expect(find.byType(SalonHome), findsOneWidget);
  });

  testWidgets('nothing changed: nothing is rewritten', (tester) async {
    final api = FakeCrayApi()
      ..mine = published(version: 3, name: 'Studio Nine Salon', primary: '#1f6f5c');
    final container = await pump(tester, api);

    expect(container.read(resolvedBrandingProvider), same(cached));
    expect(await BrandingStore().read(), isNull, reason: 'storage untouched');
  });

  testWidgets('an answer naming another salon is never worn (RULES 8.6)', (tester) async {
    final api = FakeCrayApi()
      ..mine = published(salon: '22222222-0000-4000-8000-000000000002', name: 'Other Salon');
    final container = await pump(tester, api);

    expect(container.read(resolvedBrandingProvider), same(cached));
    expect(await BrandingStore().read(), isNull);
  });
}
