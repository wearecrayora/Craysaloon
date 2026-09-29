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
  });

  static const open = SalonBilling(state: 'unbilled', readOnly: false);

  final String state;

  /// Nothing can be changed: the subscription has lapsed, or the salon is
  /// otherwise closed. The server enforces it; the app only explains it.
  final bool readOnly;
  final DateTime? renewsAt;
  final DateTime? graceEndsAt;

  bool get lapsed => state == 'grace' || state == 'suspended' || state == 'purge_due';
}

abstract interface class SalonAccountApi {
  Future<SalonBilling> myBilling();

  /// The features this salon has. Hiding a button is a courtesy: the server
  /// refuses the call either way.
  Future<Set<String>> myFeatures();
}
