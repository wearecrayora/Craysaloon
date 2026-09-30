/// What a signed-in customer reads about THEMSELVES.
///
/// Every read is the customer's own rows and nothing else, and that is the
/// database's doing, not this interface's: a restrictive policy keyed on
/// `app.current_customer_id()` sits on every table here (RULES 3.8a). None of
/// these calls takes a customer id - there is nothing to pass that could name
/// somebody else.
library;

/// The customer's own row: how the app greets them and what "Me" shows.
class CustomerProfile {
  const CustomerProfile({this.name, this.phone});

  final String? name;
  final String? phone;

  /// The first word of the name, for "Hi Asha". Null when there is no name -
  /// the greeting then says something true instead of "Hi null".
  String? get firstName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  /// `+91 98xxx x4821`: enough to recognise, not enough to read out.
  String? get maskedPhone {
    final digits = phone?.replaceAll(RegExp(r'\D'), '');
    if (digits == null || digits.length < 10) return null;
    final local = digits.substring(digits.length - 10);
    return '+91 ${local.substring(0, 2)}xxx x${local.substring(6)}';
  }
}

/// The next scheduled "you are due" reminder: the same date the salon's
/// reminder will go out on, so the app and the message never disagree.
class NextDue {
  const NextDue({required this.dueOn, this.serviceName});

  final DateTime dueOn;
  final String? serviceName;
}

/// A booking that has not happened yet.
class UpcomingBooking {
  const UpcomingBooking({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.totalPaise,
    this.serviceNames = '',
    this.staffName,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;

  /// `pending`, `confirmed`, `in_progress`, `completed`, `cancelled`, `no_show`.
  final String status;
  final int totalPaise;
  final String serviceNames;
  final String? staffName;

  int get minutes => endsAt.difference(startsAt).inMinutes;

  /// A customer may cancel what has not started (0047 refuses only a completed
  /// visit; the app does not offer to cancel one already in the chair).
  bool get cancellable => status == 'pending' || status == 'confirmed';
}

/// A completed visit, for "Visit history".
class PastVisit {
  const PastVisit({
    required this.id,
    required this.completedAt,
    required this.amountPaise,
    required this.paid,
    this.serviceNames = '',
    this.staffName,
  });

  final String id;
  final DateTime completedAt;
  final int amountPaise;
  final bool paid;
  final String serviceNames;
  final String? staffName;
}

abstract interface class CustomerApi {
  Future<CustomerProfile?> me();

  Future<NextDue?> nextDue();

  /// Not yet happened, soonest first.
  Future<List<UpcomingBooking>> upcoming();

  Future<UpcomingBooking?> booking(String id);

  /// Newest first.
  Future<List<PastVisit>> history({int limit = 30});
}
