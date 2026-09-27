import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/branding_store.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/join/join_code.dart';

/// Where the customer is in the join flow.
///
/// Salon code first, then login (`RULES.md` 4.1): there is no step here that
/// asks for a phone number before the salon is known, and binding is not a step
/// at all - the server does it inside verification, before it issues a session
/// (ADR-39). So there is no "bound?" state to recover from.
enum JoinStep { code, confirm, phone, otp, done }

/// A failure the customer can read. Deliberately not the exception: the UI must
/// never render a server message, and [alreadyBound] must never name a salon.
enum JoinProblem {
  none,
  codeNotFound,
  salonUnavailable,
  rateLimited,
  offline,
  invalidPhone,
  wrongCode,
  otpExpired,
  alreadyBound,
  accountConflict,
  generic,
}

class JoinState {
  const JoinState({
    this.step = JoinStep.code,
    this.busy = false,
    this.problem = JoinProblem.none,
    this.salon,
    this.code = '',
    this.phone = '',
    this.challenge,
    this.attemptsLeft,
    this.outcome,
    this.promotional = false,
    this.whatsapp = false,
  });

  final JoinStep step;
  final bool busy;
  final JoinProblem problem;
  final SalonSummary? salon;

  /// The code the customer typed, canonical. `start_join` takes a code, not a
  /// salon id: the server resolves it again rather than trusting our lookup.
  final String code;

  /// Held only to show "sent to …" and to resend. Never persisted, never logged.
  final String phone;
  final OtpChallenge? challenge;
  final int? attemptsLeft;
  final LoginOutcome? outcome;

  /// Marketing consent, opt-in, starting false (`RULES.md` 11).
  final bool promotional;
  final bool whatsapp;

  JoinState copyWith({
    JoinStep? step,
    bool? busy,
    JoinProblem? problem,
    SalonSummary? salon,
    String? code,
    String? phone,
    OtpChallenge? challenge,
    int? attemptsLeft,
    LoginOutcome? outcome,
    bool? promotional,
    bool? whatsapp,
  }) {
    return JoinState(
      step: step ?? this.step,
      busy: busy ?? this.busy,
      problem: problem ?? this.problem,
      salon: salon ?? this.salon,
      code: code ?? this.code,
      phone: phone ?? this.phone,
      challenge: challenge ?? this.challenge,
      attemptsLeft: attemptsLeft ?? this.attemptsLeft,
      outcome: outcome ?? this.outcome,
      promotional: promotional ?? this.promotional,
      whatsapp: whatsapp ?? this.whatsapp,
    );
  }
}

/// Injected, so the flow can be driven in tests without a network.
final crayApiProvider = Provider<CrayApi>((ref) {
  throw UnimplementedError('crayApiProvider must be overridden at startup');
});

final deviceKeyProvider = Provider<String>((ref) => 'unset');

final brandingStoreProvider = Provider<BrandingStore>((ref) => BrandingStore());

/// The branding cached on disk at startup, if any. Overridden in main();
/// null in tests, which is also what a fresh install looks like.
final initialBrandingProvider = Provider<CachedBranding?>((ref) => null);

/// The branding the app is currently wearing. Set the moment a code resolves, so
/// the login screen already carries the salon's brand (PHASES M3 done-when),
/// and restored from the cache at startup so that is true offline too.
class ResolvedBranding extends Notifier<CachedBranding?> {
  @override
  CachedBranding? build() => ref.watch(initialBrandingProvider);

  void wear(CachedBranding branding) => state = branding;
}

final resolvedBrandingProvider =
    NotifierProvider<ResolvedBranding, CachedBranding?>(ResolvedBranding.new);

class JoinController extends Notifier<JoinState> {
  @override
  JoinState build() => const JoinState();

  CrayApi get _api => ref.read(crayApiProvider);

