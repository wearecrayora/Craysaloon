import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

/// The join flow, as a customer standing in a salon meets it.
///
/// The rules being asserted here are not UI preferences:
///   * the salon is known and NAMED before a phone number is asked for
///     (`RULES.md` 4.1, 4.2)
///   * the app wears the salon's brand from the moment the code resolves
///   * marketing consent starts OFF and is passed as the customer left it
///   * "already registered" never names the other salon (`RULES.md` 4.4)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, FakeCrayApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(api),
          deviceKeyProvider.overrideWithValue('test-device'),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The phone step shows the DPDP notice above the controls, so the button and
  /// the consent boxes start below the fold. **That is deliberate** (RULES
  /// 11.6a): a customer scrolls past what their data is for on the way to
  /// giving it. The test scrolls the same way a thumb does.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    // A ListView does not build what is off-screen, so ensureVisible cannot
    // find it - the notice has to be scrolled through, exactly as a thumb does.
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> tapBelow(WidgetTester tester, Finder finder) async {
    await scrollTo(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('salon code first: the salon is named before any phone number', (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);

    // Nothing has asked for a phone number yet.
    expect(find.text('Find your salon'), findsOneWidget);
    expect(find.text('Your mobile number'), findsNothing);

    await enterCode(tester, 'cray 22335s');

    // Normalised before it was sent.
    expect(api.resolvedCodes, ['CRAY-22335S']);
    expect(find.text("You're joining Studio Nine Salon"), findsOneWidget);
  });

  testWidgets('the app wears the salon\'s brand from the moment the code resolves',
      (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);

    final before = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;
    await enterCode(tester, 'CRAY-22335S');
    final after = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;

    expect(before, isNot(const Color(0xFF1F6F5C)));
    expect(after, const Color(0xFF1F6F5C), reason: 'the login screen is already the salon\'s');
  });

  testWidgets('an unknown code and a salon in setup look identical', (tester) async {
    // The fake returns null for both, exactly as resolve_join_code does: a
    // leaked QR must not reveal that a salon is on its way.
    final api = FakeCrayApi();
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');

    expect(find.text("That code didn't match a salon. Check it and try again."), findsOneWidget);
    expect(find.text('Your mobile number'), findsNothing);
  });

  testWidgets('a number is verified, consent is passed as left, and the customer is in',
      (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your mobile number'), findsOneWidget);

    // The notice is on this screen, with the salon named as the Data Fiduciary
    // and the salon's OWN privacy contact - not Crayora's (RULES 11.7).
    expect(find.text('What Studio Nine Salon will know about you'), findsOneWidget);
    expect(find.text('Sunita Rao'), findsOneWidget);
    expect(find.text('privacy@studionine.example'), findsOneWidget);

    // Marketing consent is opt-in: both boxes start unticked (RULES 11).
    await scrollTo(tester, find.text('Offers on WhatsApp too'));
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(2), reason: 'both consent boxes exist, and are asked separately');
    expect(boxes.every((b) => b.value == false), isTrue);

    await scrollTo(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '8114325023');
    await tapBelow(tester, find.text('Get my code'));

    expect(api.startedCodes, ['CRAY-22335S']);
    expect(api.sentTo, ['8114325023']);
    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    // The number is not echoed back in full to whoever is looking at the screen.
    expect(find.textContaining('8114325023'), findsNothing);
    expect(find.textContaining('5023'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '573649');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(api.verifications.single['promotional'], false);
    expect(api.verifications.single['whatsapp'], false);
    expect(find.text('Welcome to Studio Nine Salon'), findsOneWidget);
  });

  testWidgets('ticking WhatsApp implies the marketing consent it depends on', (tester) async {
    final api = FakeCrayApi(salon: fakeSalon());
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tapBelow(tester, find.text('Offers on WhatsApp too'));

    await scrollTo(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '8114325023');
    await tapBelow(tester, find.text('Get my code'));
    await tester.enterText(find.byType(TextField), '573649');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(api.verifications.single['whatsapp'], true);
    expect(api.verifications.single['promotional'], true,
        reason: 'offers on WhatsApp are still offers');
  });

  testWidgets('a number bound elsewhere is refused WITHOUT naming the other salon',
      (tester) async {
    final api = FakeCrayApi(
      salon: fakeSalon(displayName: 'Salon Beta'),
      verifyError: const CrayApiException(CrayErrorKind.alreadyBound),
    );
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '8114325023');
    await tapBelow(tester, find.text('Get my code'));
    await tester.enterText(find.byType(TextField), '573649');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('This number is already registered with a salon.'), findsOneWidget);
    // Not "registered with Salon Alpha". The app is not told which salon, and
    // must not imply one either.
    expect(find.textContaining('Alpha'), findsNothing);
    expect(find.text('Welcome to Salon Beta'), findsNothing);
  });

  testWidgets('a blocked or suspended salon says so plainly, and blames nobody',
      (tester) async {
    final api = FakeCrayApi(
      salon: fakeSalon(),
      sendError: const CrayApiException(CrayErrorKind.salonUnavailable),
    );
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '8114325023');
    await tapBelow(tester, find.text('Get my code'));

    expect(
      find.text("This salon can't take sign-ins right now. Please ask at the counter."),
      findsOneWidget,
    );
    expect(find.text('Enter the 6-digit code'), findsNothing);
  });

  testWidgets('a wrong code says how many tries are left', (tester) async {
    final api = FakeCrayApi(
      salon: fakeSalon(),
      verifyError: const CrayApiException(CrayErrorKind.wrongCode, attemptsLeft: 2),
    );
    await pump(tester, api);
    await enterCode(tester, 'CRAY-22335S');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '8114325023');
    await tapBelow(tester, find.text('Get my code'));
    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text("That code didn't match. 2 left."), findsOneWidget);
  });
}
