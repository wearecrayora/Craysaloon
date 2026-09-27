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

  @override
  String get joinContinue => 'Continue';

  @override
  String get joinNotThisSalon => 'Not this salon? Enter a different code';

  @override
  String get joinConfirmBody =>
      'You\'ll become this salon\'s customer. Credit you buy and visits you make stay with them, and cannot move to another salon.';

  @override
  String get joinSalonUnavailable =>
      'This salon can\'t take sign-ins right now. Please ask at the counter.';

  @override
  String get joinRateLimited =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get joinOffline => 'No connection. Check your internet and try again.';

  @override
  String get joinGenericError => 'That didn\'t work. Please try again.';

  @override
  String get phoneHint => '10-digit mobile number';

  @override
  String get phoneServiceNote =>
      'Booking, payment and reminder messages are part of the service.';

  @override
  String get phoneConsentPromotional => 'Also send me offers from this salon';

  @override
  String get phoneConsentWhatsapp => 'Offers on WhatsApp too';

  @override
  String get otpResend => 'Send a new code';

  @override
  String otpExpiresIn(int seconds) {
    return 'Expires in ${seconds}s';
  }

  @override
  String get otpExpired => 'That code has expired. Send a new one.';

  @override
  String otpWrongCode(String attempts) {
    return 'That code didn\'t match. $attempts left.';
  }

  @override
  String get otpAccountConflict =>
      'We could not sign you in. Please contact the salon.';

  @override
  String joinedTitle(String salonName) {
    return 'Welcome to $salonName';
  }

  @override
  String get joinedBody => 'You\'re now a customer of this salon.';

  @override
  String get joinedStaff => 'Signed in to your salon.';

  @override
  String get joinStart => 'Get my code';

  @override
  String get homeReady => 'Bookings, credit and reminders arrive here.';

  @override
  String shortcutTitle(String salonName) {
    return 'Add $salonName to your home screen';
  }

  @override
  String get shortcutBody =>
      'One tap to your salon. Your phone will ask you to confirm.';

  @override
  String get shortcutAdd => 'Add to home screen';

  @override
  String get shortcutNotNow => 'Not now';

  @override
  String get shortcutAdded => 'Added. Look for it on your home screen.';
}
