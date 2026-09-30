import 'package:craysalon/app/providers.dart';
import 'package:craysalon/core/platform/payment_sheet.dart';
import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/wallet/wallet.dart';
import 'package:craysalon/features/join/join_controller.dart';
import 'package:craysalon/features/wallet/add_money_screen.dart';
import 'package:craysalon/features/wallet/wallet_controller.dart';
import 'package:craysalon/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cray_api.dart';

/// The wallet and Add Money (C2, C3).
///
/// Three of these are gates rather than checks, and all three cost real money
/// or a real complaint when they break:
///
///   * **a balance is never shown alone** - it always carries "usable only
///     here, cannot be taken out as cash" (DESIGN 6.1)
///   * **the disclosure block is ABOVE the pay button**, at body size, not
///     collapsed, not behind a link (RULES 5.3.6, DESIGN 6.2). It ships with M7
///     because it is a legal requirement, not polish
///   * **nothing in the app decides a payment succeeded.** The best the screen
///     may say is "sent" - the credit follows Razorpay's webhook
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeWalletApi wallet;
  late FakeSheet sheet;

  setUp(() {
    wallet = FakeWalletApi();
    sheet = FakeSheet();
  });

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
          walletApiProvider.overrideWithValue(wallet),
          paymentSheetProvider.overrideWithValue(sheet),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CraySalonApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(context).read(resolvedBrandingProvider.notifier).wear(
          CachedBranding(
            salonId: 'salon-a',
            displayName: 'Studio Nine Salon',
            version: 3,
            document: publishedBranding(displayName: 'Studio Nine Salon'),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
  }

  Future<void> openAddMoney(WidgetTester tester) async {
    // At 200% text scale the button is below the fold, which is fine - it is
    // reachable, and nothing is clipped. The test scrolls like a thumb.
    await tester.scrollUntilVisible(find.text('Add money'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add money'));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('a balance is NEVER shown alone', (tester) async {
    await pump(tester);

    expect(find.text('₹1,250'), findsOneWidget);
    // The two sentences that must travel with every balance in this product.
    expect(
      find.text('Usable only at Studio Nine Salon. Cannot be withdrawn as cash.'),
      findsOneWidget,
    );
  });

  testWidgets('paid and bonus are shown separately, and paid never expires',
      (tester) async {
    await pump(tester);

    expect(find.text('Paid credit'), findsOneWidget);
    expect(find.text('₹1,000'), findsOneWidget);
    expect(find.text('Bonus credit'), findsOneWidget);
    expect(find.text('₹250'), findsOneWidget);
    expect(find.text('Money you pay never expires.'), findsOneWidget);
    // A bonus total with no date is a number nobody can act on.
    expect(find.textContaining('of bonus expires on'), findsOneWidget);
  });

  testWidgets('the history shows the ledger''s own signs', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Used at the salon'));

    expect(find.text('+₹1,000'), findsOneWidget);
    expect(find.text('-₹300'), findsOneWidget,
        reason: 'a debit that reads as positive is a statement nobody can check');
  });

  testWidgets('money is never read from the cache - offline says so', (tester) async {
    wallet.failReads = true;
    await pump(tester);

    expect(find.text('₹1,250'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the disclosure block is ABOVE the pay button', (tester) async {
    await pump(tester);
    await openAddMoney(tester);

    // Every required line, at body size, on screen, not behind a tap.
    expect(find.text('You get ₹100 extra.'), findsOneWidget);
    expect(find.textContaining('bonus expires on'), findsOneWidget);
    expect(find.text('Money you pay never expires.'), findsOneWidget);
    expect(find.text('Usable only at Studio Nine Salon. Cannot be withdrawn as cash.'),
        findsOneWidget);
    expect(find.text('A top-up cannot be refunded or taken out as cash.'), findsOneWidget);

    final disclosureBottom = tester.getBottomLeft(find.text('Before you pay')).dy;
    final buttonTop = tester.getTopLeft(find.textContaining('Pay ₹')).dy;
    expect(disclosureBottom, lessThan(buttonTop),
        reason: 'RULES 5.3.6: above the pay button, not beside it and not after it');
  });

  testWidgets('the bonus shown is the SERVER''s, re-quoted when the amount changes',
      (tester) async {
    await pump(tester);
    await openAddMoney(tester);

    expect(wallet.quoted, [100000]);

    await tester.tap(find.text('₹2,000'));
    await tester.pumpAndSettle();

    // Not recomputed locally: an app that works out its own bonus can promise
    // one the ledger will refuse.
    expect(wallet.quoted, [100000, 200000]);
    expect(find.text('You get ₹200 extra.'), findsOneWidget);
  });

  testWidgets('an amount with no bonus says so rather than staying silent',
      (tester) async {
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.text('₹500'));
    await tester.pumpAndSettle();

    expect(find.text('No bonus on this amount.'), findsOneWidget);
    expect(find.textContaining('You get'), findsNothing);
  });

  testWidgets('the pay button cannot be pressed before the disclosure exists',
      (tester) async {
    wallet.holdQuote = true;
    await pump(tester);
    // pumpAndSettle would time out: an indeterminate progress bar never settles,
    // which is exactly the state being asserted.
    await tester.tap(find.text('Add money'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNull,
        reason: 'a pay button live before the quote is a payment made without the notice');
  });

  testWidgets('the app never claims a payment succeeded', (tester) async {
    sheet.outcome = PaymentOutcome.submitted;
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    // "Sent", not "paid". The credit follows the webhook, verified against the
    // salon's own secret - never this screen's opinion.
    expect(find.text('Payment sent. Your credit appears as soon as the bank confirms it.'),
        findsOneWidget);
    expect(find.textContaining('Paid'), findsNothing);
  });

  testWidgets('a checkout that is not wired says the money has not moved',
      (tester) async {
    sheet.outcome = PaymentOutcome.unavailable;
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    expect(
      find.text('Paying from the app is not switched on in this version yet. '
          'Your money has not moved.'),
      findsOneWidget,
    );
  });

  testWidgets('a retried tap reuses the SAME action id; a new amount does not',
      (tester) async {
    sheet.outcome = PaymentOutcome.failed;
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    expect(wallet.actionIds.toSet(), hasLength(1),
        reason: 'a retry must reach the same payment, not a second way to pay');

    await tester.tap(find.text('₹2,000'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    expect(wallet.actionIds.toSet(), hasLength(2),
        reason: 'a different amount is a different intent');
  });

  testWidgets('a salon that cannot take payments says so plainly', (tester) async {
    wallet.startProblem = TopupProblem.paymentsUnavailable;
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    // There is no Crayora account to fall back on - by design (RULES 8).
    expect(find.text('This salon cannot take payments yet. Ask at the counter.'),
        findsOneWidget);
  });

  testWidgets('below the salon''s minimum, the screen says what the minimum is',
      (tester) async {
    wallet.startProblem = TopupProblem.belowMinimum;
    await pump(tester);
    await openAddMoney(tester);

    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();

    expect(find.text('The smallest top-up here is ₹100.'), findsOneWidget);
  });

  testWidgets('nothing clips at 200% text scale', (tester) async {
    await pump(tester, textScale: 2.0);
    await openAddMoney(tester);
    expect(tester.takeException(), isNull);
  });
}

class FakeSheet implements PaymentSheet {
  PaymentOutcome outcome = PaymentOutcome.unavailable;
  final opened = <TopupOrder>[];

  @override
  bool get isAvailable => outcome != PaymentOutcome.unavailable;

  @override
  Future<PaymentOutcome> open(TopupOrder order, {required String salonName}) async {
    opened.add(order);
    return outcome;
  }
}

class FakeWalletApi implements WalletApi {
  bool failReads = false;
  bool holdQuote = false;
  TopupProblem? startProblem;

  final quoted = <int>[];
  final actionIds = <String>[];

  @override
  Future<WalletSummary> wallet() async {
    if (failReads) throw const CrayApiException(CrayErrorKind.network);
    return WalletSummary(
      balancePaise: 125000,
      paidPaise: 100000,
      bonusPaise: 25000,
      nextBonusExpiry: DateTime(2026, 11, 14),
      nextBonusPaise: 25000,
    );
  }

  @override
  Future<List<WalletEntry>> walletHistory({int limit = 20, int? before}) async {
    if (failReads) throw const CrayApiException(CrayErrorKind.network);
    return [
      WalletEntry(
        id: 2,
        kind: 'debit_spend',
        amountPaise: -30000,
        balanceAfter: 125000,
        createdAt: DateTime(2026, 9, 20),
      ),
      WalletEntry(
        id: 1,
        kind: 'credit_topup',
        amountPaise: 100000,
        balanceAfter: 155000,
        createdAt: DateTime(2026, 9, 1),
      ),
    ];
  }

  @override
  Future<TopupQuote> topupQuote(int amountPaise) async {
    quoted.add(amountPaise);
    if (holdQuote) return Future.any([]);
    // 10% over ₹1,000, which is the salon's own rule - mirrored here only so
    // the fake behaves like the server it stands in for.
    final bonus = amountPaise >= 100000 ? amountPaise ~/ 10 : 0;
    return TopupQuote(
      amountPaise: amountPaise,
      bonusPaise: bonus,
      minTopupPaise: 10000,
      bonusExpiresAt: bonus > 0 ? DateTime(2026, 10, 28) : null,
    );
  }

  @override
  Future<TopupOrder> startTopup({
    required String clientActionId,
    required int amountPaise,
  }) async {
    actionIds.add(clientActionId);
    if (startProblem != null) {
      throw TopupException(startProblem!, minTopupPaise: 10000);
    }
    return TopupOrder(
      paymentId: 'payment-1',
      orderId: 'order_test',
      keyId: 'rzp_test_salon',
      amountPaise: amountPaise,
    );
  }
}
