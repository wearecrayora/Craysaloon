import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/notifications/push_api.dart';
import 'package:craysalon/features/notifications/push_registration.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device's half of the ack protocol (ARCHITECTURE 12.3).
///
/// This is a money test wearing plain clothes. Until the device says a message
/// arrived, the server is counting down a window, and at the end of it the
/// **salon** is billed for WhatsApp or SMS. Every assertion here is about not
/// spending someone else's money, or about not crashing in a handler that runs
/// while the customer is looking at something else.
void main() {
  late FakePushApi api;
  late PushRegistration push;

  setUp(() {
    api = FakePushApi();
    push = PushRegistration(api);
  });

  test('a delivered push is acknowledged with the id it carried', () async {
    await push.acknowledge({'delivery_id': 'delivery-1', 'purpose': 'booking_confirmed'});
    expect(api.acked, ['delivery-1']);
  });

  test('a message with no delivery id is ignored, not guessed at', () async {
    await push.acknowledge({'purpose': 'booking_confirmed'});
    await push.acknowledge({'delivery_id': ''});
    expect(api.acked, isEmpty);
  });

  test('a failed ack never escapes the handler', () async {
    api.fail = true;
    // A missed ack costs the salon one escalation. An exception thrown out of a
    // notification handler costs the customer the screen they were looking at.
    await expectLater(push.acknowledge({'delivery_id': 'delivery-2'}), completes);
  });

  test('the token is registered with the platform it came from', () async {
    await push.registerToken('fcm-token-1');
    expect(api.registered, hasLength(1));
    expect(api.registered.single.$1, 'fcm-token-1');
    expect(api.registered.single.$2, anyOf('android', 'ios'));
  });

  test('a failed registration is not fatal - the next start tries again', () async {
    api.fail = true;
    await expectLater(push.registerToken('fcm-token-2'), completes);
  });
}

class FakePushApi implements PushApi {
  bool fail = false;
  final acked = <String>[];
  final registered = <(String, String)>[];

  @override
  Future<void> ackNotification(String deliveryId) async {
    if (fail) throw const CrayApiException(CrayErrorKind.network);
    acked.add(deliveryId);
  }

  @override
  Future<void> registerPushToken({required String token, required String platform}) async {
    if (fail) throw const CrayApiException(CrayErrorKind.network);
    registered.add((token, platform));
  }
}
