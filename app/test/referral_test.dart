import 'package:craysalon/app/providers.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/join/join_code.dart';
import 'package:craysalon/domain/join/join_link.dart';
import 'package:craysalon/domain/referral/referral.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/referral/referral_screen.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

/// Refer & Earn (C11), and the link that carries a code.
///
/// The screen's job is to be honest about **when** the reward arrives. A
/// customer who shares a code and gets nothing has not hit a bug - the friend
/// has not been in and paid yet (RULES 10) - but they will report it as one
/// unless the screen said so first, before the code and not under it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeReferralApi api;

  setUp(() => api = FakeReferralApi());

  Future<void> pump(WidgetTester tester, {double textScale = 1.0}) async {
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
          referralApiProvider.overrideWithValue(api),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold));
    ProviderScope.containerOf(context).read(resolvedBrandingProvider.notifier).wear(
          CachedBranding(
            salonId: 'salon-a',
            displayName: 'Studio Nine Salon',
            version: 3,
            document: publishedBranding(displayName: 'Studio Nine Salon'),
          ),
        );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Refer & Earn'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refer & Earn').last);
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the condition is stated BEFORE the code, not under it', (tester) async {
    await pump(tester);

    final condition = tester.getBottomLeft(
      find.textContaining('finishes their first paid visit'),
    ).dy;
    final code = tester.getTopLeft(find.text('MNPQ23')).dy;

    expect(condition, lessThan(code),
        reason: 'a customer who shares and gets nothing will report a bug unless '
            'the screen told them the condition first');
  });

  testWidgets('both rewards come from the server, never computed here', (tester) async {
    await pump(tester);
    expect(find.text('Give ₹50, get ₹100'), findsOneWidget);
    expect(api.summaryReads, 1);
  });

  testWidgets('referral credit never appears without what it is worth saying about it',
      (tester) async {
    await pump(tester);
    await scrollTo(tester, find.textContaining('cannot be taken out as cash'));
    expect(
      find.text('Referral credit is usable only at Studio Nine Salon and cannot be '
          'taken out as cash.'),
      findsOneWidget,
    );
  });

  testWidgets('waiting friends and earned rewards are counted separately',
      (tester) async {
    await pump(tester);
    expect(find.text('2 friends have joined and not visited yet'), findsOneWidget);
    expect(find.text('1 friend has visited. You have earned ₹100.'), findsOneWidget);
  });

  testWidgets('each refusal says something different and true', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Apply code'));

    for (final (refusal, message) in [
      (ClaimRefusal.selfReferral, 'That is your own code.'),
      (ClaimRefusal.unknownCode, 'That code does not belong to this salon.'),
      (ClaimRefusal.alreadyReferred,
          "A friend's code has already been applied to your account."),
      (ClaimRefusal.notNewCustomer,
          'Referral codes are for a first visit, and you have already been in.'),
    ]) {
      api.refusal = refusal;
      await tester.enterText(find.byType(TextField).last, 'ABCD23');
      await scrollTo(tester, find.text('Apply code'));
      await tester.tap(find.text('Apply code'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: '$refusal');
    }
  });

  testWidgets('a successful claim says when the credit arrives', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Apply code'));
    await tester.enterText(find.byType(TextField).last, 'ABCD23');
    await scrollTo(tester, find.text('Apply code'));
    await tester.tap(find.text('Apply code'));
    await tester.pumpAndSettle();

    expect(api.claimed, ['ABCD23']);
    expect(
      find.text('Code applied. You both get credit after your first paid visit.'),
      findsOneWidget,
    );
  });

  testWidgets('nothing clips at 200% text scale', (tester) async {
    await pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });

  group('the link that carries a code', () {
    test('picks the referral out of a join link', () {
      expect(
        JoinLink.referralFrom('https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?r=MNPQ23'),
        'MNPQ23',
      );
      expect(
        JoinLink.referralFrom('https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?ref=mnpq23'),
        'MNPQ23',
      );
    });

    test('and refuses anything that is not one', () {
      // The salon still resolves; only the referral is dropped. A referral code
      // that fails to parse must never stop somebody joining.
      for (final link in [
        'https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S',
        'https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?r=SHORT',
        // O, I and L are not in the alphabet - they are the characters somebody
        // misreads a code as.
        'https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?r=MNPQ2O',
        'https://evil.example/s/CRAY-22335S?r=MNPQ23',
      ]) {
        expect(JoinLink.referralFrom(link), isNull, reason: link);
      }
    });

    test('and builds the link a customer shares', () {
      expect(
        JoinLink.shareLink(JoinCode.tryParse('CRAY-22335S')!, 'MNPQ23'),
        'https://craysalon-join.crayoratech.workers.dev/s/CRAY-22335S?r=MNPQ23',
      );
    });
  });
}

class FakeReferralApi implements ReferralApi {
  ClaimRefusal? refusal;
  int summaryReads = 0;
  final claimed = <String>[];

  @override
  Future<ReferralSummary> referralSummary() async {
    summaryReads++;
    return const ReferralSummary(
      code: 'MNPQ23',
      referrerPaise: 10000,
      referredPaise: 5000,
      pending: 2,
      rewarded: 1,
      earnedPaise: 10000,
    );
  }

  @override
  Future<ClaimRefusal?> claimReferral(String code) async {
    claimed.add(code);
    return refusal;
  }
}
