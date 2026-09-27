import 'package:flutter/services.dart';

/// The salon's notification channel.
///
/// `ARCHITECTURE.md` 7.4: one channel per salon, **named for the salon**, created
/// after binding. That name is what Android shows in Settings → Notifications,
/// so a customer sees their salon there rather than "Cray Salon".
///
/// What cannot be branded, and must not be attempted: the small status-bar icon.
/// Android renders it as a silhouette from a compiled drawable, so a downloaded
/// colour logo would appear as a white blob. The large icon and the title are
/// dynamic; the glyph stays generic.
///
/// iOS has no channel concept - there is nothing to create, and [ensureChannel]
/// is a no-op there rather than a branch that pretends otherwise.
abstract interface class SalonNotifications {
  Future<void> ensureChannel({required String salonName, int? accentArgb});
}

class MethodChannelSalonNotifications implements SalonNotifications {
  const MethodChannelSalonNotifications();

  static const _channel = MethodChannel('cray/notifications');

  @override
  Future<void> ensureChannel({required String salonName, int? accentArgb}) async {
    try {
      await _channel.invokeMethod<void>('ensureChannel', {
        'name': salonName,
        'accent': accentArgb,
      });
    } on MissingPluginException {
      // iOS, or a platform without an implementation. Nothing to do.
    } on PlatformException {
      // A channel we could not create is not a reason to fail the screen; the
      // notification ladder falls back to the default channel.
    }
  }
}
