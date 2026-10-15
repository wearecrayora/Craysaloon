import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/domain/dashboard/dashboard.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/notifications/push_api.dart';
import 'package:craysalon/domain/privacy/privacy.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:craysalon/domain/referral/referral.dart';
import 'package:craysalon/domain/salon/salon_account.dart';
import 'package:craysalon/domain/salon/staff_logins.dart';
import 'package:craysalon/domain/visit/visit.dart';
import 'package:craysalon/domain/wallet/wallet.dart';

/// The server, with the internet gone: every call it is asked to make fails as
/// a network error, whatever the call. Implements every interface the real
/// `SupabaseCrayApi` does, so every screen reaches it the same way.
class OfflineApi
    implements CrayApi, SalonReads, SalonWrites, SalonBookings, PrivacyApi, WalletApi,
        PushApi, ReferralApi, DashboardApi, VisitApi, SalonAccountApi, CustomerApi,
        SalonHoursApi, StaffLoginsApi {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    // Future-returning members fail the way a dropped connection does.
    return Future<Never>.error(const CrayApiException(CrayErrorKind.network));
  }
}
