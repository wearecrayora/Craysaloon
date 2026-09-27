import 'package:flutter/services.dart';

/// Adding the salon to the home screen.
///
/// **This is not a launcher-icon change, and no amount of code makes it one.**
/// Android compiles the launcher icon into the APK; the one stock alternative
/// (`activity-alias` swapping) needs every salon's icon inside the build. What
/// IS possible is a *pinned shortcut*: a home-screen icon carrying the salon's
/// logo and name, created at runtime (`ARCHITECTURE.md` 7.3).
///
/// **iOS has no equivalent at all.** Not a harder path - none. [isSupported]
/// returns false there and the offer is never shown. Do not add an iOS branch
/// that pretends otherwise (`RULES.md` 8.11, 15).
///
/// An interface, because RULES 15b forbids platform-specific code outside a
/// platform abstraction - and because the UI must be testable without a
/// launcher.
abstract interface class HomeShortcut {
  /// False on iOS, and on Android launchers that do not support pinning. The
  /// offer must be hidden, not shown-and-failed.
  Future<bool> isSupported();

  /// Offers to pin the shortcut. Android shows its own confirmation dialog, so
  /// this can never add anything silently - the UI must frame it as an offer,
  /// not a promise. Returns true only when the request was accepted.
  ///
  /// [logo] is PNG bytes the app already downloaded; when null, the shortcut
  /// uses the app icon rather than a placeholder of someone else's brand.
  Future<bool> offer({required String label, Uint8List? logo});
}

class MethodChannelHomeShortcut implements HomeShortcut {
  const MethodChannelHomeShortcut();

  static const _channel = MethodChannel('cray/home_shortcut');

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      // iOS, or a platform with no implementation: not an error, just no.
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> offer({required String label, Uint8List? logo}) async {
    try {
      final accepted = await _channel.invokeMethod<bool>('pin', {
        'label': label,
        'logo': logo,
      });
      return accepted ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
