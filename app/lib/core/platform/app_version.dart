import 'package:package_info_plus/package_info_plus.dart';

/// This install's build number - the `+N` of the version - so the console can
/// say "below build N, update first" (0119). The same call on Android and iOS
/// (RULES 15b); an interface so screens can be tested at any build.
abstract interface class AppVersion {
  /// 0 when it cannot be read, which never blocks anything.
  Future<int> build();
}

class PlatformAppVersion implements AppVersion {
  const PlatformAppVersion();

  @override
  Future<int> build() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
