import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/platform/app_version.dart';
import '../../domain/app_config/app_config.dart';
import '../join/join_controller.dart' show crayApiProvider;

final appConfigApiProvider = Provider<AppConfigApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is AppConfigApi ? api as AppConfigApi : null;
});

/// The salon's app config. Keeps the last one it had when a read fails, so a
/// dropped connection never rearranges the home screen back to the defaults.
class AppConfigNotifier extends AsyncNotifier<AppConfig> {
  @override
  Future<AppConfig> build() async {
    ref.watch(sessionProvider);
    final api = ref.watch(appConfigApiProvider);
    final last = state.value;
    if (api == null) return last ?? AppConfig.defaults;
    try {
      return await api.myAppConfig() ?? last ?? AppConfig.defaults;
    } catch (_) {
      return last ?? AppConfig.defaults;
    }
  }
}

final appConfigProvider = AsyncNotifierProvider<AppConfigNotifier, AppConfig>(
  AppConfigNotifier.new,
);

/// The config as it stands right now - the defaults until the first read.
AppConfig appConfig(WidgetRef ref) => ref.watch(appConfigProvider).value ?? AppConfig.defaults;

/// A console switch: on unless turned off (0119).
bool switchOn(WidgetRef ref, String key) => appConfig(ref).on(key);

final announcementsProvider = FutureProvider<List<Announcement>>((ref) async {
  final api = ref.watch(appConfigApiProvider);
  if (api == null) return const [];
  try {
    return await api.announcements();
  } catch (_) {
    return const [];
  }
});

final appVersionProvider = Provider<AppVersion>((ref) => const PlatformAppVersion());

final buildNumberProvider = FutureProvider<int>((ref) => ref.watch(appVersionProvider).build());
