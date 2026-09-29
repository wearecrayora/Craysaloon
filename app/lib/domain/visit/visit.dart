/// The customer's side of a visit: the code that starts it, and the bill that
/// ends it (requested 29 Sep 2026; 0084-0086).
library;

import '../wallet/wallet.dart';

/// A booking for today, as the customer's app shows it.
class TodayVisit {
  const TodayVisit({
    required this.bookingId,
    required this.startsAt,
    required this.status,
    this.services = '',
    this.staff,
    this.startCode,
  });

  final String bookingId;
  final DateTime startsAt;

  /// pending | confirmed | in_progress
  final String status;
  final String services;
  final String? staff;

  /// What the customer reads to the stylist. Present only while the service can
  /// still be started - and readable by nobody but this customer (0084).
  final String? startCode;

  bool get inProgress => status == 'in_progress';
}

/// A completed visit that is not yet fully paid.
class Bill {
  const Bill({
    required this.visitId,
    required this.completedAt,
    required this.totalPaise,
    required this.duePaise,
    this.services = '',
    this.counterRequested = false,
  });

  final String visitId;
  final DateTime completedAt;
  final String services;
  final int totalPaise;

  /// What is LEFT to pay. The server's number, always (0085).
  final int duePaise;

  /// The customer has already said they will pay at the counter.
  final bool counterRequested;
}

/// Why paying failed. Separate only because each is a different sentence.
enum BillProblem { notFound, alreadyPaid, paymentsUnavailable, network }

class BillException implements Exception {
  const BillException(this.problem);

  final BillProblem problem;
}

abstract interface class VisitApi {
  Future<List<TodayVisit>> visitsToday();

  Future<List<Bill>> bills();

  /// Spends the customer's own wallet on the bill, as far as it goes. Returns
  /// what is left to pay.
  Future<int> payBillFromWallet({required String clientActionId, required String visitId});

  /// Creates the Razorpay order for what is LEFT on the bill - the salon's own
  /// account, the server's amount (0085).
  Future<TopupOrder> startBillPayment({required String clientActionId, required String visitId});

  /// Tells the counter. Settles NOTHING: staff take the money (decision of
  /// 29 Sep 2026).
  Future<void> requestCounterPayment(String visitId);
}
