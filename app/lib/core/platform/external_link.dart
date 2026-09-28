import 'package:url_launcher/url_launcher.dart';

/// Leaving the app on purpose: the privacy policy, and the salon's own privacy
/// contact.
///
/// An interface for two reasons. RULES 15b forbids platform-specific code
/// outside a platform abstraction - `mailto:` and `tel:` behave differently on
/// Android and iOS and neither exists in a widget test. And a screen that is
/// legally required to be *reachable* must be testable: the notice asserts that
/// tapping the contact actually tries to open it, which needs a fake.
abstract interface class ExternalLink {
  /// Returns false when nothing on the device can open it - no mail app, no
  /// dialler. The caller must then leave the address on screen rather than
  /// swallow the tap: the address is the point, the tap is a convenience.
  Future<bool> open(Uri url);
}

class UrlLauncherExternalLink implements ExternalLink {
  const UrlLauncherExternalLink();

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// The published policy. One URL, in one place: it is printed on the Play
/// listing and linked from the join site, and three copies would drift.
final Uri privacyPolicyUrl = Uri.parse('https://join.craysalon.in/privacy');
