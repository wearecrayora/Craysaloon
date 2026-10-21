import 'package:flutter/services.dart';

/// Filling in the one-time code from the SMS, with the customer's say-so.
///
/// **Android:** Google's SMS User Consent API. When the code's SMS arrives,
/// Android shows its own prompt - "Allow this app to read the message below?"
/// - with the message on it. Allow, and the code is filled in; Deny, and it is
/// typed. No READ_SMS permission (Play allows that only to SMS apps), and
/// nothing is read without that one tap (SmsConsentChannel.kt).
///
/// **iOS:** no API reads an SMS at all. The keyboard offers the code itself
/// ("From Messages") on a field marked as a one-time code, which the OTP field
/// is - so [listen] answers null there and nothing more is needed.
///
/// An interface, because RULES 15b keeps platform code behind one - and because
/// the screen must be testable without a phone.
abstract interface class OtpAutofill {
  /// Waits for the next SMS, asks the customer, and returns the CODE from it -
  /// or null: declined, timed out (five minutes), unsupported, or no code in it.
  Future<String?> listen();

  /// Stops waiting - the code was typed, or the screen was left.
  Future<void> cancel();
}

class MethodChannelOtpAutofill implements OtpAutofill {
  const MethodChannelOtpAutofill();

  static const _channel = MethodChannel('cray/sms_consent');

  @override
  Future<String?> listen() async {
    try {
      final message = await _channel.invokeMethod<String>('listen');
      return message == null ? null : codeIn(message);
    } on MissingPluginException {
      // iOS, or no implementation: the keyboard's own autofill covers it.
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Nothing was listening.
    } on PlatformException {
      // Nothing to stop.
    }
  }
}

/// The code in an SMS the customer chose to share: the first run of exactly
/// [length] digits standing on its own.
///
/// The message's wording is Message Central's, not ours (RULES 16), so this
/// reads only the number and assumes nothing else about the text. The server
/// still verifies whatever is filled in - this only saves typing.
String? codeIn(String message, {int length = 6}) {
  final match = RegExp('(?<![0-9])[0-9]{$length}(?![0-9])').firstMatch(message);
  return match?.group(0);
}
