import 'package:craysalon/app/providers.dart';
import 'package:craysalon/core/platform/payment_sheet.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/visit/visit.dart';
import 'package:craysalon/domain/wallet/wallet.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/salon/salon_home.dart';
import 'package:craysalon/features/visit/visit_cards.dart';
import 'package:craysalon/features/wallet/add_money_screen.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'salon_home_test.dart' show FakeNotifications, FakeShortcut;
import 'support/fake_cray_api.dart';
import 'wallet_test.dart' show FakeSheet, FakeWalletApi;

/// The customer's side of a visit (requested 29 Sep 2026): the code that starts
/// it, and the bill that ends it.
///
/// The gates here, rather than checks:
///   * **the app never decides a bill is paid.** The wallet is spent by the
///     server, UPI settles on Razorpay's webhook, cash when STAFF take it
///   * **"at the counter" settles nothing** - it only tells the counter
///   * **a retried tap reuses the same action id**, so it spends once
///   * **every amount is the server's** - the app sends a visit id, never a sum
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeVisitApi visits;
  late FakeWalletApi wallet;
  late FakeSheet sheet;

  setUp(() {
    visits = FakeVisitApi();
    wallet = FakeWalletApi(); // ₹1,250 balance
    sheet = FakeSheet();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crayApiProvider.overrideWithValue(FakeCrayApi()),
          sessionProvider.overrideWithValue(
            const AppSession(appRole: 'customer', salonId: 'salon-a'),
          ),
          initialBrandingProvider.overrideWithValue(CachedBranding(
            salonId: 'salon-a',
            displayName: 'Studio Nine Salon',
            version: 3,
            document: publishedBranding(),
          )),
          homeShortcutProvider.overrideWithValue(FakeShortcut(supported: false)),
          salonNotificationsProvider.overrideWithValue(FakeNotifications()),
          visitApiProvider.overrideWithValue(visits),
          walletApiProvider.overrideWithValue(wallet),
          paymentSheetProvider.overrideWithValue(sheet),
        ],
        child: const CraySalonApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBill(WidgetTester tester) async {
    await tester.tap(find.text('Pay your bill'));
    await tester.pumpAndSettle();
  }

  group('the start code', () {
    testWidgets("today's booking shows the code to read to the stylist", (tester) async {
      final semantics = tester.ensureSemantics();
      visits.today = [visits.visit(code: '4821')];
      await pump(tester);

      expect(find.text('Your visit today'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      // The card reads as one node, so match within its label.
      expect(find.bySemanticsLabel(RegExp('Your start code: 4 8 2 1')), findsOneWidget,
          reason: 'a screen reader reads four digits, not "four thousand..."');
      expect(find.bySemanticsLabel(RegExp('4821')), findsNothing,
          reason: 'and never the number as well');
      semantics.dispose();
    });

    testWidgets('once started, the code is gone', (tester) async {
      visits.today = [visits.visit(status: 'in_progress')];
      await pump(tester);

      expect(find.text('Your service is in progress.'), findsOneWidget);
      expect(find.text('4821'), findsNothing);
    });

    testWidgets('no booking today, no card', (tester) async {
      await pump(tester);
      expect(find.text('Your visit today'), findsNothing);
    });
  });

  group('the bill', () {
    testWidgets('a completed visit shows the bill, with what is left to pay', (tester) async {
      visits.billList = [visits.bill(due: 45000)];
      await pump(tester);

      expect(find.text('Your bill is ready'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
    });

    testWidgets('the wallet pays it when it can, and the server says how much', (tester) async {
      visits.billList = [visits.bill(due: 45000)];
      await pump(tester);
      await openBill(tester);

      await tester.tap(find.text('Pay ₹450 from your wallet'));
      await tester.pumpAndSettle();

      expect(visits.walletCalls, ['visit-1']);
      expect(find.text('Your bill is ready'), findsNothing,
          reason: 'the server settled it, so the next read has no bill');
    });

    testWidgets('a wallet that covers part says what is left, and how to pay it', (tester) async {
      visits.billList = [visits.bill(due: 200000)];
      await pump(tester);
      await openBill(tester);

      expect(find.text('Pay ₹1,250 from your wallet'), findsOneWidget);
      expect(find.textContaining('The other ₹750'), findsOneWidget);

      await tester.tap(find.text('Pay ₹1,250 from your wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Paid from your wallet. ₹750 left to pay - by UPI or at the counter.'),
          findsOneWidget);
      expect(find.text('Pay ₹750 by UPI'), findsOneWidget);
    });

    testWidgets('UPI never reads as paid - the webhook decides', (tester) async {
      visits.billList = [visits.bill(due: 45000)];
      sheet.outcome = PaymentOutcome.submitted;
      await pump(tester);
      await openBill(tester);

      await tester.tap(find.text('Pay ₹450 by UPI'));
      await tester.pumpAndSettle();

      expect(sheet.opened.single.amountPaise, 45000,
          reason: "the order carries the server's amount");
      expect(find.text('Payment sent. Your bill will show as paid once the bank confirms it.'),
          findsOneWidget);
    });

    testWidgets('"at the counter" tells the counter, and settles NOTHING', (tester) async {
      visits.billList = [visits.bill(due: 45000)];
      await pump(tester);
      await openBill(tester);

      await tester.tap(find.text('I will pay at the counter'));
      await tester.pumpAndSettle();

      expect(visits.counterCalls, ['visit-1']);
      expect(find.text('The counter knows. Your bill shows as paid once they take the money.'),
          findsOneWidget);
      expect(visits.billList, isNotEmpty, reason: 'staff confirm cash, never the customer');
    });

    testWidgets('a retried wallet tap reuses the SAME action id', (tester) async {
      visits.billList = [visits.bill(due: 45000)];
      visits.failWallet = 1;
      await pump(tester);
      await openBill(tester);

      await tester.tap(find.text('Pay ₹450 from your wallet'));
      await tester.pumpAndSettle();
      expect(find.text('No connection. Check your internet and try again.'), findsOneWidget);

      await tester.tap(find.text('Pay ₹450 from your wallet'));
      await tester.pumpAndSettle();

      expect(visits.walletActionIds, hasLength(2));
      expect(visits.walletActionIds.toSet(), hasLength(1),
          reason: 'a retry must reach the same debit, not spend twice');
    });
  });
}

class FakeVisitApi implements VisitApi {
  List<TodayVisit> today = const [];
  List<Bill> billList = const [];

  final walletCalls = <String>[];
  final walletActionIds = <String>[];
  final counterCalls = <String>[];
  int failWallet = 0;

  /// What the server would spend: the wallet as far as it goes.
  int balancePaise = 125000;

  TodayVisit visit({String status = 'confirmed', String? code = '4821'}) => TodayVisit(
        bookingId: 'booking-1',
        startsAt: DateTime.now().add(const Duration(hours: 1)),
        status: status,
        services: 'Haircut',
        startCode: status == 'in_progress' ? null : code,
      );

  Bill bill({required int due}) => Bill(
        visitId: 'visit-1',
        completedAt: DateTime.now(),
        totalPaise: due,
        duePaise: due,
        services: 'Haircut',
      );

  @override
  Future<List<TodayVisit>> visitsToday() async => today;

  @override
  Future<List<Bill>> bills() async => billList;

  @override
  Future<int> payBillFromWallet({required String clientActionId, required String visitId}) async {
    walletActionIds.add(clientActionId);
    if (failWallet > 0) {
      failWallet--;
      throw const CrayApiException(CrayErrorKind.network);
    }
    walletCalls.add(visitId);
    final due = billList.single.duePaise;
    final spent = balancePaise < due ? balancePaise : due;
    balancePaise -= spent;
    final left = due - spent;
    billList = left == 0
        ? const []
        : [
            Bill(
              visitId: visitId,
              completedAt: billList.single.completedAt,
              totalPaise: billList.single.totalPaise,
              duePaise: left,
            ),
          ];
    return left;
  }

  @override
  Future<TopupOrder> startBillPayment({
    required String clientActionId,
    required String visitId,
  }) async {
    return TopupOrder(
      paymentId: 'payment-1',
      orderId: 'order_bill',
      keyId: 'rzp_test_salon',
      amountPaise: billList.single.duePaise,
    );
  }

  @override
  Future<void> requestCounterPayment(String visitId) async => counterCalls.add(visitId);
}
