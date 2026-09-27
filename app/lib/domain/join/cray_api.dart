/// What the app needs from the server to get someone into their salon.
///
/// An interface, in `domain/`, so the join flow can be tested without a network
/// and without Supabase (`ARCHITECTURE.md` 9.1 - domain imports no transport).
/// The Supabase implementation lives in `data/remote`, the only place allowed to
/// call `.rpc(` or `.from(` at all (GATE-1).
library;

/// An active salon, as the pre-auth lookup returns it. This is the only thing
/// the server will say before anyone logs in, and it is deliberately thin:
/// a name and a look, never a customer, a phone number or a count.
class SalonSummary {
  const SalonSummary({
    required this.salonId,
    required this.displayName,
    required this.brandingVersion,
    required this.branding,
  });

  final String salonId;
  final String displayName;
  final int brandingVersion;

  /// The published branding document, carrying its resolved token sets.
  final Map<String, Object?> branding;
}

class OtpChallenge {
  const OtpChallenge({required this.challengeId, required this.expiresIn});

  final String challengeId;

  /// Message Central's own validity, in seconds - about a minute. The app shows
  /// a countdown from this rather than assuming a number (ADR-36).
  final int expiresIn;
}

/// What happened at the end of a successful login.
enum LoginOutcome {
  /// First login at this salon: the customer is now bound to it.
  bound,

  /// A returning customer of this salon.
  returning,

  /// Staff - the owner or a team member the console provisioned.
  staff,
}

enum CrayErrorKind {
  network,
  rateLimited,

  /// The salon cannot take this login: suspended, or blocked because its
  /// messaging was never set up (migration 0033). Not the customer's fault, and
  /// the app says so plainly.
  salonUnavailable,
  invalidPhone,
  wrongCode,

  /// Message Central's code has expired. Offer a resend, never ask someone to
  /// retype a code that was right.
  otpExpired,

  /// The number belongs to another salon. **The app must not name it**
  /// (`RULES.md` 4.4) - and the server never tells it which.
  alreadyBound,

  /// An account exists for this number that the server did not create. Support
  /// territory, not something to retry.
  accountConflict,
  server,
}

class CrayApiException implements Exception {
  const CrayApiException(this.kind, {this.attemptsLeft});

  final CrayErrorKind kind;
  final int? attemptsLeft;

  @override
  String toString() => 'CrayApiException($kind)';
}

abstract interface class CrayApi {
  /// Pre-auth, `anon`-callable, rate-limited. Null when the code matches no
  /// ACTIVE salon - a salon still in setup looks exactly like a code that does
  /// not exist, so a leaked QR reveals nothing.
  Future<SalonSummary?> resolveJoinCode(String code, {required String deviceKey});

  /// Records the intent, so the OTP is sent from THIS salon's account.
  Future<void> startJoin({
    required String code,
    required String phone,
    required String deviceKey,
  });

  Future<OtpChallenge> sendOtp(String phone);

  /// Verifies with Message Central, binds, and only then returns a session.
  /// [promotional] and [whatsapp] are the customer's marketing choices; service
  /// messages are the service itself and are not asked for here.
  Future<LoginOutcome> verifyOtp({
    required String challengeId,
    required String code,
    bool promotional = false,
    bool whatsapp = false,
  });

  /// True when a session is already stored on the device.
  bool get hasSession;
}
