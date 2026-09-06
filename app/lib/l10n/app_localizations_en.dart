// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Cray Salon';

  @override
  String get joinTitle => 'Find your salon';

  @override
  String get joinScanQr => 'Scan the salon\'s QR code';

  @override
  String get joinEnterCode => 'Or enter the salon code';

  @override
  String get joinCodeHint => 'CRAY-XXXXXX';

  @override
  String joinConfirmTitle(String salonName) {
    return 'You\'re joining $salonName';
  }

  @override
  String get joinCodeInvalid =>
      'That code didn\'t match a salon. Check it and try again.';

  @override
  String get joinAlreadyBound =>
      'This number is already registered with a salon.';

  @override
  String get phoneTitle => 'Your mobile number';

  @override
  String get otpTitle => 'Enter the 6-digit code';

  @override
  String otpSentTo(String phone) {
    return 'Sent to $phone';
  }

  @override
  String get walletBalance => 'Available credit';

  @override
  String walletOnlyAtSalon(String salonName) {
    return 'Usable only at $salonName. Cannot be withdrawn as cash.';
  }

  @override
  String get addMoneyPaidNeverExpires => 'Money you pay never expires.';

  @override
  String addMoneyBonusExpires(String bonus, String date) {
    return 'Your $bonus bonus expires on $date.';
  }

  @override
  String get markComplete => 'Mark complete';

  @override
  String get needsAttention => 'Needs attention';

  @override
  String get offlineBanner =>
      'You\'re offline. Your changes are saved and will sync.';

  @override
  String get retry => 'Try again';
}
