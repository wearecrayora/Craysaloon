/// The owner's dashboard (O6).
///
/// Every number here comes from the server, and TODAY's are computed there from
/// the visits themselves - so a card cannot disagree with the till (PRD 9.5 AC).
/// The app formats; it never adds, averages or projects.
library;

class Dashboard {
  const Dashboard({
    required this.revenuePaise,
    required this.completed,
    this.avgBillPaise,
    required this.bookingsLive,
    required this.cancelled,
    required this.noShow,
    required this.newCustomers,
    required this.repeatCustomers,
    required this.walletCollectedPaise,
    required this.outstandingCreditPaise,
    required this.reminderBookings,
    required this.binds,
    required this.spendByChannel,
    required this.remindersSent,
    required this.ackedPushes,
    required this.cohorts,
    required this.driftDays,
  });

  final int revenuePaise;
  final int completed;

  /// Null with no completed visits - an average of nothing is not zero.
  final int? avgBillPaise;

  final int bookingsLive;
  final int cancelled;
  final int noShow;

  final int newCustomers;
  final int repeatCustomers;
  final int walletCollectedPaise;

  /// A balance the owner can SEE and cannot move. There is no control, API or
  /// permission anywhere that adjusts it (PRD 9.5).
  final int outstandingCreditPaise;

  final int reminderBookings;
  final int binds;

  /// This month, by channel. Always shown WITH [reminderBookings] - cost alone
  /// invites switching reminders off; conversion alone invites paying ₹1.28 a
  /// message without noticing (PRD 9.5).
  final Map<String, int> spendByChannel;
  final int remindersSent;

  /// Pushes the customer's phone confirmed - each one a message the salon did
  /// not pay for.
  final int ackedPushes;

  final List<CohortRow> cohorts;

  /// Days whose stored figures disagree with the source. Shown, never hidden.
  final List<String> driftDays;

  int get totalSpendPaise => spendByChannel.values.fold(0, (a, b) => a + b);
}

class CohortRow {
  const CohortRow({
    required this.month,
    required this.segment,
    required this.n,
    this.d30,
    this.d60,
    this.d90,
  });

  final DateTime month;

  /// `wallet` or `no_wallet`.
  final String segment;

  /// The cohort size. A rate without an n is a claim without evidence
  /// (DESIGN 9.4).
  final int n;

  /// Percentages, 0-100. **Null means not yet known** - the cohort has not had
  /// the full window - and is never drawn as zero.
  final double? d30;
  final double? d60;
  final double? d90;
}

abstract interface class DashboardApi {
  Future<Dashboard> dashboard();
}
