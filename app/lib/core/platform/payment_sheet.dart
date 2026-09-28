import '../../domain/wallet/wallet.dart';

/// Handing off to Razorpay's checkout.
///
/// An interface for the usual two reasons — RULES 15b keeps platform code
/// behind an abstraction, and a pay button has to be testable without a payment
/// gateway — and for a third that matters more here:
///
/// **Nothing in this app may decide that a payment succeeded.** The sheet
/// reports what the customer did; the *money* only moves when Razorpay's
/// webhook reaches the server, is verified against that salon's own secret and
/// re-checked against the payment row (ARCHITECTURE 8.3). So the best outcome
/// this interface can report is [PaymentOutcome.submitted] — never "paid". A
/// client that could return "paid" would be a client worth lying to.
abstract interface class PaymentSheet {
  /// False until the real Razorpay SDK is wired in. The Add Money screen must
  /// then say so plainly rather than offering a button that does nothing.
  bool get isAvailable;

  Future<PaymentOutcome> open(TopupOrder order, {required String salonName});
}

enum PaymentOutcome {
  /// The customer completed the sheet. The credit follows the webhook, so the
  /// app shows "waiting for confirmation" - which is the truth.
  submitted,

  cancelled,

  /// The sheet itself failed: no network, a rejected card, a bad key.
  failed,

  /// No checkout is wired into this build.
  unavailable,
}

/// The no-op, kept for the case the real sheet cannot run.
///
/// The shipping implementation is `RazorpayPaymentSheet`. This one exists so a
/// build without the SDK - or a platform where it is unavailable - still has a
/// PaymentSheet that says plainly that the last step is not switched on, rather
/// than offering a button that does nothing.
///
/// **Deliberately not a simulation that reports success.** A fake pay button
/// that reports "paid" would be one merge away from shipping, and the failure
/// it produces is a customer who believes they have credit they do not have.
class UnavailablePaymentSheet implements PaymentSheet {
  const UnavailablePaymentSheet();

  @override
  bool get isAvailable => false;

  @override
  Future<PaymentOutcome> open(TopupOrder order, {required String salonName}) async =>
      PaymentOutcome.unavailable;
}
