// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppL10nHi extends AppL10n {
  AppL10nHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'क्रे सैलॉन';

  @override
  String get joinTitle => 'अपना सैलॉन खोजें';

  @override
  String get joinScanQr => 'सैलॉन का QR कोड स्कैन करें';

  @override
  String get joinEnterCode => 'या सैलॉन कोड डालें';

  @override
  String get joinCodeHint => 'CRAY-XXXXXX';

  @override
  String joinConfirmTitle(String salonName) {
    return 'आप $salonName से जुड़ रहे हैं';
  }

  @override
  String get joinCodeInvalid =>
      'यह कोड किसी सैलॉन से मेल नहीं खाया। जाँच कर दोबारा कोशिश करें।';

  @override
  String get joinAlreadyBound => 'यह नंबर पहले से एक सैलॉन में रजिस्टर्ड है।';

  @override
  String get phoneTitle => 'आपका मोबाइल नंबर';

  @override
  String get otpTitle => '6 अंकों का कोड डालें';

  @override
  String otpSentTo(String phone) {
    return '$phone पर भेजा गया';
  }

  @override
  String get walletBalance => 'उपलब्ध क्रेडिट';

  @override
  String walletOnlyAtSalon(String salonName) {
    return 'केवल $salonName में उपयोग योग्य। नकद नहीं निकाला जा सकता।';
  }

  @override
  String get addMoneyPaidNeverExpires =>
      'आपके द्वारा भुगतान किया गया पैसा कभी समाप्त नहीं होता।';

  @override
  String addMoneyBonusExpires(String bonus, String date) {
    return 'आपका $bonus बोनस $date को समाप्त होगा।';
  }

  @override
  String get markComplete => 'पूरा हुआ';

  @override
  String get needsAttention => 'ध्यान देने की ज़रूरत';

  @override
  String get offlineBanner =>
      'आप ऑफ़लाइन हैं। आपके बदलाव सहेज लिए गए हैं और सिंक हो जाएंगे।';

  @override
  String get retry => 'दोबारा कोशिश करें';
}

/// The translations for Hindi, using the Latin script (`hi_Latn`).
class AppL10nHiLatn extends AppL10nHi {
  AppL10nHiLatn() : super('hi_Latn');

  @override
  String get appTitle => 'Cray Salon';

  @override
  String get joinTitle => 'Apna salon dhundhein';

  @override
  String get joinScanQr => 'Salon ka QR code scan kijiye';

  @override
  String get joinEnterCode => 'Ya salon code daaliye';

  @override
  String get joinCodeHint => 'CRAY-XXXXXX';

  @override
  String joinConfirmTitle(String salonName) {
    return 'Aap $salonName se jud rahe hain';
  }

  @override
  String get joinCodeInvalid =>
      'Yeh code kisi salon se match nahi hua. Check karke dobara try kijiye.';

  @override
  String get joinAlreadyBound =>
      'Yeh number pehle se ek salon mein registered hai.';

  @override
  String get phoneTitle => 'Aapka mobile number';

  @override
  String get otpTitle => '6 digit ka code daaliye';

  @override
  String otpSentTo(String phone) {
    return '$phone par bheja gaya';
  }

  @override
  String get walletBalance => 'Available credit';

  @override
  String walletOnlyAtSalon(String salonName) {
    return 'Sirf $salonName mein use kar sakte hain. Cash nahi nikal sakte.';
  }

  @override
  String get addMoneyPaidNeverExpires =>
      'Aapka paid paisa kabhi expire nahi hota.';

  @override
  String addMoneyBonusExpires(String bonus, String date) {
    return 'Aapka $bonus bonus $date ko expire hoga.';
  }

  @override
  String get markComplete => 'Complete karein';

  @override
  String get needsAttention => 'Dhyan dijiye';

  @override
  String get offlineBanner =>
      'Aap offline hain. Aapke changes save ho gaye hain, sync ho jayenge.';

  @override
  String get retry => 'Dobara try kijiye';
}
