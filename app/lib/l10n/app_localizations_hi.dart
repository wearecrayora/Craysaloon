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

  @override
  String get customersTitle => 'ग्राहक';

  @override
  String get customersSearchHint => 'नाम, या पूरा मोबाइल नंबर';

  @override
  String get customersEmpty =>
      'अभी कोई ग्राहक नहीं। वे आपका QR कोड स्कैन करके जुड़ते हैं।';

  @override
  String get customersNoMatch =>
      'कोई मैच नहीं मिला। पूरा नंबर डालें, या कम अक्षर।';

  @override
  String get customerNeverVisited => 'अभी तक नहीं आए';

  @override
  String customerLastVisit(String date) {
    return 'पिछली विज़िट $date';
  }

  @override
  String customerVisits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count विज़िट',
      one: '1 विज़िट',
      zero: 'कोई विज़िट नहीं',
    );
    return '$_temp0';
  }

  @override
  String customerLoyalty(String points) {
    return '$points पॉइंट';
  }

  @override
  String cachedAsOf(String time) {
    return 'इस डिवाइस से दिखाया गया, आखिरी अपडेट $time।';
  }

  @override
  String get cachedNeverLoaded =>
      'अभी लोड नहीं हुआ। एक बार कनेक्ट करके अपने ग्राहक देखें।';

  @override
  String get loadMore => 'और दिखाएं';

  @override
  String get catalogueServices => 'सेवाएं';

  @override
  String get catalogueAddOns => 'ऐड-ऑन';

  @override
  String get staffTitle => 'टीम';

  @override
  String get catalogueEmpty =>
      'अभी यहां कुछ नहीं। Crayora आपके साथ इसे सेट करता है।';

  @override
  String get inactiveLabel => 'छिपा हुआ';

  @override
  String minutesShort(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String addsMinutes(int minutes) {
    return '$minutes मिनट बढ़ाता है';
  }

  @override
  String get dayViewSoon => 'दिन का व्यू बुकिंग के साथ आएगा।';

  @override
  String get balanceReadOnly =>
      'बैलेंस टॉप-अप और विज़िट से बनता है। इसे यहां बदला नहीं जा सकता।';

  @override
  String get catalogueAdd => 'जोड़ें';

  @override
  String get serviceFormTitle => 'सेवा';

  @override
  String get addOnFormTitle => 'ऐड-ऑन';

  @override
  String get staffFormTitle => 'टीम सदस्य';

  @override
  String get fieldName => 'नाम';

  @override
  String get fieldPrice => 'दाम (₹)';

  @override
  String get fieldDuration => 'मिनट';

  @override
  String get fieldExtraMinutes => 'अतिरिक्त मिनट';

  @override
  String get fieldVisible => 'ग्राहक इसे देख सकते हैं';

  @override
  String get actionSave => 'सेव करें';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get formNameRequired => 'नाम ज़रूरी है - ग्राहक इसे देखते हैं।';

  @override
  String get formPriceInvalid => 'दाम रुपये में डालें, जैसे 400 या 400.50।';

  @override
  String get formDurationInvalid => 'मिनट 5 से 600 के बीच डालें।';

  @override
  String get saveFailedOffline =>
      'सेव नहीं हुआ। कैटलॉग बदलने के लिए कनेक्शन ज़रूरी है।';

  @override
  String get saveFailedRefused =>
      'आपका अकाउंट कैटलॉग नहीं बदल सकता। मालिक से कहें।';

  @override
  String get saveFailed => 'सेव नहीं हुआ। दोबारा कोशिश करें।';

  @override
  String get dayTitle => 'आज';

  @override
  String get dayEmpty => 'आज कोई बुकिंग नहीं।';

  @override
  String get dayDone => 'हो गया';

  @override
  String get dayCancelled => 'रद्द';

  @override
  String daySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदलाव सिंक होने बाकी',
      one: '1 बदलाव सिंक होना बाकी',
    );
    return '$_temp0';
  }

  @override
  String get dayCancelBooking => 'अपॉइंटमेंट रद्द करें';

  @override
  String get attentionEmpty => 'कुछ भी ध्यान देने लायक नहीं।';

  @override
  String get attentionDiscard => 'हटा दें';

  @override
  String get attentionOpComplete => 'पूरा करें';

  @override
  String get attentionOpBooking => 'नई बुकिंग';

  @override
  String get attentionOpCancel => 'रद्दीकरण';

  @override
  String get reasonSlotTaken =>
      'वह समय किसी और ने ले लिया। दूसरा समय चुनकर कोशिश करें।';

  @override
  String get reasonForbidden => 'आपका अकाउंट यह नहीं कर सकता। मालिक से कहें।';

  @override
  String get reasonNotCompletable =>
      'वह अपॉइंटमेंट पहले ही पूरा या रद्द हो चुका है।';

  @override
  String get reasonSalonUnavailable => 'सैलॉन अभी बदलाव नहीं ले पा रहा है।';

  @override
  String get reasonSalonChanged =>
      'यह उस सैलॉन के लिए था जिसमें यह फ़ोन अब साइन इन नहीं है।';

  @override
  String get reasonGeneric => 'सर्वर इसे स्वीकार नहीं कर सका।';

  @override
  String get walkInTitle => 'वॉक-इन';

  @override
  String get walkInCustomer => 'ग्राहक';

  @override
  String get walkInService => 'सेवा';

  @override
  String get walkInAddOns => 'ऐड-ऑन (वैकल्पिक)';

  @override
  String get walkInStaff => 'किसके साथ';

  @override
  String get walkInAnyStaff => 'कोई भी';

  @override
  String get walkInTime => 'समय';

  @override
  String get walkInNoSlots => 'उस दिन के लिए कोई खाली समय नहीं।';

  @override
  String get walkInBook => 'बुक करें';

  @override
  String get walkInBooked => 'बुक हो गया।';

  @override
  String get walkInQueuedOffline => 'सेव हो गया। ऑनलाइन आते ही बुक हो जाएगा।';

  @override
  String noticeHeading(String salonName) {
    return '$salonName आपके बारे में क्या जानेगा';
  }

  @override
  String get noticeItemPhone =>
      'आपका मोबाइल नंबर — लॉगिन कोड भेजने के लिए, और बुकिंग के बारे में संपर्क करने के लिए।';

  @override
  String get noticeItemVisits =>
      'आपका नाम और आपकी विज़िट — ताकि आपका इतिहास, बैलेंस और पॉइंट सही रहें।';

  @override
  String get noticeItemOptional =>
      'जन्मदिन और फ़ोटो वैकल्पिक हैं, अलग से पूछे जाते हैं, और आपकी हाँ के बिना बंद रहते हैं।';

  @override
  String noticeFiduciary(String salonName) {
    return '$salonName तय करता है कि क्या रखा जाए और क्यों। Crayora ऐप बनाता है और उनके लिए डेटा रखता है।';
  }

  @override
  String get noticeControl =>
      'आप कभी भी सहमति वापस ले सकते हैं, अपने डेटा की कॉपी माँग सकते हैं, या मिटाने के लिए कह सकते हैं — “आपका डेटा” में।';

  @override
  String get noticeContactHeading => 'सवाल या शिकायत';

  @override
  String get noticeContactNone =>
      'सैलून के काउंटर पर पूछें। जवाब न मिले तो Crayora को लिखें।';

  @override
  String get noticePolicyLink => 'पूरी प्राइवेसी पॉलिसी पढ़ें';

  @override
  String get noticeLinkFailed =>
      'इस फ़ोन में इसे खोलने वाला कुछ नहीं है। पता ऊपर लिखा है।';

  @override
  String get yourDataTitle => 'आपका डेटा';

  @override
  String get yourDataConsentsHeading => 'आपने किन बातों के लिए हाँ कहा है';

  @override
  String get yourDataRightsHeading => 'आपके अधिकार';

  @override
  String get yourDataFiduciaryHeading => 'आपका डेटा किसके पास है';

  @override
  String get consentServiceTitle => 'बुकिंग और पेमेंट के मैसेज';

  @override
  String get consentServiceLocked =>
      'यह सेवा का हिस्सा है। इन्हें रोकने के लिए अपना खाता मिटाने के लिए कहें।';

  @override
  String get consentPromotionalTitle => 'इस सैलून के ऑफ़र';

  @override
  String get consentWhatsappTitle => 'WhatsApp पर ऑफ़र';

  @override
  String get consentPhotosTitle => 'पहले और बाद की फ़ोटो';

  @override
  String get consentPhotosSubtitle =>
      'ताकि सैलून आपको दिखा सके कि पिछली बार क्या किया गया था।';

  @override
  String get consentSaveFailed =>
      'यह सेव नहीं हुआ। कनेक्शन देखकर फिर कोशिश करें।';

  @override
  String get rightAccessTitle => 'मेरे डेटा की कॉपी माँगें';

  @override
  String get rightErasureTitle => 'मेरा खाता मिटाने के लिए कहें';

  @override
  String get rightGrievanceTitle => 'अपने डेटा को लेकर शिकायत दर्ज करें';

  @override
  String rightAsked(String asked, String due) {
    return '$asked को माँगा। जवाब $due तक आना चाहिए।';
  }

  @override
  String rightAnswered(String outcome) {
    return 'जवाब: $outcome';
  }

  @override
  String get rightAskedThanks =>
      'माँग दर्ज हो गई। सैलून के पास जवाब देने के लिए 30 दिन हैं।';

  @override
  String get erasureConfirmTitle => 'खाता मिटाने के लिए कहें?';

  @override
  String get erasureConfirmBody =>
      'आपका नाम, नंबर और जन्मदिन हटा दिए जाएंगे और आप लॉग आउट हो जाएंगे। पेमेंट और वॉलेट के रिकॉर्ड आपके नाम के बिना रहेंगे — सैलून को कानूनन अपने हिसाब-किताब रखने होते हैं। यह वापस नहीं हो सकता।';

  @override
  String get erasureConfirmAction => 'हाँ, मिटाने के लिए कहें';

  @override
  String get walletTitle => 'वॉलेट';

  @override
  String get walletPaidLabel => 'भुगतान किया हुआ बैलेंस';

  @override
  String get walletBonusLabel => 'बोनस बैलेंस';

  @override
  String walletBonusExpiryNote(String amount, String date) {
    return '$amount बोनस $date को समाप्त हो जाएगा।';
  }

  @override
  String get walletAddMoney => 'पैसे जोड़ें';

  @override
  String get walletHistoryHeading => 'हाल की गतिविधि';

  @override
  String get walletHistoryEmpty =>
      'अभी कुछ नहीं। आप जो पैसे जोड़ेंगे और यहाँ खर्च करेंगे, वह इस सूची में दिखेगा।';

  @override
  String get entryTopUp => 'पैसे जोड़े गए';

  @override
  String get entryBonus => 'बोनस';

  @override
  String get entrySpend => 'सैलून में उपयोग हुआ';

  @override
  String get entryExpiry => 'बोनस समाप्त हुआ';

  @override
  String get entryReversal => 'वापस किया गया';

  @override
  String get entryReferral => 'रेफरल इनाम';

  @override
  String get entryCorrection => 'सुधार';

  @override
  String get addMoneyTitle => 'पैसे जोड़ें';

  @override
  String get addMoneyAmount => 'राशि';

  @override
  String addMoneyBonusYouGet(String bonus) {
    return 'आपको $bonus अतिरिक्त मिलेंगे।';
  }

  @override
  String get addMoneyNoBonus => 'इस राशि पर कोई बोनस नहीं।';

  @override
  String get addMoneyNotRefundable =>
      'जोड़े गए पैसे वापस नहीं होते और नकद नहीं निकाले जा सकते।';

  @override
  String get addMoneyDisclosureHeading => 'भुगतान से पहले';

  @override
  String addMoneyPay(String amount) {
    return '$amount का भुगतान करें';
  }

  @override
  String addMoneyBelowMinimum(String min) {
    return 'यहाँ कम से कम $min जोड़े जा सकते हैं।';
  }

  @override
  String get addMoneyInvalid => 'जोड़ने के लिए राशि डालें।';

  @override
  String get addMoneyUnavailable =>
      'यह सैलून अभी भुगतान नहीं ले सकता। काउंटर पर पूछें।';

  @override
  String get addMoneyCheckoutNotReady =>
      'इस वर्ज़н में ऐप से भुगतान अभी चालू नहीं है। आपके पैसे नहीं कटे हैं।';

  @override
  String get addMoneySubmitted =>
      'भुगतान भेज दिया गया। बैंक की पुष्टि होते ही आपका बैलेंस दिखेगा।';

  @override
  String get addMoneyCancelled => 'भुगतान रद्द हुआ। कुछ नहीं कटा।';

  @override
  String get addMoneyFailed => 'यह भुगतान पूरा नहीं हुआ। कुछ नहीं कटा।';

  @override
  String get referTitle => 'रेफ़र करें, कमाएँ';

  @override
  String referHeadline(String referred, String referrer) {
    return '$referred दिलाएँ, $referrer पाएँ';
  }

  @override
  String referHowItWorks(String salonName) {
    return 'अपना कोड शेयर करें। जब आपका दोस्त $salonName से जुड़कर अपनी पहली विज़िट का भुगतान कर लेगा, तब दोनों को वॉलेट में क्रेडिट मिलेगा।';
  }

  @override
  String get referYourCode => 'आपका कोड';

  @override
  String get referCopy => 'कॉपी करें';

  @override
  String get referCopied => 'कॉपी हो गया';

  @override
  String get referShare => 'शेयर करें';

  @override
  String referWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दोस्त जुड़े हैं, अभी आए नहीं',
      one: '1 दोस्त जुड़ा है, अभी आया नहीं',
      zero: 'कोई पहली विज़िट के इंतज़ार में नहीं',
    );
    return '$_temp0';
  }

  @override
  String get referEarnedNone => 'अभी कुछ नहीं कमाया।';

  @override
  String referEarned(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दोस्त आ चुके हैं। आपने $amount कमाए।',
      one: '1 दोस्त आ चुका है। आपने $amount कमाए।',
    );
    return '$_temp0';
  }

  @override
  String referNotCash(String salonName) {
    return 'रेफ़रल क्रेडिट केवल $salonName में उपयोग होता है और नकद नहीं निकाला जा सकता।';
  }

  @override
  String get referClaimTitle => 'क्या आपको किसी ने बुलाया है?';

  @override
  String get referClaimHint => 'दोस्त का कोड डालें';

  @override
  String get referClaimAction => 'कोड लगाएँ';

  @override
  String get referClaimed =>
      'कोड लग गया। पहली भुगतान की गई विज़िट के बाद दोनों को क्रेडिट मिलेगा।';

  @override
  String get referClaimUnknown => 'यह कोड इस सैलून का नहीं है।';

  @override
  String get referClaimSelf => 'यह आपका अपना कोड है।';

  @override
  String get referClaimAlready =>
      'आपके खाते पर पहले से एक दोस्त का कोड लगा है।';

  @override
  String get referClaimNotNew =>
      'रेफ़रल कोड पहली विज़िट के लिए होते हैं, और आप पहले आ चुके हैं।';

  @override
  String get dashTitle => 'डैशबोर्ड';

  @override
  String get dashToday => 'आज';

  @override
  String get dashRevenue => 'कमाई';

  @override
  String get dashCompleted => 'पूरी विज़िट';

  @override
  String get dashAvgBill => 'औसत बिल';

  @override
  String get dashNoAverage => '—';

  @override
  String get dashBookings => 'बुकिंग';

  @override
  String dashCancelledNoShow(int cancelled, int noShow) {
    return '$cancelled रद्द · $noShow नहीं आए';
  }

  @override
  String get dashThisMonth => 'इस महीने';

  @override
  String get dashNewRepeat => 'नए / लौटे';

  @override
  String get dashWalletCollected => 'वॉलेट टॉप-अप';

  @override
  String get dashOutstanding => 'ग्राहकों के पास क्रेडिट';

  @override
  String get dashOutstandingNote =>
      'केवल दिखाया जाता है, बदला नहीं जा सकता। बैलेंस केवल टॉप-अप और विज़िट से बदलता है।';

  @override
  String get dashBinds => 'नए ग्राहक जुड़े';

  @override
  String get dashMessagingTitle => 'रिमाइंडर: खर्च और नतीजा';

  @override
  String get dashSpend => 'मैसेज पर खर्च';

  @override
  String dashRemindersSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count रिमाइंडर भेजे',
      one: '1 रिमाइंडर भेजा',
    );
    return '$_temp0';
  }

  @override
  String dashReminderBookings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'रिमाइंडर से $count बुकिंग',
      one: 'रिमाइंडर से 1 बुकिंग',
    );
    return '$_temp0';
  }

  @override
  String dashPushSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मैसेज ऐप नोटिफिकेशन से मुफ़्त गए',
      one: '1 मैसेज ऐप नोटिफिकेशन से मुफ़्त गया',
    );
    return '$_temp0';
  }

  @override
  String get dashCohortTitle => 'क्या ग्राहक लौटते हैं?';

  @override
  String get dashCohortAxis => '% जो लौटे';

  @override
  String get dashCohortWallet => 'वॉलेट वाले';

  @override
  String get dashCohortNoWallet => 'बिना वॉलेट';

  @override
  String dashCohortWithin(int days) {
    return '$days दिन में';
  }

  @override
  String get dashCohortNotYet => 'अभी नहीं';

  @override
  String dashCohortN(int n) {
    return 'n = $n';
  }

  @override
  String get dashCohortEmpty => 'पहली विज़िट के बाद यहाँ समूह दिखेंगे।';

  @override
  String get dashCohortTable => 'यही आँकड़े';

  @override
  String get dashCohortMonth => 'जुड़े';

  @override
  String get dashCohortGroup => 'समूह';

  @override
  String get dashDrift =>
      'कुछ पुराने आँकड़े रिकॉर्ड से मेल नहीं खाते और उनकी जाँच हो रही है।';

  @override
  String get payTake => 'भुगतान लें';

  @override
  String get payPaid => 'भुगतान हो गया';

  @override
  String get payPartial => 'आंशिक भुगतान';

  @override
  String get paySheetTitle => 'भुगतान लें';

  @override
  String get payUseWallet => 'पहले ग्राहक का वॉलेट इस्तेमाल करें';

  @override
  String paySplit(String wallet, String counter) {
    return 'वॉलेट से $wallet। $counter लें।';
  }

  @override
  String payCollectAll(String amount) {
    return '$amount लें।';
  }

  @override
  String get payNoQuote =>
      'कनेक्शन नहीं है, इसलिए वॉलेट बैलेंस जाँचा नहीं जा सकता। पूरी राशि लें, या वॉलेट के लिए ऑनलाइन होने तक रुकें।';

  @override
  String get payMethod => 'बाकी भुगतान';

  @override
  String get payCash => 'नकद';

  @override
  String get payUpi => 'UPI';

  @override
  String get payCard => 'कार्ड';

  @override
  String get payRecord => 'भुगतान दर्ज करें';

  @override
  String get payQueued =>
      'भुगतान दर्ज हो गया। सर्वर तक पहुँचने पर यह भुगतान हुआ दिखेगा।';

  @override
  String get startTitle => 'शुरू करें';

  @override
  String get startAskForCode => 'ग्राहक से उनके ऐप का 4 अंकों वाला कोड माँगें।';

  @override
  String get startWithCode => 'इस कोड से शुरू करें';

  @override
  String startWrongCode(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'यह उनका कोड नहीं है। $count कोशिशें बाकी।',
      one: 'यह उनका कोड नहीं है। 1 कोशिश बाकी।',
    );
    return '$_temp0';
  }

  @override
  String get startLocked =>
      'बहुत गलत कोशिशें हुईं, इसलिए कोड बंद है। बिना कोड शुरू करें - मालिक को कारण दिखेगा।';

  @override
  String get startNoCodeIssued =>
      'उन्होंने ऐप में यह बुकिंग अभी नहीं खोली, इसलिए कोड नहीं है। खोलने को कहें, या बिना कोड शुरू करें।';

  @override
  String get startNotStartable =>
      'यह बुकिंग शुरू नहीं हो सकती - यह पूरी या रद्द हो चुकी है।';

  @override
  String get startOffline =>
      'कनेक्शन नहीं है, इसलिए कोड जाँचा नहीं जा सकता। बिना कोड शुरू कर सकते हैं - मालिक को कारण दिखेगा।';

  @override
  String get startNoAppExplained =>
      'इस ग्राहक के पास ऐप नहीं है, इसलिए कोड नहीं है। बिना कोड शुरू करें - मालिक को दिखेगा।';

  @override
  String get startWithoutExplained =>
      'बिना कोड शुरू करना ठीक है। यह कारण के साथ मालिक के लिए दर्ज होता है।';

  @override
  String get startWithoutCode => 'बिना कोड शुरू करें';

  @override
  String get dayInProgress => 'चल रहा है';

  @override
  String get payCounterRequested => 'काउंटर पर भुगतान';

  @override
  String get visitToday => 'आज की आपकी विज़िट';

  @override
  String get visitInProgress => 'आपकी सर्विस चल रही है।';

  @override
  String get visitShowCode => 'बैठने पर यह कोड अपने स्टाइलिस्ट को दिखाएँ।';

  @override
  String visitCodeSemantics(String digits) {
    return 'आपका शुरुआती कोड: $digits';
  }

  @override
  String get billReady => 'आपका बिल तैयार है';

  @override
  String get billCounterSaid => 'आपने काउंटर पर भुगतान करने को कहा है।';

  @override
  String get billPay => 'बिल भरें';

  @override
  String billToPay(String amount) {
    return 'भुगतान: $amount';
  }

  @override
  String get payHowTitle => 'आप भुगतान कैसे करना चाहेंगे?';

  @override
  String get payOptWallet => 'वॉलेट';

  @override
  String payOptWalletAll(String amount, String balance) {
    return 'अपने $balance के बैलेंस से $amount भरें।';
  }

  @override
  String payOptWalletPart(String wallet, String rest) {
    return 'वॉलेट के पूरे $wallet इस्तेमाल करें, फिर बाकी $rest UPI से या काउंटर पर भरें।';
  }

  @override
  String payWalletBreakdown(String paid, String bonus) {
    return 'इसमें $paid आपके जमा किए हुए और $bonus बोनस है।';
  }

  @override
  String get payOptUpi => 'UPI';

  @override
  String payOptUpiBody(String amount) {
    return 'किसी भी UPI ऐप से $amount भरें।';
  }

  @override
  String get payOptCounter => 'काउंटर पर';

  @override
  String payOptCounterBody(String amount) {
    return 'रिसेप्शन पर नकद या कार्ड से $amount भरें।';
  }

  @override
  String payRestTitle(String amount) {
    return '$amount भरना बाकी है';
  }

  @override
  String get payRestHow =>
      'आपका वॉलेट इस्तेमाल हो गया। बाकी का भुगतान कैसे करना चाहेंगे?';

  @override
  String get billingReadOnlyTitle => 'अभी सिर्फ़ देखा जा सकता है';

  @override
  String billingReadOnlyGrace(String date) {
    return 'आपकी सदस्यता का भुगतान बाकी है, इसलिए अभी कुछ नया दर्ज नहीं हो सकता - न बुकिंग, न शुरुआत, न भुगतान। सब कुछ देखा जा सकता है। निलंबन से बचने के लिए $date से पहले Crayora को भुगतान करें।';
  }

  @override
  String get billingReadOnlySuspended =>
      'आपकी सदस्यता निलंबित है, इसलिए कुछ नया दर्ज नहीं हो सकता। कुछ भी मिटाया नहीं गया है। भुगतान करके आगे बढ़ने के लिए Crayora से संपर्क करें।';

  @override
  String get billingReadOnlyStaff =>
      'सैलून अभी कुछ नया दर्ज नहीं कर सकता - न बुकिंग, न शुरुआत, न भुगतान। मालिक इसे सुलझा रहे हैं।';

  @override
  String get billingReadOnlyOther =>
      'यह सैलून अभी बदलाव दर्ज नहीं कर सकता। Crayora से संपर्क करें।';

  @override
  String get billAlreadyPaid => 'यह बिल पहले से भरा है।';

  @override
  String get billPaidFromWallet => 'वॉलेट से भुगतान हो गया।';

  @override
  String get billUpiSent =>
      'भुगतान भेज दिया गया। बैंक की पुष्टि होते ही बिल भरा हुआ दिखेगा।';

  @override
  String get billCounterTold =>
      'काउंटर को पता है। पैसे लेने पर आपका बिल भरा हुआ दिखेगा।';

  @override
  String get navHome => 'होम';

  @override
  String get navBook => 'बुक करें';

  @override
  String get navMe => 'मैं';

  @override
  String homeGreeting(String name) {
    return 'नमस्ते $name';
  }

  @override
  String get homeGreetingNoName => 'फिर से स्वागत है';

  @override
  String homeNextDueService(String service, String date) {
    return 'आपकी अगली $service लगभग $date को होनी है';
  }

  @override
  String homeNextDue(String date) {
    return 'आपकी अगली विज़िट लगभग $date को है';
  }

  @override
  String get homeBookNow => 'अभी बुक करें';

  @override
  String get homeNextBooking => 'आपकी अगली बुकिंग';

  @override
  String get homeWalletUnavailable =>
      'आपका बैलेंस लोड नहीं हो सका। दोबारा कोशिश के लिए नीचे खींचें।';

  @override
  String get walletView => 'वॉलेट देखें';

  @override
  String get referSubtitle => 'दोस्त को बुलाएँ, दोनों को क्रेडिट';

  @override
  String bookStep(int step, int total) {
    return 'चरण $step / $total';
  }

  @override
  String get bookChooseService => 'सेवा चुनें';

  @override
  String get bookOther => 'अन्य';

  @override
  String get bookNoServices => 'अभी बुकिंग के लिए कोई सेवा उपलब्ध नहीं है।';

  @override
  String get bookAddOnsTitle => 'कुछ और जोड़ें?';

  @override
  String get bookAddOnsHint => 'वैकल्पिक। जब तक आप न चुनें, कुछ नहीं जुड़ता।';

  @override
  String get bookStylistTime => 'स्टाइलिस्ट और समय';

  @override
  String get bookStylist => 'स्टाइलिस्ट';

  @override
  String get bookAnyone => 'कोई भी';

  @override
  String get bookDate => 'तारीख';

  @override
  String get bookNoTimes => 'इस दिन कोई समय खाली नहीं है।';

  @override
  String get bookTimesFailed =>
      'खाली समय लोड नहीं हो सके। अपना कनेक्शन जाँचें।';

  @override
  String get bookTotal => 'कुल';

  @override
  String bookMinutes(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String get bookContinue => 'आगे बढ़ें';

  @override
  String get bookReview => 'अपनी बुकिंग जाँचें';

  @override
  String get bookService => 'सेवा';

  @override
  String get bookAddOns => 'ऐड-ऑन';

  @override
  String get bookNone => 'कोई नहीं';

  @override
  String get bookDateTime => 'तारीख और समय';

  @override
  String get bookTakesAbout => 'लगभग समय';

  @override
  String get bookPayAfter => 'भुगतान विज़िट के बाद - वॉलेट, UPI या काउंटर पर।';

  @override
  String get bookChangeHint =>
      'शुरू होने तक आप यह बुकिंग ऐप में रद्द कर सकते हैं।';

  @override
  String get bookConfirm => 'बुकिंग पक्की करें';

  @override
  String get bookSlotTaken =>
      'यह समय अभी-अभी किसी और ने ले लिया। कृपया दूसरा चुनें।';

  @override
  String get bookFailed => 'बुकिंग नहीं हो सकी। कनेक्शन जाँचकर फिर कोशिश करें।';

  @override
  String bookDone(String date) {
    return 'बुक हो गया। $date को मिलते हैं।';
  }

  @override
  String get bookingTitle => 'आपकी बुकिंग';

  @override
  String get bookingBooked => 'बुक है';

  @override
  String get bookingInProgress => 'सेवा जारी है';

  @override
  String get bookingCancelledStatus => 'रद्द';

  @override
  String get bookingCancel => 'बुकिंग रद्द करें';

  @override
  String get bookingCancelAsk => 'यह बुकिंग रद्द करें?';

  @override
  String get bookingCancelBody =>
      'समय सैलून को वापस मिल जाएगा। कुछ भुगतान नहीं हुआ है, इसलिए कुछ लौटाना नहीं है।';

  @override
  String get bookingKeep => 'रहने दें';

  @override
  String get bookingCancelled => 'बुकिंग रद्द हो गई।';

  @override
  String get bookingCancelFailed =>
      'रद्द नहीं हो सकी। कनेक्शन जाँचकर फिर कोशिश करें।';

  @override
  String get bookingNotFound => 'यह बुकिंग नहीं मिली।';

  @override
  String withStylist(String name) {
    return '$name के साथ';
  }

  @override
  String get historyTitle => 'विज़िट इतिहास';

  @override
  String get historyEmpty => 'अभी तक कोई विज़िट नहीं। पहली विज़िट यहाँ दिखेगी।';

  @override
  String get historyPaid => 'भुगतान हो गया';

  @override
  String get historyUnpaid => 'अभी भुगतान नहीं हुआ';

  @override
  String get historyFailed => 'आपकी विज़िट लोड नहीं हो सकीं।';

  @override
  String get meTitle => 'मैं';

  @override
  String get meName => 'नाम';

  @override
  String get mePhone => 'फ़ोन';

  @override
  String get meLanguage => 'भाषा';

  @override
  String get meHistorySub => 'आपने क्या करवाया, और कब';

  @override
  String get meYourDataSub => 'कॉपी, मिटाना, और किससे पूछें';

  @override
  String get meAppBy => 'ऐप: Crayora';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageHinglish => 'Hinglish';

  @override
  String get bookingMissed => 'छूट गई';

  @override
  String get homeFirstVisit => 'अपनी पहली विज़िट बुक करें';

  @override
  String get joinIntro =>
      'जुड़ते ही आपके सैलून का ऐप खुल जाएगा। कोड काउंटर पर रखे कार्ड पर है।';

  @override
  String get homeBookAgain => 'अपनी अगली विज़िट बुक करें';
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

  @override
  String get customersTitle => 'Customers';

  @override
  String get customersSearchHint => 'Naam, ya poora mobile number';

  @override
  String get customersEmpty =>
      'Abhi koi customer nahi. Wo aapka QR code scan karke judte hain.';

  @override
  String get customersNoMatch =>
      'Koi match nahi mila. Poora number daaliye, ya kam letters.';

  @override
  String get customerNeverVisited => 'Abhi tak nahi aaye';

  @override
  String customerLastVisit(String date) {
    return 'Pichhli visit $date';
  }

  @override
  String customerVisits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visits',
      one: '1 visit',
      zero: 'Koi visit nahi',
    );
    return '$_temp0';
  }

  @override
  String customerLoyalty(String points) {
    return '$points points';
  }

  @override
  String cachedAsOf(String time) {
    return 'Is device se dikhaya gaya, last update $time.';
  }

  @override
  String get cachedNeverLoaded =>
      'Abhi load nahi hua. Ek baar connect karke apne customers dekhiye.';

  @override
  String get loadMore => 'Aur dikhaiye';

  @override
  String get catalogueServices => 'Services';

  @override
  String get catalogueAddOns => 'Add-ons';

  @override
  String get staffTitle => 'Team';

  @override
  String get catalogueEmpty =>
      'Abhi yahan kuch nahi. Crayora aapke saath ise set karta hai.';

  @override
  String get inactiveLabel => 'Chhipa hua';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String addsMinutes(int minutes) {
    return '$minutes min badhata hai';
  }

  @override
  String get dayViewSoon => 'Din ka view booking ke saath aayega.';

  @override
  String get balanceReadOnly =>
      'Balance top-up aur visits se banta hai. Ise yahan badla nahi ja sakta.';

  @override
  String get catalogueAdd => 'Add kijiye';

  @override
  String get serviceFormTitle => 'Service';

  @override
  String get addOnFormTitle => 'Add-on';

  @override
  String get staffFormTitle => 'Team member';

  @override
  String get fieldName => 'Naam';

  @override
  String get fieldPrice => 'Daam (₹)';

  @override
  String get fieldDuration => 'Minute';

  @override
  String get fieldExtraMinutes => 'Extra minute';

  @override
  String get fieldVisible => 'Customers ise dekh sakte hain';

  @override
  String get actionSave => 'Save kijiye';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get formNameRequired =>
      'Naam zaroori hai - customers ise dekhte hain.';

  @override
  String get formPriceInvalid =>
      'Daam rupees mein daaliye, jaise 400 ya 400.50.';

  @override
  String get formDurationInvalid => 'Minute 5 se 600 ke beech daaliye.';

  @override
  String get saveFailedOffline =>
      'Save nahi hua. Catalogue badalne ke liye connection chahiye.';

  @override
  String get saveFailedRefused =>
      'Aapka account catalogue nahi badal sakta. Owner se kahiye.';

  @override
  String get saveFailed => 'Save nahi hua. Dobara try kijiye.';

  @override
  String get dayTitle => 'Aaj';

  @override
  String get dayEmpty => 'Aaj koi booking nahi.';

  @override
  String get dayDone => 'Ho gaya';

  @override
  String get dayCancelled => 'Cancel';

  @override
  String daySyncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes sync hone baaki',
      one: '1 change sync hona baaki',
    );
    return '$_temp0';
  }

  @override
  String get dayCancelBooking => 'Appointment cancel kijiye';

  @override
  String get attentionEmpty => 'Kuch bhi dhyan dene layak nahi.';

  @override
  String get attentionDiscard => 'Hata dijiye';

  @override
  String get attentionOpComplete => 'Complete karein';

  @override
  String get attentionOpBooking => 'Nayi booking';

  @override
  String get attentionOpCancel => 'Cancellation';

  @override
  String get reasonSlotTaken =>
      'Wo time kisi aur ne le liya. Dusra time chunkar try kijiye.';

  @override
  String get reasonForbidden =>
      'Aapka account yeh nahi kar sakta. Owner se kahiye.';

  @override
  String get reasonNotCompletable =>
      'Wo appointment pehle hi complete ya cancel ho chuka hai.';

  @override
  String get reasonSalonUnavailable =>
      'Salon abhi changes nahi le pa raha hai.';

  @override
  String get reasonSalonChanged =>
      'Yeh us salon ke liye tha jismein yeh phone ab sign in nahi hai.';

  @override
  String get reasonGeneric => 'Server ise accept nahi kar saka.';

  @override
  String get walkInTitle => 'Walk-in';

  @override
  String get walkInCustomer => 'Customer';

  @override
  String get walkInService => 'Service';

  @override
  String get walkInAddOns => 'Add-ons (optional)';

  @override
  String get walkInStaff => 'Kiske saath';

  @override
  String get walkInAnyStaff => 'Koi bhi';

  @override
  String get walkInTime => 'Time';

  @override
  String get walkInNoSlots => 'Us din ke liye koi free time nahi.';

  @override
  String get walkInBook => 'Book kijiye';

  @override
  String get walkInBooked => 'Book ho gaya.';

  @override
  String get walkInQueuedOffline =>
      'Save ho gaya. Online aate hi book ho jayega.';

  @override
  String noticeHeading(String salonName) {
    return '$salonName aapke baare mein kya jaanega';
  }

  @override
  String get noticeItemPhone =>
      'Aapka mobile number — login code bhejne ke liye, aur booking ke baare mein contact karne ke liye.';

  @override
  String get noticeItemVisits =>
      'Aapka naam aur aapki visits — taaki aapki history, balance aur points sahi rahein.';

  @override
  String get noticeItemOptional =>
      'Birthday aur photos optional hain, alag se pooche jaate hain, aur aapki haan ke bina band rehte hain.';

  @override
  String noticeFiduciary(String salonName) {
    return '$salonName tay karta hai ki kya rakha jaaye aur kyun. Crayora app banata hai aur unke liye data rakhta hai.';
  }

  @override
  String get noticeControl =>
      'Aap kabhi bhi consent wapas le sakte hain, apne data ki copy maang sakte hain, ya mitane ke liye keh sakte hain — “Aapka data” mein.';

  @override
  String get noticeContactHeading => 'Sawaal ya shikayat';

  @override
  String get noticeContactNone =>
      'Salon ke counter par poochein. Jawab na mile to Crayora ko likhein.';

  @override
  String get noticePolicyLink => 'Poori privacy policy padhein';

  @override
  String get noticeLinkFailed =>
      'Is phone mein ise kholne wala kuch nahi hai. Pata upar likha hai.';

  @override
  String get yourDataTitle => 'Aapka data';

  @override
  String get yourDataConsentsHeading =>
      'Aapne kin baaton ke liye haan kaha hai';

  @override
  String get yourDataRightsHeading => 'Aapke adhikaar';

  @override
  String get yourDataFiduciaryHeading => 'Aapka data kiske paas hai';

  @override
  String get consentServiceTitle => 'Booking aur payment ke message';

  @override
  String get consentServiceLocked =>
      'Yeh service ka hissa hai. Inhe rokne ke liye apna account mitane ke liye kahein.';

  @override
  String get consentPromotionalTitle => 'Is salon ke offers';

  @override
  String get consentWhatsappTitle => 'WhatsApp par offers';

  @override
  String get consentPhotosTitle => 'Pehle aur baad ki photos';

  @override
  String get consentPhotosSubtitle =>
      'Taaki salon aapko dikha sake ki pichhli baar kya kiya gaya tha.';

  @override
  String get consentSaveFailed =>
      'Yeh save nahi hua. Connection dekh kar phir koshish karein.';

  @override
  String get rightAccessTitle => 'Mere data ki copy maangein';

  @override
  String get rightErasureTitle => 'Mera account mitane ke liye kahein';

  @override
  String get rightGrievanceTitle => 'Apne data ko lekar shikayat darj karein';

  @override
  String rightAsked(String asked, String due) {
    return '$asked ko maanga. Jawab $due tak aana chahiye.';
  }

  @override
  String rightAnswered(String outcome) {
    return 'Jawab: $outcome';
  }

  @override
  String get rightAskedThanks =>
      'Maang darj ho gayi. Salon ke paas jawab dene ke liye 30 din hain.';

  @override
  String get erasureConfirmTitle => 'Account mitane ke liye kahein?';

  @override
  String get erasureConfirmBody =>
      'Aapka naam, number aur birthday hata diye jaayenge aur aap log out ho jaayenge. Payment aur wallet ke record aapke naam ke bina rahenge — salon ko kanoonan apne hisaab-kitaab rakhne hote hain. Yeh wapas nahi ho sakta.';

  @override
  String get erasureConfirmAction => 'Haan, mitane ke liye kahein';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletPaidLabel => 'Paid credit';

  @override
  String get walletBonusLabel => 'Bonus credit';

  @override
  String walletBonusExpiryNote(String amount, String date) {
    return '$amount ka bonus $date ko khatam ho jaayega.';
  }

  @override
  String get walletAddMoney => 'Paise jodein';

  @override
  String get walletHistoryHeading => 'Recent activity';

  @override
  String get walletHistoryEmpty =>
      'Abhi kuch nahi. Aap jo paise jodenge aur yahan kharch karenge, woh is list mein dikhega.';

  @override
  String get entryTopUp => 'Paise jode gaye';

  @override
  String get entryBonus => 'Bonus';

  @override
  String get entrySpend => 'Salon mein use hua';

  @override
  String get entryExpiry => 'Bonus khatam hua';

  @override
  String get entryReversal => 'Wapas kiya gaya';

  @override
  String get entryReferral => 'Referral reward';

  @override
  String get entryCorrection => 'Correction';

  @override
  String get addMoneyTitle => 'Paise jodein';

  @override
  String get addMoneyAmount => 'Amount';

  @override
  String addMoneyBonusYouGet(String bonus) {
    return 'Aapko $bonus extra milenge.';
  }

  @override
  String get addMoneyNoBonus => 'Is amount par koi bonus nahi.';

  @override
  String get addMoneyNotRefundable =>
      'Jode gaye paise wapas nahi hote aur cash nahi nikal sakte.';

  @override
  String get addMoneyDisclosureHeading => 'Pay karne se pehle';

  @override
  String addMoneyPay(String amount) {
    return '$amount pay karein';
  }

  @override
  String addMoneyBelowMinimum(String min) {
    return 'Yahan kam se kam $min jod sakte hain.';
  }

  @override
  String get addMoneyInvalid => 'Jodne ke liye amount daalein.';

  @override
  String get addMoneyUnavailable =>
      'Yeh salon abhi payment nahi le sakta. Counter par poochein.';

  @override
  String get addMoneyCheckoutNotReady =>
      'Is version mein app se payment abhi chaalu nahi hai. Aapke paise nahi kate hain.';

  @override
  String get addMoneySubmitted =>
      'Payment bhej diya gaya. Bank ki confirmation ke baad aapka balance dikhega.';

  @override
  String get addMoneyCancelled => 'Payment cancel hua. Kuch nahi kata.';

  @override
  String get addMoneyFailed => 'Yeh payment poora nahi hua. Kuch nahi kata.';

  @override
  String get referTitle => 'Refer karein, kamayein';

  @override
  String referHeadline(String referred, String referrer) {
    return '$referred dilayein, $referrer payein';
  }

  @override
  String referHowItWorks(String salonName) {
    return 'Apna code share karein. Jab aapka dost $salonName se judkar apni pehli visit ka payment kar lega, tab dono ko wallet mein credit milega.';
  }

  @override
  String get referYourCode => 'Aapka code';

  @override
  String get referCopy => 'Copy karein';

  @override
  String get referCopied => 'Copy ho gaya';

  @override
  String get referShare => 'Share karein';

  @override
  String referWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dost jude hain, abhi aaye nahi',
      one: '1 dost juda hai, abhi aaya nahi',
      zero: 'Koi pehli visit ke intezaar mein nahi',
    );
    return '$_temp0';
  }

  @override
  String get referEarnedNone => 'Abhi kuch nahi kamaya.';

  @override
  String referEarned(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dost aa chuke hain. Aapne $amount kamaye.',
      one: '1 dost aa chuka hai. Aapne $amount kamaye.',
    );
    return '$_temp0';
  }

  @override
  String referNotCash(String salonName) {
    return 'Referral credit sirf $salonName mein use hota hai aur cash nahi nikala ja sakta.';
  }

  @override
  String get referClaimTitle => 'Kya aapko kisi ne bulaya hai?';

  @override
  String get referClaimHint => 'Dost ka code daalein';

  @override
  String get referClaimAction => 'Code lagayein';

  @override
  String get referClaimed =>
      'Code lag gaya. Pehli paid visit ke baad dono ko credit milega.';

  @override
  String get referClaimUnknown => 'Yeh code is salon ka nahi hai.';

  @override
  String get referClaimSelf => 'Yeh aapka apna code hai.';

  @override
  String get referClaimAlready =>
      'Aapke account par pehle se ek dost ka code laga hai.';

  @override
  String get referClaimNotNew =>
      'Referral code pehli visit ke liye hote hain, aur aap pehle aa chuke hain.';

  @override
  String get dashTitle => 'Dashboard';

  @override
  String get dashToday => 'Aaj';

  @override
  String get dashRevenue => 'Kamai';

  @override
  String get dashCompleted => 'Poori visits';

  @override
  String get dashAvgBill => 'Average bill';

  @override
  String get dashNoAverage => '—';

  @override
  String get dashBookings => 'Bookings';

  @override
  String dashCancelledNoShow(int cancelled, int noShow) {
    return '$cancelled cancel · $noShow nahi aaye';
  }

  @override
  String get dashThisMonth => 'Is mahine';

  @override
  String get dashNewRepeat => 'Naye / lautne wale';

  @override
  String get dashWalletCollected => 'Wallet top-up';

  @override
  String get dashOutstanding => 'Customers ke paas credit';

  @override
  String get dashOutstandingNote =>
      'Sirf dikhaya jaata hai, badla nahi ja sakta. Balance sirf top-up aur visit se badalta hai.';

  @override
  String get dashBinds => 'Naye customer jude';

  @override
  String get dashMessagingTitle => 'Reminders: kharch aur nateeja';

  @override
  String get dashSpend => 'Message par kharch';

  @override
  String dashRemindersSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders bheje',
      one: '1 reminder bheja',
    );
    return '$_temp0';
  }

  @override
  String dashReminderBookings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reminder se $count bookings',
      one: 'Reminder se 1 booking',
    );
    return '$_temp0';
  }

  @override
  String dashPushSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages app notification se free gaye',
      one: '1 message app notification se free gaya',
    );
    return '$_temp0';
  }

  @override
  String get dashCohortTitle => 'Kya customers wapas aate hain?';

  @override
  String get dashCohortAxis => '% jo lautey';

  @override
  String get dashCohortWallet => 'Wallet wale';

  @override
  String get dashCohortNoWallet => 'Bina wallet';

  @override
  String dashCohortWithin(int days) {
    return '$days din mein';
  }

  @override
  String get dashCohortNotYet => 'abhi nahi';

  @override
  String dashCohortN(int n) {
    return 'n = $n';
  }

  @override
  String get dashCohortEmpty => 'Pehli visit ke baad yahan groups dikhenge.';

  @override
  String get dashCohortTable => 'Yahi aankde';

  @override
  String get dashCohortMonth => 'Jude';

  @override
  String get dashCohortGroup => 'Group';

  @override
  String get dashDrift =>
      'Kuch purane aankde record se match nahi karte aur unki jaanch ho rahi hai.';

  @override
  String get payTake => 'Payment lein';

  @override
  String get payPaid => 'Payment ho gaya';

  @override
  String get payPartial => 'Aadha payment';

  @override
  String get paySheetTitle => 'Payment lein';

  @override
  String get payUseWallet => 'Pehle customer ka wallet use karein';

  @override
  String paySplit(String wallet, String counter) {
    return 'Wallet se $wallet. $counter lein.';
  }

  @override
  String payCollectAll(String amount) {
    return '$amount lein.';
  }

  @override
  String get payNoQuote =>
      'Connection nahi hai, isliye wallet balance check nahi ho sakta. Poori amount lein, ya wallet ke liye online hone tak rukein.';

  @override
  String get payMethod => 'Baaki payment';

  @override
  String get payCash => 'Cash';

  @override
  String get payUpi => 'UPI';

  @override
  String get payCard => 'Card';

  @override
  String get payRecord => 'Payment darj karein';

  @override
  String get payQueued =>
      'Payment darj ho gaya. Server tak pahunchne par yeh paid dikhega.';

  @override
  String get startTitle => 'Shuru karein';

  @override
  String get startAskForCode =>
      'Customer se unke app ka 4 ankon wala code maangein.';

  @override
  String get startWithCode => 'Is code se shuru karein';

  @override
  String startWrongCode(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yeh unka code nahi hai. $count koshishein baaki.',
      one: 'Yeh unka code nahi hai. 1 koshish baaki.',
    );
    return '$_temp0';
  }

  @override
  String get startLocked =>
      'Bahut galat koshishein huin, isliye code band hai. Bina code shuru karein - owner ko kaaran dikhega.';

  @override
  String get startNoCodeIssued =>
      'Unhone app mein yeh booking abhi nahi kholi, isliye code nahi hai. Kholne ko kahein, ya bina code shuru karein.';

  @override
  String get startNotStartable =>
      'Yeh booking shuru nahi ho sakti - yeh poori ya cancel ho chuki hai.';

  @override
  String get startOffline =>
      'Connection nahi hai, isliye code check nahi ho sakta. Bina code shuru kar sakte hain - owner ko kaaran dikhega.';

  @override
  String get startNoAppExplained =>
      'Is customer ke paas app nahi hai, isliye code nahi hai. Bina code shuru karein - owner ko dikhega.';

  @override
  String get startWithoutExplained =>
      'Bina code shuru karna theek hai. Yeh kaaran ke saath owner ke liye darj hota hai.';

  @override
  String get startWithoutCode => 'Bina code shuru karein';

  @override
  String get dayInProgress => 'Chal raha hai';

  @override
  String get payCounterRequested => 'Counter par payment';

  @override
  String get visitToday => 'Aaj ki aapki visit';

  @override
  String get visitInProgress => 'Aapki service chal rahi hai.';

  @override
  String get visitShowCode => 'Baithne par yeh code apne stylist ko dikhayein.';

  @override
  String visitCodeSemantics(String digits) {
    return 'Aapka start code: $digits';
  }

  @override
  String get billReady => 'Aapka bill taiyaar hai';

  @override
  String get billCounterSaid => 'Aapne counter par payment karne ko kaha hai.';

  @override
  String get billPay => 'Bill bharein';

  @override
  String billToPay(String amount) {
    return 'Payment: $amount';
  }

  @override
  String get payHowTitle => 'Aap payment kaise karna chahenge?';

  @override
  String get payOptWallet => 'Wallet';

  @override
  String payOptWalletAll(String amount, String balance) {
    return 'Apne $balance ke balance se $amount bharein.';
  }

  @override
  String payOptWalletPart(String wallet, String rest) {
    return 'Wallet ke poore $wallet use karein, phir baaki $rest UPI se ya counter par bharein.';
  }

  @override
  String payWalletBreakdown(String paid, String bonus) {
    return 'Ismein $paid aapke jama kiye hue aur $bonus bonus hai.';
  }

  @override
  String get payOptUpi => 'UPI';

  @override
  String payOptUpiBody(String amount) {
    return 'Kisi bhi UPI app se $amount bharein.';
  }

  @override
  String get payOptCounter => 'Counter par';

  @override
  String payOptCounterBody(String amount) {
    return 'Reception par cash ya card se $amount bharein.';
  }

  @override
  String payRestTitle(String amount) {
    return '$amount bharna baaki hai';
  }

  @override
  String get payRestHow =>
      'Aapka wallet use ho gaya. Baaki ka payment kaise karna chahenge?';

  @override
  String get billingReadOnlyTitle => 'Abhi sirf dekh sakte hain';

  @override
  String billingReadOnlyGrace(String date) {
    return 'Aapki subscription ka payment baaki hai, isliye abhi kuch naya darj nahi ho sakta - na booking, na start, na payment. Sab kuch dekh sakte hain. Suspension se bachne ke liye $date se pehle Crayora ko payment karein.';
  }

  @override
  String get billingReadOnlySuspended =>
      'Aapki subscription suspended hai, isliye kuch naya darj nahi ho sakta. Kuch bhi delete nahi hua hai. Payment karke aage badhne ke liye Crayora se contact karein.';

  @override
  String get billingReadOnlyStaff =>
      'Salon abhi kuch naya darj nahi kar sakta - na booking, na start, na payment. Owner ise suljha rahe hain.';

  @override
  String get billingReadOnlyOther =>
      'Yeh salon abhi badlav darj nahi kar sakta. Crayora se contact karein.';

  @override
  String get billAlreadyPaid => 'Yeh bill pehle se bhara hai.';

  @override
  String get billPaidFromWallet => 'Wallet se payment ho gaya.';

  @override
  String get billUpiSent =>
      'Payment bhej diya gaya. Bank ki confirmation ke baad bill bhara hua dikhega.';

  @override
  String get billCounterTold =>
      'Counter ko pata hai. Paise lene par aapka bill bhara hua dikhega.';

  @override
  String get navHome => 'Home';

  @override
  String get navBook => 'Book';

  @override
  String get navMe => 'Main';

  @override
  String homeGreeting(String name) {
    return 'Namaste $name';
  }

  @override
  String get homeGreetingNoName => 'Phir se swagat hai';

  @override
  String homeNextDueService(String service, String date) {
    return 'Aapka agla $service lagbhag $date ko hona hai';
  }

  @override
  String homeNextDue(String date) {
    return 'Aapki agli visit lagbhag $date ko hai';
  }

  @override
  String get homeBookNow => 'Abhi book karein';

  @override
  String get homeNextBooking => 'Aapki agli booking';

  @override
  String get homeWalletUnavailable =>
      'Aapka balance load nahi hua. Dobara try karne ke liye neeche kheenchein.';

  @override
  String get walletView => 'Wallet dekhein';

  @override
  String get referSubtitle => 'Dost ko bulaayein, dono ko credit';

  @override
  String bookStep(int step, int total) {
    return 'Step $step / $total';
  }

  @override
  String get bookChooseService => 'Service chunein';

  @override
  String get bookOther => 'Aur';

  @override
  String get bookNoServices => 'Abhi booking ke liye koi service nahi hai.';

  @override
  String get bookAddOnsTitle => 'Kuch aur jodein?';

  @override
  String get bookAddOnsHint =>
      'Optional. Jab tak aap tick na karein, kuch nahi judta.';

  @override
  String get bookStylistTime => 'Stylist aur time';

  @override
  String get bookStylist => 'Stylist';

  @override
  String get bookAnyone => 'Koi bhi';

  @override
  String get bookDate => 'Tareekh';

  @override
  String get bookNoTimes => 'Is din koi time khaali nahi hai.';

  @override
  String get bookTimesFailed =>
      'Khaali time load nahi hue. Apna connection check karein.';

  @override
  String get bookTotal => 'Total';

  @override
  String bookMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get bookContinue => 'Aage badhein';

  @override
  String get bookReview => 'Apni booking check karein';

  @override
  String get bookService => 'Service';

  @override
  String get bookAddOns => 'Add-ons';

  @override
  String get bookNone => 'Koi nahi';

  @override
  String get bookDateTime => 'Tareekh aur time';

  @override
  String get bookTakesAbout => 'Lagbhag time';

  @override
  String get bookPayAfter =>
      'Payment visit ke baad - wallet, UPI ya counter par.';

  @override
  String get bookChangeHint =>
      'Shuru hone tak aap yeh booking app mein cancel kar sakte hain.';

  @override
  String get bookConfirm => 'Booking pakki karein';

  @override
  String get bookSlotTaken =>
      'Yeh time abhi kisi aur ne le liya. Doosra chunein.';

  @override
  String get bookFailed =>
      'Booking nahi hui. Connection check karke dobara try karein.';

  @override
  String bookDone(String date) {
    return 'Book ho gaya. $date ko milte hain.';
  }

  @override
  String get bookingTitle => 'Aapki booking';

  @override
  String get bookingBooked => 'Booked';

  @override
  String get bookingInProgress => 'Chal raha hai';

  @override
  String get bookingCancelledStatus => 'Cancelled';

  @override
  String get bookingCancel => 'Booking cancel karein';

  @override
  String get bookingCancelAsk => 'Yeh booking cancel karein?';

  @override
  String get bookingCancelBody =>
      'Time salon ko wapas mil jayega. Kuch pay nahi hua, isliye kuch refund nahi.';

  @override
  String get bookingKeep => 'Rehne dein';

  @override
  String get bookingCancelled => 'Booking cancel ho gayi.';

  @override
  String get bookingCancelFailed =>
      'Cancel nahi hui. Connection check karke dobara try karein.';

  @override
  String get bookingNotFound => 'Yeh booking nahi mili.';

  @override
  String withStylist(String name) {
    return '$name ke saath';
  }

  @override
  String get historyTitle => 'Visit history';

  @override
  String get historyEmpty =>
      'Abhi tak koi visit nahi. Pehli visit yahan dikhegi.';

  @override
  String get historyPaid => 'Paid';

  @override
  String get historyUnpaid => 'Abhi payment nahi hua';

  @override
  String get historyFailed => 'Aapki visits load nahi hui.';

  @override
  String get meTitle => 'Main';

  @override
  String get meName => 'Naam';

  @override
  String get mePhone => 'Phone';

  @override
  String get meLanguage => 'Bhasha';

  @override
  String get meHistorySub => 'Aapne kya karwaya, aur kab';

  @override
  String get meYourDataSub => 'Copy, mitana, aur kisse poochein';

  @override
  String get meAppBy => 'App by Crayora';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageHinglish => 'Hinglish';

  @override
  String get bookingMissed => 'Miss ho gayi';

  @override
  String get homeFirstVisit => 'Apni pehli visit book karein';

  @override
  String get joinIntro =>
      'Judte hi aapke salon ka app khul jayega. Code counter par rakhe card par hai.';

  @override
  String get homeBookAgain => 'Apni agli visit book karein';
}
