import 'dart:async';

import 'package:craysalon/features/join/deep_link_listener.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

/// Opening the salon's printed QR with the app already installed.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late StreamController<Uri> links;

  setUp(() => links = StreamController<Uri>.broadcast());
  tearDown(() => links.close());

  Future<void> pump(WidgetTester tester, FakeCrayApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          deviceKeyProvider.overrideWithValue('test-device'),
          appLinkStreamProvider.overrideWithValue(links.stream),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a join link resolves the salon and NAMES it - it does not bind anyone',
      (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);

    links.add(Uri.parse('https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S'));
    await tester.pumpAndSettle();

    expect(api.resolvedCodes, ['CRAY-22335S']);
    // The confirmation screen, not a phone number and not a session: a link is
    // a code, and the salon is still agreed to first (RULES 4.1).
    expect(find.text("You're joining Studio Nine Salon"), findsOneWidget);
    expect(api.startedCodes, isEmpty);
    expect(api.verifications, isEmpty);
  });

  testWidgets('a link that is not a salon code changes nothing', (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);

    links.add(Uri.parse('https://example.com/s/CRAY-22335S'));
    links.add(Uri.parse('https://craysalon-join.crayoratech.workers.dev/pricing'));
    await tester.pumpAndSettle();

    expect(api.resolvedCodes, isEmpty);
    expect(find.text('Find your salon'), findsOneWidget);
  });

  testWidgets('a link arriving mid-flow does not restart someone who is typing',
      (tester) async {
    final api = FakeCrayApi(salon: fakeSalon(displayName: 'Salon Alpha'));
    await pump(tester, api);

    // They are already on the confirmation screen for Alpha.
    await tester.enterText(find.byType(TextField), 'CRAY-AAAQQQ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text("You're joining Salon Alpha"), findsOneWidget);

    // Someone's poster link arrives now. It must not hijack the flow.
    links.add(Uri.parse('https://craysalon-join.crayoratech.workers.dev/s/CRAY-BBBQQQ'));
    await tester.pumpAndSettle();

    expect(api.resolvedCodes, ['CRAY-AAAQQQ']);
    expect(find.text("You're joining Salon Alpha"), findsOneWidget);
  });
}
