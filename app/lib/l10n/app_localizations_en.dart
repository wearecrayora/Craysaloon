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

  @override
  String get dayTitle => 'Today';

  @override
  String get dayEmpty => 'Nothing booked today.';

  @override
  String get dayDone => 'Done';

  @override
  String get dayCancelled => 'Cancelled';

  @override
  String daySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to sync',
      one: '1 change waiting to sync',
    );
    return '$_temp0';
  }

  @override
  String get dayCancelBooking => 'Cancel appointment';

  @override
  String get attentionEmpty => 'Nothing needs attention.';

  @override
  String get attentionDiscard => 'Discard';

  @override
  String get attentionOpComplete => 'Mark complete';

  @override
  String get attentionOpBooking => 'New booking';

  @override
  String get attentionOpCancel => 'Cancellation';

  @override
  String get reasonSlotTaken =>
      'That time was taken by someone else. Pick another and try again.';

  @override
  String get reasonForbidden => 'Your account cannot do this. Ask the owner.';

  @override
  String get reasonNotCompletable =>
      'That appointment was already finished or cancelled.';

  @override
  String get reasonSalonUnavailable =>
      'The salon cannot accept changes right now.';

  @override
  String get reasonSalonChanged =>
      'This was for a salon this phone is no longer signed in to.';

  @override
  String get reasonGeneric => 'The server could not accept this.';

  @override
  String get walkInTitle => 'Walk-in';

  @override
  String get walkInCustomer => 'Customer';

  @override
  String get walkInService => 'Service';

  @override
  String get walkInAddOns => 'Add-ons (optional)';

  @override
  String get walkInStaff => 'With';

  @override
  String get walkInAnyStaff => 'Anyone';

  @override
  String get walkInTime => 'Time';

  @override
  String get walkInNoSlots => 'No free times left for that day.';

  @override
  String get walkInBook => 'Book';

  @override
  String get walkInBooked => 'Booked.';

  @override
  String get walkInQueuedOffline =>
      'Saved. It will book when you are back online.';

  @override
  String noticeHeading(String salonName) {
    return 'What $salonName will know about you';
  }

  @override
  String get noticeItemPhone =>
      'Your mobile number, to send your login code and to reach you about a booking.';

  @override
  String get noticeItemVisits =>
      'Your name and your visits, so your history, balance and points stay right.';

  @override
  String get noticeItemOptional =>
      'Your birthday and photos are optional, asked for separately, and off unless you say yes.';

  @override
  String noticeFiduciary(String salonName) {
    return '$salonName decides what it keeps and why. Crayora makes the app and stores it for them.';
  }

  @override
  String get noticeControl =>
      'You can withdraw any of this, ask for a copy of your data, or ask to be deleted — any time, under Your data.';

  @override
  String get noticeContactHeading => 'Questions or complaints';

  @override
  String get noticeContactNone =>
      'Ask at the salon counter. If nobody answers, write to Crayora.';

  @override
  String get noticePolicyLink => 'Read the full privacy policy';

  @override
  String get noticeLinkFailed =>
      'Nothing on this phone can open that. The address is above.';

  @override
  String get yourDataTitle => 'Your data';

  @override
  String get yourDataConsentsHeading => 'What you have agreed to';

  @override
  String get yourDataRightsHeading => 'Your rights';

  @override
  String get yourDataFiduciaryHeading => 'Who holds your data';

  @override
  String get consentServiceTitle => 'Booking and payment messages';

  @override
  String get consentServiceLocked =>
      'Part of the service. To stop these, ask for your account to be deleted.';

  @override
  String get consentPromotionalTitle => 'Offers from this salon';

  @override
  String get consentWhatsappTitle => 'Offers on WhatsApp';

  @override
  String get consentPhotosTitle => 'Before and after photos';

  @override
  String get consentPhotosSubtitle =>
      'So the salon can show you what was done last time.';

  @override
  String get consentSaveFailed =>
      'That did not save. Check your connection and try again.';

  @override
  String get rightAccessTitle => 'Ask for a copy of my data';

  @override
  String get rightErasureTitle => 'Ask for my account to be deleted';

  @override
  String get rightGrievanceTitle => 'Raise a complaint about my data';

  @override
  String rightAsked(String asked, String due) {
    return 'Asked $asked. Answer due by $due.';
  }

  @override
  String rightAnswered(String outcome) {
    return 'Answered: $outcome';
  }

  @override
  String get rightAskedThanks => 'Asked. The salon has 30 days to answer.';

  @override
  String get erasureConfirmTitle => 'Ask to be deleted?';

  @override
  String get erasureConfirmBody =>
      'Your name, number and birthday are removed, and you are logged out. Payments and wallet records stay without your name — the salon has to keep its books by law. This cannot be undone.';

  @override
  String get erasureConfirmAction => 'Yes, ask for deletion';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletPaidLabel => 'Paid credit';

  @override
  String get walletBonusLabel => 'Bonus credit';

  @override
  String walletBonusExpiryNote(String amount, String date) {
    return '$amount of bonus expires on $date.';
  }

  @override
  String get walletAddMoney => 'Add money';

  @override
  String get walletHistoryHeading => 'Recent activity';

  @override
  String get walletHistoryEmpty =>
      'Nothing yet. Money you add, and money you use here, shows up in this list.';

  @override
  String get entryTopUp => 'Money added';

  @override
  String get entryBonus => 'Bonus';

  @override
  String get entrySpend => 'Used at the salon';

  @override
  String get entryExpiry => 'Bonus expired';

  @override
  String get entryReversal => 'Reversed';

  @override
  String get entryReferral => 'Referral reward';

  @override
  String get entryCorrection => 'Correction';

  @override
  String get addMoneyTitle => 'Add money';

  @override
  String get addMoneyAmount => 'Amount';

  @override
  String addMoneyBonusYouGet(String bonus) {
    return 'You get $bonus extra.';
  }

  @override
  String get addMoneyNoBonus => 'No bonus on this amount.';

  @override
  String get addMoneyNotRefundable =>
      'A top-up cannot be refunded or taken out as cash.';

  @override
  String get addMoneyDisclosureHeading => 'Before you pay';

  @override
  String addMoneyPay(String amount) {
    return 'Pay $amount';
  }

  @override
  String addMoneyBelowMinimum(String min) {
    return 'The smallest top-up here is $min.';
  }

  @override
  String get addMoneyInvalid => 'Enter an amount to add.';

  @override
  String get addMoneyUnavailable =>
      'This salon cannot take payments yet. Ask at the counter.';

  @override
  String get addMoneyCheckoutNotReady =>
      'Paying from the app is not switched on in this version yet. Your money has not moved.';

  @override
  String get addMoneySubmitted =>
      'Payment sent. Your credit appears as soon as the bank confirms it.';

  @override
  String get addMoneyCancelled => 'Payment cancelled. Nothing was charged.';

  @override
  String get addMoneyFailed =>
      'That payment did not go through. Nothing was charged.';

  @override
  String get referTitle => 'Refer & Earn';

  @override
  String referHeadline(String referred, String referrer) {
    return 'Give $referred, get $referrer';
  }

  @override
  String referHowItWorks(String salonName) {
    return 'Share your code. When your friend joins $salonName and finishes their first paid visit, you both get credit in your wallets.';
  }

  @override
  String get referYourCode => 'Your code';

  @override
  String get referCopy => 'Copy';

  @override
  String get referCopied => 'Copied';

  @override
  String get referShare => 'Share';

  @override
  String referWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friends have joined and not visited yet',
      one: '1 friend has joined and not visited yet',
      zero: 'No one is waiting on a first visit',
    );
    return '$_temp0';
  }

  @override
  String get referEarnedNone => 'Nothing earned yet.';

  @override
  String referEarned(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friends have visited. You have earned $amount.',
      one: '1 friend has visited. You have earned $amount.',
    );
    return '$_temp0';
  }

  @override
  String referNotCash(String salonName) {
    return 'Referral credit is usable only at $salonName and cannot be taken out as cash.';
  }

  @override
  String get referClaimTitle => 'Were you invited?';

  @override
  String get referClaimHint => 'Enter your friend\'s code';

  @override
  String get referClaimAction => 'Apply code';

  @override
  String get referClaimed =>
      'Code applied. You both get credit after your first paid visit.';

  @override
  String get referClaimUnknown => 'That code does not belong to this salon.';

  @override
  String get referClaimSelf => 'That is your own code.';

  @override
  String get referClaimAlready =>
      'A friend\'s code has already been applied to your account.';

  @override
  String get referClaimNotNew =>
      'Referral codes are for a first visit, and you have already been in.';

  @override
  String get dashTitle => 'Dashboard';

  @override
  String get dashToday => 'Today';

  @override
  String get dashRevenue => 'Revenue';

  @override
  String get dashCompleted => 'Visits done';

  @override
  String get dashAvgBill => 'Average bill';

  @override
  String get dashNoAverage => '—';

  @override
  String get dashBookings => 'Bookings';

  @override
  String dashCancelledNoShow(int cancelled, int noShow) {
    return '$cancelled cancelled · $noShow no-show';
  }

  @override
  String get dashThisMonth => 'This month';

  @override
  String get dashNewRepeat => 'New / returning';

  @override
  String get dashWalletCollected => 'Wallet top-ups';

  @override
  String get dashOutstanding => 'Credit customers hold';

  @override
  String get dashOutstandingNote =>
      'Shown, not adjustable. Balances change only through top-ups and visits.';

  @override
  String get dashBinds => 'New customers joined';

  @override
  String get dashMessagingTitle =>
      'Reminders: what they cost and what they brought';

  @override
  String get dashSpend => 'Spent on messages';

  @override
  String dashRemindersSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders sent',
      one: '1 reminder sent',
    );
    return '$_temp0';
  }

  @override
  String dashReminderBookings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookings from reminders',
      one: '1 booking from reminders',
    );
    return '$_temp0';
  }

  @override
  String dashPushSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages went free by app notification',
      one: '1 message went free by app notification',
    );
    return '$_temp0';
  }

  @override
  String get dashCohortTitle => 'Do customers come back?';

  @override
  String get dashCohortAxis => '% who returned';

  @override
  String get dashCohortWallet => 'Use the wallet';

  @override
  String get dashCohortNoWallet => 'No wallet';

  @override
  String dashCohortWithin(int days) {
    return 'Within $days days';
  }

  @override
  String get dashCohortNotYet => 'not yet';

  @override
  String dashCohortN(int n) {
    return 'n = $n';
  }

  @override
  String get dashCohortEmpty =>
      'Cohorts appear once customers have had their first visit.';

  @override
  String get dashCohortTable => 'The same numbers';

  @override
  String get dashCohortMonth => 'Joined';

  @override
  String get dashCohortGroup => 'Group';

  @override
  String get dashDrift =>
      'Some past figures disagree with the records and are being checked.';

  @override
  String get payTake => 'Take payment';

  @override
  String get payPaid => 'Paid';

  @override
  String get payPartial => 'Part paid';

  @override
  String get paySheetTitle => 'Take payment';

  @override
  String get payUseWallet => 'Use the customer\'s wallet first';

  @override
  String paySplit(String wallet, String counter) {
    return 'Wallet pays $wallet. Collect $counter.';
  }

  @override
  String payCollectAll(String amount) {
    return 'Collect $amount.';
  }

  @override
  String get payNoQuote =>
      'No connection, so the wallet balance cannot be checked. Collect the full amount, or wait until you are online to use the wallet.';

  @override
  String get payMethod => 'The rest by';

  @override
  String get payCash => 'Cash';

  @override
  String get payUpi => 'UPI';

  @override
  String get payCard => 'Card';

  @override
  String get payRecord => 'Record payment';

  @override
  String get payQueued =>
      'Payment recorded. It will show as paid once it reaches the server.';
}
