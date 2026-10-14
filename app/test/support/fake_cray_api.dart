import 'package:craysalon/domain/join/cray_api.dart';

/// A server that behaves like the real one, without a network.
///
/// It is deliberately faithful about the things that are rules rather than
/// implementation details: an unknown code and a salon in setup are the same
/// answer, and `alreadyBound` carries no salon.
class FakeCrayApi implements CrayApi {
  FakeCrayApi({
    this.salon,
    this.resolveError,
    this.startJoinError,
    this.sendError,
    this.verifyError,
    this.outcome = LoginOutcome.bound,
  });

  SalonSummary? salon;
  CrayApiException? resolveError;
  CrayApiException? startJoinError;
  CrayApiException? sendError;
  CrayApiException? verifyError;
  LoginOutcome outcome;

  final List<String> resolvedCodes = [];
  final List<String> startedCodes = [];
  final List<String> sentTo = [];
  final List<Map<String, Object?>> verifications = [];

  /// The session the app would have after login. Null means nobody is signed in.
  AppSession? sessionValue;

  @override
  AppSession? get session => sessionValue;

  @override
  bool get hasSession => sessionValue != null;

  @override
  Future<SalonSummary?> resolveJoinCode(String code, {required String deviceKey}) async {
    resolvedCodes.add(code);
    if (resolveError != null) throw resolveError!;
    return salon;
  }

  /// What `my_branding` returns: the signed-in caller's own salon, as published
  /// now. Null means bound to nothing (or not yet set by the test).
  SalonSummary? mine;
  CrayApiException? myBrandingError;
  int myBrandingCalls = 0;

  @override
  Future<SalonSummary?> myBranding() async {
    myBrandingCalls++;
    if (myBrandingError != null) throw myBrandingError!;
    return mine;
  }

  @override
  Future<void> startJoin({
    required String code,
    required String phone,
    required String deviceKey,
  }) async {
    startedCodes.add(code);
    if (startJoinError != null) throw startJoinError!;
  }

  @override
  Future<OtpChallenge> sendOtp(String phone) async {
    sentTo.add(phone);
    if (sendError != null) throw sendError!;
    return const OtpChallenge(challengeId: 'challenge-1', expiresIn: 60);
  }

  @override
  Future<LoginOutcome> verifyOtp({
    required String challengeId,
    required String code,
    bool promotional = false,
    bool whatsapp = false,
    AgeDeclaration? age,
  }) async {
    verifications.add({
      'challenge_id': challengeId,
      'promotional': promotional,
      'whatsapp': whatsapp,
      'age': age?.toJson(),
    });
    if (verifyError != null) throw verifyError!;
    return outcome;
  }
}

/// A published branding document, shaped like the console's output: the
/// operator's input plus the resolved light and dark sets (migration 0037).
Map<String, Object?> publishedBranding({
  String displayName = 'Studio Nine Salon',
  String primaryLight = '#1f6f5c',
  String primaryDark = '#3fbf9f',
  String script = 'latin',
  double lineHeightBonus = 0,
  // The rest of a brand's resolved palette, per mode, as the console's publish
  // would compute it - so a sweep can wear a dark brand or a pale one
  // (DESIGN 13: three test brandings), not only the default teal.
  Map<String, String> lightColors = const {},
  Map<String, String> darkColors = const {},
}) {
  // Each mode resolved as the console's publish would: the dark set carries
  // its OWN ink and greys, light on dark. (It used to reuse the light ones,
  // which no real publish could produce - the contrast gate blocks it - and
  // which the screen sweep's contrast check rightly failed.)
  Map<String, Object?> set(String primary, String surface, String text, {bool dark = false}) => {
        'color': {
          'primary': primary,
          'onPrimary': dark ? '#1a1a19' : '#ffffff',
          'primaryContainer': dark ? '#1f3b34' : '#dbeee8',
          'onPrimaryContainer': dark ? '#a8e6d4' : '#0d3b31',
          'accent': '#eb6834',
          'onAccent': '#1a1a19',
          'brandInk': dark ? '#3fbf9f' : '#155447',
          'surface': surface,
          'surfaceAlt': dark ? '#1f1e1b' : '#f4f3f0',
          'surfaceSunken': dark ? '#0f0f0e' : '#eceae5',
          'border': dark ? '#35342f' : '#dedcd6',
          'borderStrong': dark ? '#7d7b73' : '#8f8d85',
          'divider': dark ? '#2a2927' : '#e7e5df',
          'textPrimary': text,
          'textSecondary': dark ? '#c4c1ba' : '#52514e',
          'textMuted': dark ? '#9a968e' : '#6b6964',
          // A palette that tried to recolour status. The app must ignore it.
          'success': '#ff00ff',
          'danger': '#00ff00',
        },
        'radius': {'base': 16, 'chip': 8, 'sheet': 24, 'pill': 999},
        'typography': {
          'heading': {'family': 'Fraunces', 'weight': 600},
          'body': {'family': 'Inter', 'weight': 400},
          'script': script,
          'lineHeightBonus': lineHeightBonus,
        },
      };

  Map<String, Object?> wearing(Map<String, Object?> resolved, Map<String, String> colors) => {
        ...resolved,
        'color': {...(resolved['color']! as Map<String, Object?>), ...colors},
      };

  return {
    'version': 3,
    'displayName': displayName,
    'brand': {
      'light': {'primary': primaryLight, 'accent': '#eb6834'},
      'dark': {'primary': primaryDark, 'accent': '#eb6834'},
    },
    'resolved': {
      'light': wearing(set(primaryLight, '#fcfcfb', '#1a1a19'), lightColors),
      'dark': wearing(set(primaryDark, '#1a1a19', '#ffffff', dark: true), darkColors),
    },
  };
}

SalonSummary fakeSalon({
  String displayName = 'Studio Nine Salon',
  // An active salon always has one: activation refuses without it (0053). The
  // default is present so the notice under test is the one customers see.
  GrievanceContact? grievance = const GrievanceContact(
    name: 'Sunita Rao',
    email: 'privacy@studionine.example',
  ),
}) =>
    SalonSummary(
      salonId: '11111111-0000-4000-8000-000000000001',
      displayName: displayName,
      brandingVersion: 3,
      branding: publishedBranding(displayName: displayName),
      grievance: grievance,
    );
