/// Refer & Earn (C11).
///
/// The one screen in the app where a customer is asked to do something for the
/// salon rather than for themselves, so it has to be honest about when the
/// reward actually arrives: **after the friend's first completed, paid visit**
/// (RULES 10). A screen that implies "share and get ₹100" produces a complaint
/// the moment somebody shares and gets nothing.
library;

class ReferralSummary {
  const ReferralSummary({
    required this.code,
    required this.referrerPaise,
    required this.referredPaise,
    this.pending = 0,
    this.rewarded = 0,
    this.earnedPaise = 0,
  });

  /// Created once and reused forever — a code already given to a friend has to
  /// keep working.
  final String code;

  /// What the server says each side gets. Never computed in the app: a screen
  /// that works out its own reward is a screen that can promise one the ledger
  /// will refuse.
  final int referrerPaise;
  final int referredPaise;

  /// Claimed the code, not yet been in.
  final int pending;

  /// Been in, paid, and the reward has been released.
  final int rewarded;
  final int earnedPaise;
}

/// Why a claim was refused. Each is a different sentence, which is the only
/// reason they are separate values.
enum ClaimRefusal {
  /// Already has a referrer. One per customer, enforced by a unique index.
  alreadyReferred,

  /// Their own code.
  selfReferral,

  /// No such code at this salon.
  unknownCode,

  /// They have already paid for a visit here. A referral is for a new customer,
  /// not a retrospective claim on an existing one.
  notNewCustomer,
}

abstract interface class ReferralApi {
  Future<ReferralSummary> referralSummary();

  /// Attaches this customer to someone else's code. Returns null when it took
  /// effect, or the reason it did not.
  Future<ClaimRefusal?> claimReferral(String code);
}
