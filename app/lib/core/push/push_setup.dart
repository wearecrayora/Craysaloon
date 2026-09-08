import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push notifications (FCM).
///
/// Push is the primary channel and the only free one: every acknowledged push
/// is money the *salon owner* does not spend on WhatsApp or SMS
/// (ARCHITECTURE.md 12.2b). It works on both Android and iOS, though iOS
/// additionally needs an APNs key on the Firebase project before it delivers.
///
/// M0 scope is deliberately narrow: initialise Firebase and be able to read a
/// device token. The delivery-ack protocol, the escalation sweep and the
/// channel ladder are M8 (PHASES.md). Do not build them here.
///
/// Like Sentry, this is **never a boot dependency**. `google-services.json` is
/// gitignored - it holds an AIza... key and this repo is public - so a fresh
/// clone has no Firebase config at all. The app must still run.
class Push {
  Push._();

  static bool _available = false;

  /// True when Firebase initialised and push can be used.
  static bool get available => _available;

  /// Initialises Firebase if it is configured. Swallows failure by design:
  /// a missing or broken push setup must never stop the app from starting.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (error, stackTrace) {
      _available = false;
      // Not an error worth reporting: it is the expected state of any clone
      // without google-services.json.
      debugPrint('Push unavailable - Firebase not configured: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 3);
    }
  }

  /// The device's FCM registration token, or null when push is unavailable.
  ///
  /// At M8 this is stored in `notification_tokens` and refreshed on rotation;
  /// an `UNREGISTERED` response marks it dead immediately so the ladder
  /// escalates without waiting out a window (RULES.md 7.3.3).
  static Future<String?> token() async {
    if (!_available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('Could not read FCM token: $error');
      return null;
    }
  }

  /// Fires whenever FCM rotates the token. Wired to the server at M8.
  static Stream<String> get onTokenRefresh =>
      _available
          ? FirebaseMessaging.instance.onTokenRefresh
          : const Stream<String>.empty();
}
