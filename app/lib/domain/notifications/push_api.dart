/// The app's half of the ack protocol.
///
/// Push is the only free channel, and every push that is acknowledged is money
/// the **salon owner** does not spend on WhatsApp or SMS (ARCHITECTURE 12.4).
/// FCM tells the server "accepted by Google", which is not delivery — so the
/// device is the only thing that can say a message actually arrived, and this
/// is how it says so.
library;

abstract interface class PushApi {
  /// Stores this device's FCM token against the signed-in customer. Called on
  /// every start and on every rotation: a token that has moved and not been
  /// re-registered is a customer whose messages all escalate to paid channels.
  Future<void> registerPushToken({required String token, required String platform});

  /// Acknowledges a delivery. Idempotent, and safe to call for a message that
  /// arrived twice — the server records the first ack and ignores the rest.
  Future<void> ackNotification(String deliveryId);
}
