import 'package:craysalon/app/providers.dart';
import 'package:craysalon/core/platform/external_link.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/privacy/privacy.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/privacy/consent_notice.dart';
import 'package:craysalon/features/privacy/your_data_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

/// "Your data", and the notice that precedes it.
///
/// These are gates in the same sense as the database ones: they assert
/// entitlements, not behaviour someone chose. A build that cannot withdraw a
/// consent in one tap, that shows a consent it failed to read as "off", or that
/// lets erasure be asked for without first saying what erasure keeps, is a
/// build that puts every salon using it in breach - and the salon is the one the
/// penalty lands on (DPDP ss.6(4), 8, 11, 12(3), 13).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakePrivacyApi privacy;

  setUp(() => privacy = FakePrivacyApi());

  Future<void> pump(
    WidgetTester tester, {
    GrievanceContact? grievance = const GrievanceContact(
      name: 'Sunita Rao',
      email: 'privacy@studionine.example',
    ),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'customer', salonId: 'salon-a'),
          ),
          privacyApiProvider.overrideWithValue(privacy),
          externalLinkProvider.overrideWithValue(link),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The customer is home. Wear the salon's branding first, so the notice has
    // a salon to name - after binding this comes from the cache, not the wire.
    final context = tester.element(find.byType(Scaffold));
    ProviderScope.containerOf(context).read(resolvedBrandingProvider.notifier).wear(
          CachedBranding(
            salonId: 'salon-a',
            displayName: 'Studio Nine Salon',
            version: 3,
            document: publishedBranding(displayName: 'Studio Nine Salon'),
            grievance: grievance,
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.shield_outlined));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the rights are one tap from the salon home, not buried', (tester) async {
    await pump(tester);
    expect(find.text('Your data'), findsWidgets);
    expect(find.text('What you have agreed to'), findsOneWidget);
  });

  testWidgets('what is shown is what the server holds, purpose by purpose',
      (tester) async {
    await pump(tester);

    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches, hasLength(4), reason: 'four purposes, each consented to separately');

    // The fake holds promotional on, whatsapp off, photos off.
    expect(switches[1].value, isTrue);
    expect(switches[2].value, isFalse);
    expect(switches[3].value, isFalse);
  });

  testWidgets('withdrawing marketing consent is ONE tap, with no confirmation',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Offers from this salon'));
    await tester.pumpAndSettle();

    // s.6(4): as easy as consent was. Consent was a tick box, so withdrawal is
    // a tap - not a dialog, not an email, not a support request.
    expect(privacy.written, [('promotional', false)]);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches[1].value, isFalse);
  });

  testWidgets('service messages cannot be switched off, and the screen says why',
      (tester) async {
    await pump(tester);

    final service =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).first;
    expect(service.value, isTrue);
    expect(service.onChanged, isNull,
        reason: 'disabled rather than hidden: someone looking for these must find them');
    expect(
      find.text('Part of the service. To stop these, ask for your account to be deleted.'),
      findsWidgets,
    );
  });

  testWidgets('a consent that failed to save springs back to what the server holds',
      (tester) async {
    privacy.failWrites = true;
    await pump(tester);

    await tester.tap(find.text('Offers from this salon'));
    await tester.pumpAndSettle();

    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches[1].value, isTrue,
        reason: 'a consent record the customer cannot trust is worse than an error');
    expect(find.text('That did not save. Check your connection and try again.'),
        findsOneWidget);
  });

  testWidgets('a load that failed does not report every consent as off', (tester) async {
    privacy.failReads = true;
    await pump(tester);

    // Showing four unticked switches would be a false statement about a legal
    // record - and the one it would get wrong is marketing.
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('That did not save. Check your connection and try again.'),
        findsOneWidget);
  });

  testWidgets('asking for a copy records the request and shows when it is due',
      (tester) async {
    await pump(tester);

    await scrollTo(tester, find.text('Ask for a copy of my data'));
    await tester.tap(find.text('Ask for a copy of my data'));
    await tester.pumpAndSettle();

    expect(privacy.requested, ['access']);
    // The button becomes a receipt: asking twice helps nobody, and the due date
    // is what makes the obligation visible rather than remembered (RULES 11.11).
    expect(find.textContaining('Answer due by'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('erasure says what it keeps BEFORE it is asked for', (tester) async {
    await pump(tester);

    await scrollTo(tester, find.text('Ask for my account to be deleted'));
    await tester.tap(find.text('Ask for my account to be deleted'));
    await tester.pumpAndSettle();

    // RULES 11.8: erasure is anonymisation. The money stays, without a name on
    // it, and nobody should discover that afterwards.
    expect(find.text('Ask to be deleted?'), findsOneWidget);
    expect(
      find.textContaining('Payments and wallet records stay without your name'),
      findsOneWidget,
    );
    expect(privacy.requested, isEmpty, reason: 'nothing is asked for until it is confirmed');

    await tester.tap(find.text('Yes, ask for deletion'));
    await tester.pumpAndSettle();
    expect(privacy.requested, ['erasure']);
  });

  testWidgets('cancelling the erasure dialog asks for nothing', (tester) async {
    await pump(tester);

    await scrollTo(tester, find.text('Ask for my account to be deleted'));
    await tester.tap(find.text('Ask for my account to be deleted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(privacy.requested, isEmpty);
  });

  testWidgets('the notice names the SALON, and carries the salon\'s own contact',
      (tester) async {
    await pump(tester);

    await scrollTo(tester, find.text('Who holds your data'));

    // The salon is the Data Fiduciary; Crayora is the Processor (RULES 11.7).
    expect(find.text('What Studio Nine Salon will know about you'), findsOneWidget);
    expect(
      find.text(
          'Studio Nine Salon decides what it keeps and why. Crayora makes the app and stores it for them.'),
      findsOneWidget,
    );
    expect(find.text('Sunita Rao'), findsOneWidget);
  });

  testWidgets('the contact is openable, not just printed', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('privacy@studionine.example'));
    await tester.tap(find.text('privacy@studionine.example'));
    await tester.pumpAndSettle();

    // "Reachable" is the requirement. Retyping an address into a mail app is
    // how a complaint quietly stops being made.
    expect(link.opened.map((u) => u.toString()), ['mailto:privacy@studionine.example']);

    await tester.tap(find.text('Read the full privacy policy'));
    await tester.pumpAndSettle();
    expect(link.opened.last.toString(), 'https://craysalon-join.crayoratech.workers.dev/privacy');
  });

  testWidgets('a salon with no privacy contact says so instead of inventing one',
      (tester) async {
    // Only possible for a salon activated before 0053 made the contact
    // mandatory. The notice degrades; it never shows a made-up name.
    await pump(tester, grievance: null);
    await scrollTo(tester, find.text('Who holds your data'));

    expect(find.text('Ask at the salon counter. If nobody answers, write to Crayora.'),
        findsOneWidget);
    expect(find.text('Sunita Rao'), findsNothing);
  });

  testWidgets('nothing clips at 200% text scale', (tester) async {
    await pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}

final link = FakeExternalLink();

class FakeExternalLink implements ExternalLink {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class FakePrivacyApi implements PrivacyApi {
  bool failReads = false;
  bool failWrites = false;

  final written = <(String, bool)>[];
  final requested = <String>[];
  final _requests = <DataRightRequest>[];

  @override
  Future<List<ConsentState>> consents() async {
    if (failReads) throw const CrayApiException(CrayErrorKind.network);
    return [
      ConsentState(
          purpose: ConsentPurpose.service, granted: true, occurredAt: DateTime(2026, 9, 1)),
      ConsentState(
          purpose: ConsentPurpose.promotional, granted: true, occurredAt: DateTime(2026, 9, 1)),
      ConsentState(
          purpose: ConsentPurpose.whatsapp, granted: false, occurredAt: DateTime(2026, 9, 1)),
      ConsentState(
          purpose: ConsentPurpose.photos, granted: false, occurredAt: DateTime(2026, 9, 1)),
    ];
  }

  @override
  Future<ConsentRefusal?> setConsent(String purpose, bool granted) async {
    if (failWrites) throw const CrayApiException(CrayErrorKind.network);
    if (purpose == ConsentPurpose.service && !granted) {
      return ConsentRefusal.serviceRequired;
    }
    written.add((purpose, granted));
    return null;
  }

  @override
  Future<DataRightRequest?> requestRight(String kind, {String? detail}) async {
    if (failWrites) throw const CrayApiException(CrayErrorKind.network);
    requested.add(kind);
    final request = DataRightRequest(
      id: 'request-$kind',
      kind: kind,
      status: 'open',
      requestedAt: DateTime(2026, 9, 28),
      dueAt: DateTime(2026, 10, 28),
    );
    _requests.add(request);
    return request;
  }

  @override
  Future<List<DataRightRequest>> myRequests() async {
    if (failReads) throw const CrayApiException(CrayErrorKind.network);
    return List.of(_requests);
  }
}
