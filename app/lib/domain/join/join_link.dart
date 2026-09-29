import 'join_code.dart';

/// The printed QR, and the link it encodes.
///
/// Every QR in the salon's pack encodes `<origin>/s/<code>` ([origin])
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
  static const hosts = {host};

  /// Where the join site lives - Cloudflare's own address for the Worker.
  ///
  /// There is no custom domain (30 Sep 2026: none is being bought). The
  /// workers.dev address is permanent for as long as the Worker exists, and
  /// every printed QR encodes it, so a domain attached later must be ADDED to
  /// [hosts], never swapped in: the cards already on salon counters keep this
  /// one.
  static const host = 'craysalon-join.crayoratech.workers.dev';
  static const origin = 'https://$host';

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
  static String forCode(JoinCode code) => '$origin/s/${code.value}';

  /// A referral code riding along on the same link: `/s/<salon>?r=ABCDEF`.
  ///
  /// It is a SEPARATE thing from the salon code and is parsed separately, on
  /// purpose. A referral code that fails to parse must never stop somebody
  /// joining a salon - the salon is the point, the referral is a bonus - so
  /// this returns null and the join flow carries on.
  static String? referralFrom(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return null;
    if (!hosts.contains(uri.host.toLowerCase())) return null;

    final value = uri.queryParameters['r'] ?? uri.queryParameters['ref'];
    if (value == null) return null;

    final code = value.trim().toUpperCase();
    // The same unambiguous alphabet the server generates from (0071). Anything
    // else is not a referral code, and guessing would send a wrong one.
    return RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(code) ? code : null;
  }

  /// The link a customer shares: their salon, and their own code on the end.
  static String shareLink(JoinCode salon, String referral) =>
      '$origin/s/${salon.value}?r=$referral';
}
