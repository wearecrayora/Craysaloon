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
  }) async {
    verifications.add({
      'challenge_id': challengeId,
      'promotional': promotional,
      'whatsapp': whatsapp,
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
  String script = 'latin',
  double lineHeightBonus = 0,
}) {
  Map<String, Object?> set(String primary, String surface, String text) => {
        'color': {
          'primary': primary,
          'onPrimary': '#ffffff',
          'primaryContainer': '#dbeee8',
          'onPrimaryContainer': '#0d3b31',
          'accent': '#eb6834',
          'onAccent': '#1a1a19',
          'brandInk': '#155447',
          'surface': surface,
          'surfaceAlt': '#f4f3f0',
          'surfaceSunken': '#eceae5',
          'border': '#dedcd6',
          'borderStrong': '#8f8d85',
          'divider': '#e7e5df',
          'textPrimary': text,
          'textSecondary': '#52514e',
          'textMuted': '#6b6964',
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

  return {
    'version': 3,
    'displayName': displayName,
    'brand': {
      'light': {'primary': primaryLight, 'accent': '#eb6834'},
      'dark': {'primary': '#3fbf9f', 'accent': '#eb6834'},
    },
    'resolved': {
      'light': set(primaryLight, '#fcfcfb', '#1a1a19'),
      'dark': set('#3fbf9f', '#1a1a19', '#ffffff'),
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
