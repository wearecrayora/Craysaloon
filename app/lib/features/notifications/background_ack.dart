import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/remote/supabase_cray_api.dart';

/// Acknowledging a push that arrived while the app was not running.
///
/// This is the half of ARCHITECTURE 12.3 that actually matters. Most pushes
/// arrive when nobody is looking at the app — a reminder at 11am, a booking
/// confirmation while the phone is in a pocket. Without an ack from the
/// background isolate, every one of those waits out its window and escalates to
/// a channel **the salon pays for**, and the whole push-first design saves
/// nothing.
///
/// Android runs this handler in a **separate isolate** with none of the app's
/// state: no Riverpod, no providers, no initialised Supabase. So it initialises
/// what it needs, does one thing, and stops. Everything is wrapped, because an
/// exception thrown here is thrown inside the OS's notification delivery path.
///
/// It must be a **top-level function** — Flutter needs a static entry point to
/// call into the isolate — which is why it does not live on a class.
@pragma('vm:entry-point')
Future<void> ackInBackground(RemoteMessage message) async {
  final deliveryId = message.data['delivery_id'] as String?;
  if (deliveryId == null || deliveryId.isEmpty) return;

  try {
    await Firebase.initializeApp();

    // Supabase persists the session, so the isolate can restore it rather than
    // being handed one. A customer who is signed out has nothing to ack, and
    // the call below simply finds no delivery of theirs.
    await Supabase.initialize(
      url: backgroundSupabaseUrl,
      publishableKey: backgroundSupabaseKey,
    );

    await SupabaseCrayApi(Supabase.instance.client).ackNotification(deliveryId);
  } catch (error) {
    // Never rethrow. A missed ack costs the salon one escalation; an exception
    // out of this handler is a crash inside the OS's delivery path, and it is
    // invisible to everyone until a user reports the app "not working".
    debugPrint('Background ack failed: $error');
  }
}

/// The same `--dart-define` values `main.dart` uses. Declared again here because
/// a background isolate does not inherit them from the app's `main`.
const backgroundSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const backgroundSupabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Registers the handler. Safe to call when push is unconfigured: it is a no-op
/// rather than a boot failure, exactly like the rest of the push setup.
void registerBackgroundAck() {
  if (backgroundSupabaseUrl.isEmpty || backgroundSupabaseKey.isEmpty) return;
  try {
    FirebaseMessaging.onBackgroundMessage(ackInBackground);
  } catch (error) {
    debugPrint('Could not register the background ack handler: $error');
  }
}
