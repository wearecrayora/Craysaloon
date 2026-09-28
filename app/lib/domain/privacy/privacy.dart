/// The rights half of the app, in `domain/` so the screen can be tested with a
/// fake and no network (ARCHITECTURE 9.1).
///
/// These are not features. They are entitlements under the DPDP Act 2023 -
/// ss.6(4) withdrawal, 11 access, 12(3) erasure, 13 grievance - and the app's
/// job is to make using them **as easy as giving consent was**, which is the
/// statutory test. One screen, no email address to find, no form to download.
library;

/// The purposes the consent ledger knows. The names match the database enum
/// exactly; a string typed twice is a bug waiting for a rename.
class ConsentPurpose {
  static const service = 'service_communication';
  static const promotional = 'promotional';
  static const whatsapp = 'whatsapp';
  static const photos = 'photos';

  /// The order they are shown in: the one that cannot be switched off first, so
  /// nobody hunts for it, then the opt-ins.
  static const all = [service, promotional, whatsapp, photos];
}

class ConsentState {
  const ConsentState({
    required this.purpose,
    required this.granted,
    required this.occurredAt,
  });

  final String purpose;
  final bool granted;
  final DateTime occurredAt;
}

/// Why a consent change was refused. There is exactly one reason, and it is not
/// an error: service messages are the service, and the way out of them is
/// erasure, not a toggle (RULES 11.6c).
enum ConsentRefusal { serviceRequired }

class DataRightRequest {
  const DataRightRequest({
    required this.id,
    required this.kind,
    required this.status,
    required this.requestedAt,
    required this.dueAt,
    this.outcome,
  });

  /// `access`, `erasure` or `grievance`.
  final String kind;
  final String id;
  final String status;
  final DateTime requestedAt;
  final DateTime dueAt;

  /// Filled when the salon answers. A refusal is allowed; silence is not
  /// (RULES 11.11), so a completed request with no outcome is a defect.
  final String? outcome;

  bool get isOpen => status == 'open' || status == 'in_progress';
}

abstract interface class PrivacyApi {
  /// The current state of every purpose - the last row of the ledger.
  Future<List<ConsentState>> consents();

  /// Appends to the ledger. Returns null when it took effect, or the reason it
  /// did not.
  Future<ConsentRefusal?> setConsent(String purpose, bool granted);

  /// Raises the right against the salon, with a due date. Asking twice returns
  /// the request already open rather than making a second one.
  Future<DataRightRequest?> requestRight(String kind, {String? detail});

  /// What this customer has already asked for, so the screen can say "asked on
  /// the 2nd, due by the 2nd of next month" instead of offering the button
  /// again as though nothing happened.
  Future<List<DataRightRequest>> myRequests();
}
