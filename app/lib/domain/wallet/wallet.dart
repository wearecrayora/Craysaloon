/// The wallet, as the customer's app needs it.
///
/// Every amount here is **integer paise** (RULES 5.1.2). No double, no
/// `num`, no currency string parsed back into arithmetic - money is formatted
/// once, at the edge, by `core/format/money.dart`.
library;

class WalletSummary {
  const WalletSummary({
    required this.balancePaise,
    required this.paidPaise,
    required this.bonusPaise,
    this.nextBonusExpiry,
    this.nextBonusPaise = 0,
  });

  static const empty = WalletSummary(balancePaise: 0, paidPaise: 0, bonusPaise: 0);

  /// The number on the card. Paid and bonus are shown separately underneath -
  /// the summary is one number, the detail is honest (DESIGN 6.2).
  final int balancePaise;

  /// Never expires. Not a default, not a setting: there is no field and no code
  /// path that could expire it (RULES 5.3.3).
  final int paidPaise;

  final int bonusPaise;

  /// When the NEXT bonus lot goes, and how much of it. A total with no date
  /// attached tells a customer nothing they can act on.
  final DateTime? nextBonusExpiry;
  final int nextBonusPaise;
}

class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.balanceAfter,
    required this.createdAt,
    this.reason,
  });

  final int id;

  /// `credit_topup`, `credit_bonus`, `debit_spend`, `debit_expiry`,
  /// `credit_reversal`, `credit_referral`, `admin_correction`.
  final String kind;

  /// Signed: credits positive, debits negative.
  final int amountPaise;
  final int balanceAfter;
  final DateTime createdAt;

  /// Mandatory on a correction, absent on everything else.
  final String? reason;
}

/// What the server says a top-up of this size would produce — and what the
/// screen must state above the pay button before anyone pays.
class TopupQuote {
  const TopupQuote({
    required this.amountPaise,
    required this.bonusPaise,
    required this.minTopupPaise,
    this.bonusExpiresAt,
  });

  final int amountPaise;
  final int bonusPaise;
  final int minTopupPaise;
  final DateTime? bonusExpiresAt;

  bool get hasBonus => bonusPaise > 0;
}

/// A Razorpay order, made against **the salon's own account**. `keyId` is that
/// salon's public key — the secret never leaves the server, and no Crayora
/// account exists to fall back on (RULES 8).
class TopupOrder {
  const TopupOrder({
    required this.paymentId,
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
  });

  final String paymentId;
  final String orderId;
  final String keyId;
  final int amountPaise;
}

/// Why a top-up could not be started. Each one is a different sentence to the
/// customer, which is the only reason they are separate.
enum TopupProblem {
  belowMinimum,
  invalidAmount,

  /// The salon has no usable Razorpay account. Not the customer's fault, and
  /// **there is no Crayora account to fall back on** - by design.
  paymentsUnavailable,

  salonUnavailable,
  network,
}

class TopupException implements Exception {
  const TopupException(this.problem, {this.minTopupPaise});

  final TopupProblem problem;
  final int? minTopupPaise;
}

abstract interface class WalletApi {
  Future<WalletSummary> wallet();

  Future<List<WalletEntry>> walletHistory({int limit = 20, int? before});

  /// What this amount would buy, priced by the server. The screen never
  /// computes a bonus itself: an app that calculates its own bonus is an app
  /// that can promise one the ledger will refuse.
  Future<TopupQuote> topupQuote(int amountPaise);

  /// Creates the payment and the salon's Razorpay order. Idempotent on
  /// [clientActionId], so a retried tap cannot create a second way to pay.
  Future<TopupOrder> startTopup({
    required String clientActionId,
    required int amountPaise,
  });
}
