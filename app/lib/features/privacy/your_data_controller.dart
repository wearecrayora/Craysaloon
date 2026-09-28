import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/join/cray_api.dart';
import '../../domain/privacy/privacy.dart';
import '../join/join_controller.dart';

/// The rights surface. Null when the signed-in account is not a customer:
/// consent is the customer's own, and there is nothing here for a stylist.
final privacyApiProvider = Provider<PrivacyApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is PrivacyApi ? api as PrivacyApi : null;
});

class YourDataState {
  const YourDataState({
    this.consents = const {},
    this.requests = const [],
    this.loading = true,
    this.failed = false,
    this.busyPurpose,
    this.message,
  });

  /// purpose -> granted. The database's answer, never a local guess: a toggle
  /// that shows what the app hoped for is a toggle that lies after a failure.
  final Map<String, bool> consents;
  final List<DataRightRequest> requests;
  final bool loading;

  /// The load itself failed. The screen says so instead of showing every
  /// consent as "off", which would be a false statement about a legal record.
  final bool failed;

  /// Which toggle is in flight, so only that row is disabled.
  final String? busyPurpose;

  final YourDataMessage? message;

  YourDataState copyWith({
    Map<String, bool>? consents,
    List<DataRightRequest>? requests,
    bool? loading,
    bool? failed,
    String? busyPurpose,
    YourDataMessage? message,
    bool clearBusy = false,
    bool clearMessage = false,
  }) =>
      YourDataState(
        consents: consents ?? this.consents,
        requests: requests ?? this.requests,
        loading: loading ?? this.loading,
        failed: failed ?? this.failed,
        busyPurpose: clearBusy ? null : (busyPurpose ?? this.busyPurpose),
        message: clearMessage ? null : (message ?? this.message),
      );

  DataRightRequest? openRequest(String kind) =>
      requests.where((r) => r.kind == kind).firstOrNull;
}

enum YourDataMessage {
  /// Service messages cannot be switched off. Not an error - an explanation,
  /// with erasure as the way out (RULES 11.6c).
  serviceRequired,
  saveFailed,
  requestSent,
}

class YourDataController extends Notifier<YourDataState> {
  @override
  YourDataState build() {
    // Riverpod builds synchronously; the load starts immediately and the screen
    // shows its own loading state until it lands.
    Future.microtask(load);
    return const YourDataState();
  }

  PrivacyApi? get _api => ref.read(privacyApiProvider);

  Future<void> load() async {
    final api = _api;
    if (api == null) {
      state = state.copyWith(loading: false, failed: true);
      return;
    }
    state = state.copyWith(loading: true, failed: false, clearMessage: true);
    try {
      final consents = await api.consents();
      final requests = await api.myRequests();
      state = state.copyWith(
        consents: {for (final c in consents) c.purpose: c.granted},
        requests: requests,
        loading: false,
        failed: false,
      );
    } on CrayApiException {
      state = state.copyWith(loading: false, failed: true);
    }
  }

  /// Withdrawal must be as easy as consent was (s.6(4)) - one tap, no
  /// confirmation, and it takes effect before the screen redraws.
  Future<void> setConsent(String purpose, bool granted) async {
    final api = _api;
    if (api == null) return;
    state = state.copyWith(busyPurpose: purpose, clearMessage: true);
    try {
      final refusal = await api.setConsent(purpose, granted);
      if (refusal == ConsentRefusal.serviceRequired) {
        state = state.copyWith(
          message: YourDataMessage.serviceRequired,
          clearBusy: true,
        );
        return;
      }
      state = state.copyWith(
        consents: {...state.consents, purpose: granted},
        clearBusy: true,
      );
    } on CrayApiException {
      // The stored value is untouched, so the toggle springs back to what the
      // database actually holds. A consent record the customer cannot trust is
      // worse than an error message.
      state = state.copyWith(
        message: YourDataMessage.saveFailed,
        clearBusy: true,
      );
    }
  }

  Future<void> request(String kind, {String? detail}) async {
    final api = _api;
    if (api == null) return;
    state = state.copyWith(busyPurpose: kind, clearMessage: true);
    try {
      await api.requestRight(kind, detail: detail);
      final requests = await api.myRequests();
      state = state.copyWith(
        requests: requests,
        message: YourDataMessage.requestSent,
        clearBusy: true,
      );
    } on CrayApiException {
      state = state.copyWith(message: YourDataMessage.saveFailed, clearBusy: true);
    }
  }
}

final yourDataControllerProvider =
    NotifierProvider<YourDataController, YourDataState>(YourDataController.new);
