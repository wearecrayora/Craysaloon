/// Who can sign in to the salon's own screens (0106): the owner, and the
/// managers and stylists the owner (or Crayora) has added.
enum LoginRole { owner, manager, staff }

class StaffLogin {
  const StaffLogin({
    required this.id,
    required this.role,
    required this.name,
    required this.phoneLast4,
    required this.active,
    required this.signedIn,
  });

  final String id;
  final LoginRole role;
  final String name;

  /// Only the last four digits - a number shown on a shared salon phone is a
  /// number anyone at the counter can read.
  final String phoneLast4;
  final bool active;

  /// Has signed in at least once.
  final bool signedIn;
}

/// Why an add or a switch did not happen. Each is a sentence the owner can act
/// on - none of them names another salon (RULES 4.4).
enum LoginRefusal { numberInUse, badPhone, nameRequired, ownerLogin, notFound, salonUnavailable }

class LoginOutcomeResult {
  const LoginOutcomeResult.ok() : refusal = null;
  const LoginOutcomeResult.refused(this.refusal);

  final LoginRefusal? refusal;
  bool get ok => refusal == null;
}

/// The owner's controls (0106). The database lets only the OWNER call these;
/// a manager or stylist is refused there, not just hidden here.
abstract interface class StaffLoginsApi {
  Future<List<StaffLogin>> staffLogins();

  Future<LoginOutcomeResult> addStaffLogin({
    required String name,
    required String phone,
    required LoginRole role,
  });

  Future<LoginOutcomeResult> setStaffLoginActive(String id, {required bool active});
}
