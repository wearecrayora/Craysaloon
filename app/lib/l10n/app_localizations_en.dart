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

  @override
  String get scanHint => 'Point the camera at the salon\'s QR code';

  @override
  String get scanCameraUnavailable =>
      'The camera isn\'t available. You can enter the salon code by hand instead.';

  @override
  String get joinScanButton => 'Scan the QR code';

  @override
  String get customersTitle => 'Customers';

  @override
  String get customersSearchHint => 'Name, or full mobile number';

  @override
  String get customersEmpty =>
      'No customers yet. They join by scanning your QR code.';

  @override
  String get customersNoMatch =>
      'Nobody matched that. Try the full number, or fewer letters.';

  @override
  String get customerNeverVisited => 'Not visited yet';

  @override
  String customerLastVisit(String date) {
    return 'Last visit $date';
  }

  @override
  String customerVisits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visits',
      one: '1 visit',
      zero: 'No visits',
    );
    return '$_temp0';
  }

  @override
  String customerLoyalty(String points) {
    return '$points points';
  }

  @override
  String cachedAsOf(String time) {
    return 'Shown from this device, last updated $time.';
  }

  @override
  String get cachedNeverLoaded =>
      'Not loaded yet. Connect once to see your customers.';

  @override
  String get loadMore => 'Load more';

  @override
  String get catalogueServices => 'Services';

  @override
  String get catalogueAddOns => 'Add-ons';

  @override
  String get staffTitle => 'Team';

  @override
  String get catalogueEmpty =>
      'Nothing here yet. Crayora sets this up with you.';

  @override
  String get inactiveLabel => 'Hidden';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String addsMinutes(int minutes) {
    return 'adds $minutes min';
  }

  @override
  String get dayViewSoon => 'The day view arrives with bookings.';

  @override
  String get balanceReadOnly =>
      'Balance is set by top-ups and visits. It cannot be edited here.';

  @override
  String get catalogueAdd => 'Add';

  @override
  String get serviceFormTitle => 'Service';

  @override
  String get addOnFormTitle => 'Add-on';

  @override
  String get staffFormTitle => 'Team member';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldPrice => 'Price (₹)';

  @override
  String get fieldDuration => 'Minutes';

  @override
  String get fieldExtraMinutes => 'Extra minutes';

  @override
  String get fieldVisible => 'Customers can see this';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get formNameRequired => 'A name is needed - customers see it.';

  @override
  String get formPriceInvalid =>
      'Enter the price in rupees, for example 400 or 400.50.';

  @override
  String get formDurationInvalid => 'Enter the minutes, between 5 and 600.';

  @override
  String get saveFailedOffline =>
      'Not saved. Catalogue changes need a connection.';

  @override
  String get saveFailedRefused =>
      'Your account cannot change the catalogue. Ask the owner.';

  @override
  String get saveFailed => 'Not saved. Please try again.';
}
