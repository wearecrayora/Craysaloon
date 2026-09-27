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

  @override
  String get joinContinue => 'आगे बढ़ें';

  @override
  String get joinNotThisSalon => 'यह सैलून नहीं? दूसरा कोड डालें';

  @override
  String get joinConfirmBody =>
      'आप इसी सैलून के ग्राहक बनेंगे। आपका खरीदा हुआ क्रेडिट और विज़िट इसी सैलून के साथ रहते हैं, किसी दूसरे सैलून में नहीं जाते।';

  @override
  String get joinSalonUnavailable =>
      'यह सैलून अभी साइन-इन नहीं ले पा रहा है। कृपया काउंटर पर पूछें।';

  @override
  String get joinRateLimited =>
      'बहुत बार कोशिश हो गई। कुछ मिनट रुककर दोबारा कोशिश करें।';

  @override
  String get joinOffline => 'कनेक्शन नहीं है। इंटरनेट देखकर दोबारा कोशिश करें।';

  @override
  String get joinGenericError => 'यह नहीं हो सका। कृपया दोबारा कोशिश करें।';

  @override
  String get phoneHint => '10 अंकों का मोबाइल नंबर';

  @override
  String get phoneServiceNote =>
      'बुकिंग, पेमेंट और रिमाइंडर के मैसेज सेवा का हिस्सा हैं।';

  @override
  String get phoneConsentPromotional => 'इस सैलून के ऑफ़र भी भेजें';

  @override
  String get phoneConsentWhatsapp => 'ऑफ़र WhatsApp पर भी';

  @override
  String get otpResend => 'नया कोड भेजें';

  @override
  String otpExpiresIn(int seconds) {
    return '$seconds सेकंड में खत्म';
  }

  @override
  String get otpExpired => 'यह कोड खत्म हो गया। नया कोड भेजें।';

  @override
  String otpWrongCode(String attempts) {
    return 'यह कोड मैच नहीं हुआ। $attempts बची हैं।';
  }

  @override
  String get otpAccountConflict =>
      'हम आपको साइन इन नहीं कर सके। कृपया सैलून से संपर्क करें।';

  @override
  String joinedTitle(String salonName) {
    return '$salonName में आपका स्वागत है';
  }

  @override
  String get joinedBody => 'अब आप इस सैलून के ग्राहक हैं।';

  @override
  String get joinedStaff => 'आप अपने सैलून में साइन इन हैं।';

  @override
  String get joinStart => 'मेरा कोड भेजें';

  @override
  String get homeReady => 'बुकिंग, क्रेडिट और रिमाइंडर यहीं आएंगे।';

  @override
  String shortcutTitle(String salonName) {
    return '$salonName को होम स्क्रीन पर जोड़ें';
  }

  @override
  String get shortcutBody =>
      'एक टैप में अपना सैलून खोलें। आपका फ़ोन पुष्टि करने के लिए पूछेगा।';

  @override
  String get shortcutAdd => 'होम स्क्रीन पर जोड़ें';

  @override
  String get shortcutNotNow => 'अभी नहीं';

  @override
  String get shortcutAdded => 'जुड़ गया। होम स्क्रीन पर देखिए।';

  @override
  String get scanHint => 'कैमरे को सैलॉन के QR कोड पर रखें';

  @override
  String get scanCameraUnavailable =>
      'कैमरा उपलब्ध नहीं है। आप सैलॉन कोड हाथ से भी डाल सकते हैं।';

  @override
  String get joinScanButton => 'QR कोड स्कैन करें';
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

  @override
  String get joinContinue => 'Aage badhein';

  @override
  String get joinNotThisSalon => 'Yeh salon nahi? Dusra code daaliye';

  @override
  String get joinConfirmBody =>
      'Aap isi salon ke customer banenge. Aapka khareeda hua credit aur visits isi salon ke saath rehte hain, kisi dusre salon mein nahi jaate.';

  @override
  String get joinSalonUnavailable =>
      'Yeh salon abhi sign-in nahi le pa raha hai. Counter par poochh lijiye.';

  @override
  String get joinRateLimited =>
      'Bahut baar koshish ho gayi. Kuch minute ruk kar dobara try kijiye.';

  @override
  String get joinOffline =>
      'Connection nahi hai. Internet check karke dobara try kijiye.';

  @override
  String get joinGenericError => 'Yeh nahi ho saka. Dobara try kijiye.';

  @override
  String get phoneHint => '10 digit ka mobile number';

  @override
  String get phoneServiceNote =>
      'Booking, payment aur reminder ke message service ka hissa hain.';

  @override
  String get phoneConsentPromotional => 'Is salon ke offers bhi bhejiye';

  @override
  String get phoneConsentWhatsapp => 'Offers WhatsApp par bhi';

  @override
  String get otpResend => 'Naya code bhejiye';

  @override
  String otpExpiresIn(int seconds) {
    return '$seconds second mein khatam';
  }

  @override
  String get otpExpired => 'Yeh code khatam ho gaya. Naya code bhejiye.';

  @override
  String otpWrongCode(String attempts) {
    return 'Yeh code match nahi hua. $attempts bachi hain.';
  }

  @override
  String get otpAccountConflict =>
      'Hum aapko sign in nahi kar sake. Salon se contact kijiye.';

  @override
  String joinedTitle(String salonName) {
    return '$salonName mein aapka swagat hai';
  }

  @override
  String get joinedBody => 'Ab aap is salon ke customer hain.';

  @override
  String get joinedStaff => 'Aap apne salon mein sign in hain.';

  @override
  String get joinStart => 'Mera code bhejiye';

  @override
  String get homeReady => 'Booking, credit aur reminder yahin aayenge.';

  @override
  String shortcutTitle(String salonName) {
    return '$salonName ko home screen par add kijiye';
  }

  @override
  String get shortcutBody =>
      'Ek tap mein apna salon kholiye. Aapka phone confirm karne ke liye poochhega.';

  @override
  String get shortcutAdd => 'Home screen par add kijiye';

  @override
  String get shortcutNotNow => 'Abhi nahi';

  @override
  String get shortcutAdded => 'Add ho gaya. Home screen par dekhiye.';

  @override
  String get scanHint => 'Camera ko salon ke QR code par rakhiye';

  @override
  String get scanCameraUnavailable =>
      'Camera available nahi hai. Aap salon code haath se bhi daal sakte hain.';

  @override
  String get joinScanButton => 'QR code scan kijiye';
}
