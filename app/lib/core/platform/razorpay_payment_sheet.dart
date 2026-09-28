import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../domain/wallet/wallet.dart';
import 'payment_sheet.dart';

/// Razorpay Checkout, opened against **the salon's own account**.
///
/// `order.keyId` is that salon's public key, fetched at the moment of use from
/// the one function allowed to read a credential. The secret never reaches the
/// device, and there is no Crayora account to fall back on - by design
/// (RULES 8, ARCHITECTURE 13.1).
///
/// **What this class may and may not conclude.** Razorpay's success callback
/// means the customer finished the sheet. It does not mean the money arrived,
/// and this app is not allowed to decide that it did: the credit is posted by
/// the webhook, after the signature is verified with that salon's own secret and
/// the amount is re-checked against the payment row we created. So a success
/// callback returns [PaymentOutcome.submitted] - never "paid" - and the
/// `payment_id` and `signature` it carries are deliberately **dropped**. A
/// client-reported payment id is a claim, and treating a claim as evidence is
/// how a wallet gets credited for a payment nobody made.
class RazorpayPaymentSheet implements PaymentSheet {
  RazorpayPaymentSheet();

  @override
  bool get isAvailable => true;

  @override
  Future<PaymentOutcome> open(TopupOrder order, {required String salonName}) async {
    if (order.keyId.isEmpty || order.orderId.isEmpty) {
      // The server could not produce an order for this salon. Nothing to open.
      return PaymentOutcome.unavailable;
    }

    final razorpay = Razorpay();
    final done = Completer<PaymentOutcome>();

    void finish(PaymentOutcome outcome) {
      if (!done.isCompleted) done.complete(outcome);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (_) => finish(PaymentOutcome.submitted));
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      // Razorpay reports a cancelled sheet as an error with its own code. To a
      // customer those are different events - "nothing was charged" either way,
      // but only one of them is worth an apology.
      finish(response.code == Razorpay.PAYMENT_CANCELLED
          ? PaymentOutcome.cancelled
          : PaymentOutcome.failed);
    });
    // Paid through a wallet app rather than in the sheet. Still just submitted.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish(PaymentOutcome.submitted));

    try {
      razorpay.open({
        'key': order.keyId,
        'order_id': order.orderId,
        // Paise, exactly as the server stored them. Razorpay re-checks this
        // against the order, so a mismatch here fails loudly rather than
        // charging the wrong amount.
        'amount': order.amountPaise,
        'currency': 'INR',
        // The salon's name, because this is the salon's app and the salon's
        // account. Nothing here says Crayora.
        'name': salonName,
        'retry': {'enabled': false},
      });
    } catch (_) {
      razorpay.clear();
      return PaymentOutcome.failed;
    }

    final outcome = await done.future;
    razorpay.clear();
    return outcome;
  }
}
