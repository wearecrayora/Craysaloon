/// The salon's own standing with Crayora: whether it can change anything, and
/// which features its plan carries (M11, 0087).
library;

/// unbilled | active | grace | suspended | purge_due - the SERVER's word,
/// computed from the date the paid period ends.
class SalonBilling {
  const SalonBilling({
    required this.state,
    required this.readOnly,
    this.renewsAt,
    this.graceEndsAt,
    this.plan,
    this.monthlyPricePaise,
  });

  static const open = SalonBilling(state: 'unbilled', readOnly: false);

  final String state;

  /// Nothing can be changed: the subscription has lapsed, or the salon is
  /// otherwise closed. The server enforces it; the app only explains it.
  final bool readOnly;
  final DateTime? renewsAt;
  final DateTime? graceEndsAt;

  /// Owners and managers only: what the salon pays Crayora is not a stylist's
  /// business, and the server does not send it to one (0087).
  final String? plan;
  final int? monthlyPricePaise;

  bool get lapsed => state == 'grace' || state == 'suspended' || state == 'purge_due';
}

/// The salon's own business details, as its staff may read them (0096: the
/// business columns only - never the webhook token or who at Crayora acted).
/// Read-only in the app: Crayora changes them in the console.
class SalonProfile {
  const SalonProfile({
    required this.displayName,
    this.legalName,
    this.address,
    this.phone,
    this.email,
    this.gstNumber,
    this.gstRateBp,
    this.workingHours = const {},
    this.walletRule = const {},
    this.rewardRule = const {},
    this.cancellationPolicy,
    this.reminderCycleDays,
    this.grievanceName,
    this.grievanceEmail,
    this.grievancePhone,
  });

  final String displayName;
  final String? legalName;
  final String? address;
  final String? phone;
  final String? email;
  final String? gstNumber;
  final int? gstRateBp;
  final Map<String, Object?> workingHours;
  final Map<String, Object?> walletRule;
  final Map<String, Object?> rewardRule;
  final String? cancellationPolicy;
  final int? reminderCycleDays;
  final String? grievanceName;
  final String? grievanceEmail;
  final String? grievancePhone;
}

abstract interface class SalonAccountApi {
  Future<SalonBilling> myBilling();

  Future<SalonProfile?> mySalon();

  /// The features this salon has. Hiding a button is a courtesy: the server
  /// refuses the call either way.
  Future<Set<String>> myFeatures();
}
