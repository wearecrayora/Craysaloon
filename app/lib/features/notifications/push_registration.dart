import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_setup.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/notifications/push_api.dart';
import '../join/join_controller.dart';

final pushApiProvider = Provider<PushApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is PushApi ? api as PushApi : null;
});

/// Registering this device, and acknowledging what arrives on it.
///
/// Both halves of ARCHITECTURE 12.3, from the app's side:
///
///   * **the token** is stored on every start and every rotation. A token that
///     has moved and not been re-registered is a customer whose every message
///     escalates to a channel the salon pays for.
///   * **the ack** is sent the moment a push lands. Until it arrives, the
///     server's sweep is counting down a window, and at the end of it the salon
///     is billed for WhatsApp or SMS. Acking is not bookkeeping; it is the
///     thing that keeps push free.
///
/// Failures here are swallowed deliberately. A missed ack costs the salon one
/// escalation; an exception thrown out of a notification handler costs the
/// customer the screen they were looking at.
class PushRegistration {
  PushRegistration(this._api);

  final PushApi _api;

  /// Kept so the subscriptions can be cancelled when the session ends.
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Future<void> start() async {
    if (!Push.available) return;

    final token = await Push.token();
    if (token != null) await _register(token);

    _subscriptions.add(Push.onTokenRefresh.listen(_register));

    // Foreground. The customer is looking at the app, so the message has
    // unambiguously arrived.
    _subscriptions.add(FirebaseMessaging.onMessage.listen(_ack));

    // Opened from the tray. It arrived earlier; the ack is late but still
    // cheaper than an escalation that has not fired yet.
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(_ack));
  }

  /// Public so it can be tested without Firebase: the interesting behaviour is
  /// what gets sent and what happens when it fails, neither of which needs a
  /// real FCM stream to exercise.
  Future<void> registerToken(String token) => _register(token);

  /// The ack, given a message's data payload. Called by the stream handlers.
  Future<void> acknowledge(Map<String, dynamic> data) async {
    final deliveryId = data['delivery_id'] as String?;
    if (deliveryId == null || deliveryId.isEmpty) return;
    try {
      await _api.ackNotification(deliveryId);
    } on CrayApiException catch (e) {
      // A missed ack costs the salon one escalation. An exception thrown out of
      // a notification handler costs the customer the screen they were on.
      debugPrint('Could not acknowledge a delivery: ${e.kind.name}');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _api.registerPushToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } on CrayApiException catch (e) {
      // Not fatal, and not worth a screen: the next start tries again.
      debugPrint('Could not register push token: ${e.kind.name}');
    }
  }

  Future<void> _ack(RemoteMessage message) => acknowledge(message.data);

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
