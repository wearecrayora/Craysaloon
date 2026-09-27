import 'package:craysalon/core/platform/home_shortcut.dart';
import 'package:craysalon/core/platform/salon_notifications.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

class FakeShortcut implements HomeShortcut {
  FakeShortcut({this.supported = true, this.accept = true});

  bool supported;
  bool accept;
  final List<String> offered = [];

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> offer({required String label, Uint8List? logo}) async {
    offered.add(label);
    return accept;
  }
}

class FakeNotifications implements SalonNotifications {
  final List<String> channels = [];
  int? accent;

  @override
  Future<void> ensureChannel({required String salonName, int? accentArgb}) async {
    channels.add(salonName);
    accent = accentArgb;
  }
}

/// The two M4 things that belong to binding rather than to a feature: the app
/// wearing the salon's brand, and the offer to put the salon on the home screen.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final branding = CachedBranding(
    salonId: '11111111-0000-4000-8000-000000000001',
    displayName: 'Studio Nine Salon',
    version: 3,
    document: publishedBranding(),
  );

  Future<void> pump(
    WidgetTester tester, {
    required FakeShortcut shortcut,
    required FakeNotifications notifications,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          hasSessionProvider.overrideWithValue(true),
          initialBrandingProvider.overrideWithValue(branding),
          homeShortcutProvider.overrideWithValue(shortcut),
          salonNotificationsProvider.overrideWithValue(notifications),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a bound install opens in the salon\'s brand, from the cache alone',
      (tester) async {
    await pump(tester, shortcut: FakeShortcut(), notifications: FakeNotifications());

    expect(find.text('Studio Nine Salon'), findsOneWidget);
    final theme = Theme.of(tester.element(find.byType(SalonHome)));
    expect(theme.colorScheme.primary, const Color(0xFF1F6F5C));
  });

  testWidgets('the notification channel is named for the salon', (tester) async {
    final notifications = FakeNotifications();
    await pump(tester, shortcut: FakeShortcut(), notifications: notifications);

    expect(notifications.channels, ['Studio Nine Salon']);
    expect(notifications.accent, const Color(0xFF1F6F5C).toARGB32());
  });

  testWidgets('the home-screen shortcut is an offer, and only offered once',
      (tester) async {
    final shortcut = FakeShortcut();
    await pump(tester, shortcut: shortcut, notifications: FakeNotifications());

    expect(find.text('Add to home screen'), findsOneWidget);
    await tester.tap(find.text('Add to home screen'));
    await tester.pumpAndSettle();

    expect(shortcut.offered, ['Studio Nine Salon']);
    expect(find.text('Added. Look for it on your home screen.'), findsOneWidget);

    // Never nag: a fresh launch does not ask again (ARCHITECTURE 7.3).
    await pump(tester, shortcut: shortcut, notifications: FakeNotifications());
    expect(find.text('Add to home screen'), findsNothing);
  });

  testWidgets('declining is remembered, and claims nothing was added', (tester) async {
    final shortcut = FakeShortcut();
    await pump(tester, shortcut: shortcut, notifications: FakeNotifications());

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(shortcut.offered, isEmpty);
    expect(find.text('Added. Look for it on your home screen.'), findsNothing);
    expect(find.text('Add to home screen'), findsNothing);
  });

  testWidgets('a refused request never claims an icon exists', (tester) async {
    // Android shows its own dialog and can come back with no.
    final shortcut = FakeShortcut(accept: false);
    await pump(tester, shortcut: shortcut, notifications: FakeNotifications());

    await tester.tap(find.text('Add to home screen'));
    await tester.pumpAndSettle();

    expect(find.text('Added. Look for it on your home screen.'), findsNothing);
  });

  testWidgets('an unsupported launcher - and every iPhone - is offered nothing',
      (tester) async {
    // iOS has NO equivalent API (ARCHITECTURE 7.3, RULES 8.11). The offer must
    // be absent, not present-and-failing.
    await pump(
      tester,
      shortcut: FakeShortcut(supported: false),
      notifications: FakeNotifications(),
    );

    expect(find.text('Add to home screen'), findsNothing);
    expect(find.text('Studio Nine Salon'), findsOneWidget);
  });
}
