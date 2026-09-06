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
