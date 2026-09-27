import 'join_code.dart';

/// The printed QR, and the link it encodes.
///
/// Every QR in the salon's pack encodes `https://join.craysalon.in/s/<code>`
/// (`ARCHITECTURE.md` 5.6). The same string arrives two ways - scanned by the
/// camera, or handed to the app as a deep link when the QR is opened by the
/// phone's own scanner - so both go through here.
class JoinLink {
  /// Hosts whose `/s/<code>` links we treat as ours.
  ///
  /// A code from a QR is not a secret and not a credential: it names a salon,
  /// and the server resolves it from scratch either way, so a code from an
  /// unknown host is no more dangerous than one typed by hand. The check is
  /// here for clarity of intent - a scan of some unrelated URL should read as
  /// "that is not a salon code", not send someone into the join flow.
  static const hosts = {'join.craysalon.in', 'craysalon.in', 'www.craysalon.in'};

  /// Pulls the salon code out of anything a scanner or the OS might hand us:
  /// the printed link, the same link with tracking parameters, a `?code=`
  /// query, or the bare code on a sticker someone re-printed by hand.
  static JoinCode? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Not a URL at all: treat it as a typed code.
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return JoinCode.tryParse(text);

    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!hosts.contains(uri.host.toLowerCase())) return null;

    // /s/<code>, tolerating a trailing slash or extra segments.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments.first == 's') {
      final code = JoinCode.tryParse(segments[1]);
      if (code != null) return code;
    }

    // ?code=<code>, which is how the Play Install Referrer carries it through
    // an install.
    final fromQuery = uri.queryParameters['code'];
    if (fromQuery != null) return JoinCode.tryParse(fromQuery);

    return null;
  }

  /// The canonical link for a code - what the console prints on the QR.
  static String forCode(JoinCode code) => 'https://join.craysalon.in/s/${code.value}';
}
