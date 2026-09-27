import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn'),
  ];

  /// Fallback app title. Once a customer is bound, the salon's displayName replaces this everywhere (DESIGN.md 2.1).
  ///
  /// In en, this message translates to:
  /// **'Cray Salon'**
  String get appTitle;

  /// U2 - salon code entry. Shown BEFORE login (RULES.md 4.1).
  ///
  /// In en, this message translates to:
  /// **'Find your salon'**
  String get joinTitle;

  /// No description provided for @joinScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the salon\'s QR code'**
  String get joinScanQr;

  /// No description provided for @joinEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Or enter the salon code'**
  String get joinEnterCode;

  /// No description provided for @joinCodeHint.
  ///
  /// In en, this message translates to:
  /// **'CRAY-XXXXXX'**
  String get joinCodeHint;

  /// U3 - the salon is named before binding. Never translate salonName.
  ///
  /// In en, this message translates to:
  /// **'You\'re joining {salonName}'**
  String joinConfirmTitle(String salonName);

  /// Never blame the user (DESIGN.md 8).
  ///
  /// In en, this message translates to:
  /// **'That code didn\'t match a salon. Check it and try again.'**
  String get joinCodeInvalid;

  /// MUST NOT name the other salon - that is a cross-tenant leak (RULES.md 4.4).
  ///
  /// In en, this message translates to:
  /// **'This number is already registered with a salon.'**
  String get joinAlreadyBound;

  /// No description provided for @phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Your mobile number'**
  String get phoneTitle;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get otpTitle;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @walletBalance.
  ///
  /// In en, this message translates to:
  /// **'Available credit'**
  String get walletBalance;

  /// Shown with every balance. Never show a balance alone (DESIGN.md 6.1).
  ///
  /// In en, this message translates to:
  /// **'Usable only at {salonName}. Cannot be withdrawn as cash.'**
  String walletOnlyAtSalon(String salonName);

  /// Disclosure block, above the pay button (RULES.md 5.3.6).
  ///
  /// In en, this message translates to:
  /// **'Money you pay never expires.'**
  String get addMoneyPaidNeverExpires;

  /// No description provided for @addMoneyBonusExpires.
  ///
  /// In en, this message translates to:
  /// **'Your {bonus} bonus expires on {date}.'**
  String addMoneyBonusExpires(String bonus, String date);

  /// One tap, no confirm dialog (DESIGN.md 6.4).
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get markComplete;

  /// O3 - rejected offline actions. Never dropped silently.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Your changes are saved and will sync.'**
  String get offlineBanner;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @joinContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get joinContinue;

  /// No description provided for @joinNotThisSalon.
  ///
  /// In en, this message translates to:
  /// **'Not this salon? Enter a different code'**
  String get joinNotThisSalon;

  /// DPDP + licensing: credit is redeemable only at the issuing salon (RULES 2).
  ///
  /// In en, this message translates to:
  /// **'You\'ll become this salon\'s customer. Credit you buy and visits you make stay with them, and cannot move to another salon.'**
  String get joinConfirmBody;

  /// Shown for a suspended or messaging-blocked salon (0033). Never blames the customer, never names a reason that is the salon’s business.
  ///
  /// In en, this message translates to:
  /// **'This salon can\'t take sign-ins right now. Please ask at the counter.'**
  String get joinSalonUnavailable;

  /// No description provided for @joinRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get joinRateLimited;

  /// No description provided for @joinOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get joinOffline;

  /// No description provided for @joinGenericError.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work. Please try again.'**
  String get joinGenericError;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit mobile number'**
  String get phoneHint;

  /// No description provided for @phoneServiceNote.
  ///
  /// In en, this message translates to:
  /// **'Booking, payment and reminder messages are part of the service.'**
  String get phoneServiceNote;

  /// Marketing consent is opt-in and starts UNTICKED (RULES 11).
  ///
  /// In en, this message translates to:
  /// **'Also send me offers from this salon'**
  String get phoneConsentPromotional;

  /// No description provided for @phoneConsentWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Offers on WhatsApp too'**
  String get phoneConsentWhatsapp;

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get otpResend;

  /// No description provided for @otpExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {seconds}s'**
  String otpExpiresIn(int seconds);

  /// No description provided for @otpExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Send a new one.'**
  String get otpExpired;

  /// No description provided for @otpWrongCode.
  ///
  /// In en, this message translates to:
  /// **'That code didn\'t match. {attempts} left.'**
  String otpWrongCode(String attempts);

  /// No description provided for @otpAccountConflict.
  ///
  /// In en, this message translates to:
  /// **'We could not sign you in. Please contact the salon.'**
  String get otpAccountConflict;

  /// No description provided for @joinedTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {salonName}'**
  String joinedTitle(String salonName);

  /// No description provided for @joinedBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re now a customer of this salon.'**
  String get joinedBody;

  /// No description provided for @joinedStaff.
  ///
  /// In en, this message translates to:
  /// **'Signed in to your salon.'**
  String get joinedStaff;

  /// No description provided for @joinStart.
  ///
  /// In en, this message translates to:
  /// **'Get my code'**
  String get joinStart;

  /// No description provided for @homeReady.
  ///
  /// In en, this message translates to:
  /// **'Bookings, credit and reminders arrive here.'**
  String get homeReady;

  /// No description provided for @shortcutTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {salonName} to your home screen'**
  String shortcutTitle(String salonName);

  /// An OFFER, never a promise: Android shows its own confirmation and can refuse (ARCHITECTURE 7.3). Never shown on iOS, which has no such API.
  ///
  /// In en, this message translates to:
  /// **'One tap to your salon. Your phone will ask you to confirm.'**
  String get shortcutBody;

  /// No description provided for @shortcutAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to home screen'**
  String get shortcutAdd;

  /// No description provided for @shortcutNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get shortcutNotNow;

  /// No description provided for @shortcutAdded.
  ///
  /// In en, this message translates to:
  /// **'Added. Look for it on your home screen.'**
  String get shortcutAdded;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the salon\'s QR code'**
  String get scanHint;

  /// A refused camera is a supported path, not an error: manual entry always works (IMPLEMENTATION U2).
  ///
  /// In en, this message translates to:
  /// **'The camera isn\'t available. You can enter the salon code by hand instead.'**
  String get scanCameraUnavailable;

  /// No description provided for @joinScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code'**
  String get joinScanButton;

  /// No description provided for @customersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersTitle;

  /// No description provided for @customersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, or full mobile number'**
  String get customersSearchHint;

  /// No description provided for @customersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No customers yet. They join by scanning your QR code.'**
  String get customersEmpty;

  /// No description provided for @customersNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Nobody matched that. Try the full number, or fewer letters.'**
  String get customersNoMatch;

  /// No description provided for @customerNeverVisited.
  ///
  /// In en, this message translates to:
  /// **'Not visited yet'**
  String get customerNeverVisited;

  /// No description provided for @customerLastVisit.
  ///
  /// In en, this message translates to:
  /// **'Last visit {date}'**
  String customerLastVisit(String date);

  /// No description provided for @customerVisits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No visits} =1{1 visit} other{{count} visits}}'**
  String customerVisits(int count);

  /// No description provided for @customerLoyalty.
  ///
  /// In en, this message translates to:
  /// **'{points} points'**
  String customerLoyalty(String points);

  /// Cached data is LABELLED, never passed off as live (ARCHITECTURE 10.2).
  ///
  /// In en, this message translates to:
  /// **'Shown from this device, last updated {time}.'**
  String cachedAsOf(String time);

  /// No description provided for @cachedNeverLoaded.
  ///
  /// In en, this message translates to:
  /// **'Not loaded yet. Connect once to see your customers.'**
  String get cachedNeverLoaded;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @catalogueServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get catalogueServices;

  /// No description provided for @catalogueAddOns.
  ///
  /// In en, this message translates to:
  /// **'Add-ons'**
  String get catalogueAddOns;

  /// No description provided for @staffTitle.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get staffTitle;

  /// No description provided for @catalogueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Crayora sets this up with you.'**
  String get catalogueEmpty;

  /// No description provided for @inactiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get inactiveLabel;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// No description provided for @addsMinutes.
  ///
  /// In en, this message translates to:
  /// **'adds {minutes} min'**
  String addsMinutes(int minutes);

  /// No description provided for @dayViewSoon.
  ///
  /// In en, this message translates to:
  /// **'The day view arrives with bookings.'**
  String get dayViewSoon;

  /// O5 shows a balance and cannot change it: no control, no endpoint, no permission (RULES 2, 5.2).
  ///
  /// In en, this message translates to:
  /// **'Balance is set by top-ups and visits. It cannot be edited here.'**
  String get balanceReadOnly;

  /// No description provided for @catalogueAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get catalogueAdd;

  /// No description provided for @serviceFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceFormTitle;

  /// No description provided for @addOnFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Add-on'**
  String get addOnFormTitle;

  /// No description provided for @staffFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get staffFormTitle;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (₹)'**
  String get fieldPrice;

  /// No description provided for @fieldDuration.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get fieldDuration;

  /// No description provided for @fieldExtraMinutes.
  ///
  /// In en, this message translates to:
  /// **'Extra minutes'**
  String get fieldExtraMinutes;

  /// Hiding a service does not delete it: history keeps its own snapshot (ARCHITECTURE 6.2).
  ///
  /// In en, this message translates to:
  /// **'Customers can see this'**
  String get fieldVisible;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @formNameRequired.
  ///
  /// In en, this message translates to:
  /// **'A name is needed - customers see it.'**
  String get formNameRequired;

  /// No description provided for @formPriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the price in rupees, for example 400 or 400.50.'**
  String get formPriceInvalid;

  /// No description provided for @formDurationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the minutes, between 5 and 600.'**
  String get formDurationInvalid;

  /// No description provided for @saveFailedOffline.
  ///
  /// In en, this message translates to:
  /// **'Not saved. Catalogue changes need a connection.'**
  String get saveFailedOffline;

  /// Shown when the DATABASE refuses the write - only owner/manager may change the catalogue (0041).
  ///
  /// In en, this message translates to:
  /// **'Your account cannot change the catalogue. Ask the owner.'**
  String get saveFailedRefused;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Not saved. Please try again.'**
  String get saveFailed;

  /// O1, the day view. The tab is the DAY; mark-complete is an action on it, not its name.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dayTitle;

  /// No description provided for @dayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing booked today.'**
  String get dayEmpty;

  /// No description provided for @dayDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dayDone;

  /// No description provided for @dayCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get dayCancelled;

  /// Shown when work is queued: the owner must never wonder whether a tap was lost (RULES 9.6).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change waiting to sync} other{{count} changes waiting to sync}}'**
  String daySyncPending(int count);

  /// No description provided for @dayCancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel appointment'**
  String get dayCancelBooking;

  /// No description provided for @attentionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention.'**
  String get attentionEmpty;

  /// No description provided for @attentionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get attentionDiscard;

  /// No description provided for @attentionOpComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get attentionOpComplete;

  /// No description provided for @attentionOpBooking.
  ///
  /// In en, this message translates to:
  /// **'New booking'**
  String get attentionOpBooking;

  /// No description provided for @attentionOpCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancellation'**
  String get attentionOpCancel;

  /// No description provided for @reasonSlotTaken.
  ///
  /// In en, this message translates to:
  /// **'That time was taken by someone else. Pick another and try again.'**
  String get reasonSlotTaken;

  /// No description provided for @reasonForbidden.
  ///
  /// In en, this message translates to:
  /// **'Your account cannot do this. Ask the owner.'**
  String get reasonForbidden;

  /// No description provided for @reasonNotCompletable.
  ///
  /// In en, this message translates to:
  /// **'That appointment was already finished or cancelled.'**
  String get reasonNotCompletable;

  /// No description provided for @reasonSalonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The salon cannot accept changes right now.'**
  String get reasonSalonUnavailable;

  /// No description provided for @reasonSalonChanged.
  ///
  /// In en, this message translates to:
  /// **'This was for a salon this phone is no longer signed in to.'**
  String get reasonSalonChanged;

  /// No description provided for @reasonGeneric.
  ///
  /// In en, this message translates to:
  /// **'The server could not accept this.'**
  String get reasonGeneric;

  /// No description provided for @walkInTitle.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get walkInTitle;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get walkInCustomer;

  /// No description provided for @walkInService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get walkInService;

  /// NEVER pre-selected (RULES 9). The label says optional and every box starts empty.
  ///
  /// In en, this message translates to:
  /// **'Add-ons (optional)'**
  String get walkInAddOns;

  /// No description provided for @walkInStaff.
  ///
  /// In en, this message translates to:
  /// **'With'**
  String get walkInStaff;

  /// No description provided for @walkInAnyStaff.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get walkInAnyStaff;

  /// No description provided for @walkInTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get walkInTime;

  /// No description provided for @walkInNoSlots.
  ///
  /// In en, this message translates to:
  /// **'No free times left for that day.'**
  String get walkInNoSlots;

  /// No description provided for @walkInBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get walkInBook;

  /// No description provided for @walkInBooked.
  ///
  /// In en, this message translates to:
  /// **'Booked.'**
  String get walkInBooked;

  /// Capture works offline (RULES 9.1); money and binding never do (9.2).
  ///
  /// In en, this message translates to:
  /// **'Saved. It will book when you are back online.'**
  String get walkInQueuedOffline;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'hi':
      {
        switch (locale.scriptCode) {
          case 'Latn':
            return AppL10nHiLatn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'hi':
      return AppL10nHi();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
