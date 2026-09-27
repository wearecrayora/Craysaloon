import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/join/cray_api.dart';

/// The only file in the app that talks to Supabase (`RULES.md` 3.7 / GATE-1).
///
/// Two things it deliberately does not do:
///
/// * **It never sends the salon with a verification.** `otp-verify` reads both
///   the phone and the salon from the challenge the server issued, so editing a
///   request cannot move a login to a different salon (ADR-36).
/// * **It never logs a phone number, a code, a challenge id or a token.** The
///   error paths carry a kind, not a payload.
class SupabaseCrayApi implements CrayApi {
  SupabaseCrayApi(this._client);

  final SupabaseClient _client;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Future<SalonSummary?> resolveJoinCode(String code, {required String deviceKey}) async {
    try {
      final result = await _client.rpc<dynamic>(
        'resolve_join_code',
        params: {'p_code': code, 'p_device_key': deviceKey},
      );
      final row = _asMap(result);
      if (row == null) return null;

      final salonId = row['salon_id'] as String?;
      final displayName = row['display_name'] as String?;
      if (salonId == null || displayName == null) return null;

      return SalonSummary(
        salonId: salonId,
        displayName: displayName,
        brandingVersion: (row['branding_version'] as num?)?.toInt() ?? 0,
        branding: _asMap(row['branding']) ?? const {},
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<void> startJoin({
    required String code,
    required String phone,
    required String deviceKey,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'start_join',
        params: {'p_code': code, 'p_phone': phone, 'p_device_key': deviceKey},
      );
    } on PostgrestException catch (e) {
      throw CrayApiException(_postgrestKind(e));
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  @override
  Future<OtpChallenge> sendOtp(String phone) async {
    final response = await _invoke('otp-send', {'phone': phone});
    final body = _asMap(response.data) ?? const {};
    final id = body['challenge_id'] as String?;
    if (response.status != 200 || id == null) {
      throw CrayApiException(_functionKind(response.status, body['error']));
    }
    return OtpChallenge(
      challengeId: id,
      expiresIn: (body['expires_in'] as num?)?.toInt() ?? 60,
    );
  }

  @override
  Future<LoginOutcome> verifyOtp({
    required String challengeId,
    required String code,
    bool promotional = false,
    bool whatsapp = false,
  }) async {
    final response = await _invoke('otp-verify', {
      'challenge_id': challengeId,
      'code': code,
      'consents': {'promotional': promotional, 'whatsapp': whatsapp},
    });
    final body = _asMap(response.data) ?? const {};

    if (response.status != 200) {
      throw CrayApiException(
        _functionKind(response.status, body['error']),
        attemptsLeft: (body['attempts_left'] as num?)?.toInt(),
      );
    }

    // The Edge Function returns the session; supabase_flutter is what persists
    // and refreshes it, so hand it over rather than keeping tokens ourselves.
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw const CrayApiException(CrayErrorKind.server);
    }
    await _client.auth.setSession(refresh);

    return switch (body['outcome']) {
      'bound' => LoginOutcome.bound,
      'staff' => LoginOutcome.staff,
      _ => LoginOutcome.returning,
    };
  }

  Future<FunctionResponse> _invoke(String name, Map<String, Object?> body) async {
    try {
      return await _client.functions.invoke(name, body: body);
    } on FunctionException catch (e) {
      // A non-2xx from an Edge Function arrives as an exception, with the body
      // we deliberately shaped. Treat it as a response, not a crash.
      return FunctionResponse(status: e.status, data: e.details);
    } catch (_) {
      throw const CrayApiException(CrayErrorKind.network);
    }
  }

  static CrayErrorKind _functionKind(int status, Object? error) {
    if (status == 429) return CrayErrorKind.rateLimited;
    return switch (error) {
      'salon_unavailable' => CrayErrorKind.salonUnavailable,
      'already_bound' => CrayErrorKind.alreadyBound,
      'account_conflict' => CrayErrorKind.accountConflict,
      'wrong_code' => CrayErrorKind.wrongCode,
      'expired' => CrayErrorKind.otpExpired,
      'too_many_attempts' => CrayErrorKind.rateLimited,
      'invalid_phone' => CrayErrorKind.invalidPhone,
      _ => CrayErrorKind.server,
    };
  }

  static CrayErrorKind _postgrestKind(PostgrestException e) {
    final text = e.message.toLowerCase();
    if (text.contains('rate')) return CrayErrorKind.rateLimited;
    // app.phone_hash raises on anything that is not an Indian mobile number.
    if (text.contains('phone_hash')) return CrayErrorKind.invalidPhone;
    if (text.contains('not active') || text.contains('unavailable')) {
      return CrayErrorKind.salonUnavailable;
    }
    return CrayErrorKind.server;
  }

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;
}