  /// U2. The code is normalised locally only to catch a typo early; the server
  /// decides what exists.
  Future<void> submitCode(String raw) async {
    final code = JoinCode.tryParse(raw);
    if (code == null) {
      state = state.copyWith(problem: JoinProblem.codeNotFound);
      return;
    }

    state = state.copyWith(busy: true, problem: JoinProblem.none);
    try {
      final salon = await _api.resolveJoinCode(
        code.value,
        deviceKey: ref.read(deviceKeyProvider),
      );
      if (salon == null) {
        // A salon in setup and a code that does not exist are the same answer,
        // on purpose: a leaked QR must not confirm that a salon is coming.
        state = state.copyWith(busy: false, problem: JoinProblem.codeNotFound);
        return;
      }

      final branding = CachedBranding(
        salonId: salon.salonId,
        displayName: salon.displayName,
        version: salon.brandingVersion,
        document: salon.branding,
      );
      // Theme now: from here on the customer is looking at their salon's app.
      ref.read(resolvedBrandingProvider.notifier).wear(branding);

      state = state.copyWith(
        busy: false,
        salon: salon,
        code: code.value,
        step: JoinStep.confirm,
      );
    } on CrayApiException catch (e) {
      state = state.copyWith(busy: false, problem: _problem(e));
    }
  }

  /// U3. The salon has been named and the customer said yes.
  void confirmSalon() => state = state.copyWith(step: JoinStep.phone, problem: JoinProblem.none);

  void backToCode() => state = const JoinState();

  void setPromotional(bool value) => state = state.copyWith(promotional: value);

  void setWhatsapp(bool value) =>
      state = state.copyWith(whatsapp: value, promotional: value ? true : state.promotional);

  /// U4/U5. Records the intent - so this salon's account sends and pays for the
  /// OTP - and then asks for the code.
  Future<void> submitPhone(String phone) async {
    if (state.salon == null || state.code.isEmpty) return;

    state = state.copyWith(busy: true, problem: JoinProblem.none, phone: phone);
    try {
      await _api.startJoin(
        code: state.code,
        phone: phone,
        deviceKey: ref.read(deviceKeyProvider),
      );
      final challenge = await _api.sendOtp(phone);
      state = state.copyWith(busy: false, challenge: challenge, step: JoinStep.otp);
    } on CrayApiException catch (e) {
      state = state.copyWith(busy: false, problem: _problem(e));
    }
  }

  Future<void> resend() async {
    if (state.phone.isEmpty) return;
    state = state.copyWith(busy: true, problem: JoinProblem.none);
    try {
      final challenge = await _api.sendOtp(state.phone);
      state = state.copyWith(busy: false, challenge: challenge, attemptsLeft: null);
    } on CrayApiException catch (e) {
      state = state.copyWith(busy: false, problem: _problem(e));
    }
  }

  /// U6. Verification, binding and the session all happen server-side in one
  /// call. A refusal returns no session, so there is nothing to undo here.
  Future<void> submitOtp(String code) async {
    final challenge = state.challenge;
    if (challenge == null) return;

    state = state.copyWith(busy: true, problem: JoinProblem.none);
    try {
      final outcome = await _api.verifyOtp(
        challengeId: challenge.challengeId,
        code: code,
        promotional: state.promotional,
        whatsapp: state.whatsapp,
      );

      // Bound: this salon's branding is now the app's, offline included.
      final branding = ref.read(resolvedBrandingProvider);
      if (branding != null) {
        await ref.read(brandingStoreProvider).save(
              salonId: branding.salonId,
              displayName: branding.displayName,
              version: branding.version,
              document: branding.document,
            );
      }

      state = state.copyWith(busy: false, outcome: outcome, step: JoinStep.done);
    } on CrayApiException catch (e) {
      state = state.copyWith(
        busy: false,
        problem: _problem(e),
        attemptsLeft: e.attemptsLeft,
      );
    }
  }

  static JoinProblem _problem(CrayApiException e) => switch (e.kind) {
        CrayErrorKind.network => JoinProblem.offline,
        CrayErrorKind.rateLimited => JoinProblem.rateLimited,
        CrayErrorKind.salonUnavailable => JoinProblem.salonUnavailable,
        CrayErrorKind.invalidPhone => JoinProblem.invalidPhone,
        CrayErrorKind.wrongCode => JoinProblem.wrongCode,
        CrayErrorKind.otpExpired => JoinProblem.otpExpired,
        CrayErrorKind.alreadyBound => JoinProblem.alreadyBound,
        CrayErrorKind.accountConflict => JoinProblem.accountConflict,
        CrayErrorKind.server => JoinProblem.generic,
        // Nothing in the join flow is role-gated - there is no role yet - so a
        // refusal here would be a server fault, not a permission.
        CrayErrorKind.forbidden => JoinProblem.generic,
      };
}

final joinControllerProvider =
    NotifierProvider<JoinController, JoinState>(JoinController.new);
