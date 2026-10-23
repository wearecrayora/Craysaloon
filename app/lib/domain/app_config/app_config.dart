/// What the console decides about the app, per salon (0119): the home screen's
/// tiles and sections, feature switches, and which app builds may still run.
///
/// The app ships every screen; the console only chooses what they show. A
/// value the app does not recognise is skipped, never an error - so an older
/// build reading a newer config keeps working.
library;

class AppConfig {
  const AppConfig({
    this.version = 0,
    this.pulse,
    this.homeTiles = defaultTiles,
    this.homeSections = defaultSections,
    this.switches = const {},
    this.minBuild = 0,
    this.latestBuild = 0,
    this.updateUrl,
  });

  static const defaultTiles = [
    'book', 'add_money', 'bookings', 'bills', 'refer', 'birthday', 'profile', 'your_data',
  ];
  static const defaultSections = ['categories', 'quick', 'services', 'wallet'];

  /// The config as it stands with nothing set - what the app shows before the
  /// first read, offline on a fresh install, or if the read fails.
  static const defaults = AppConfig();

  final int version;

  /// Moves whenever anything a customer sees changes - branding, the menu, the
  /// plan, the rules, an announcement. The app re-reads when it does.
  final String? pulse;
  final List<String> homeTiles;
  final List<String> homeSections;
  final Map<String, bool> switches;
  final int minBuild;
  final int latestBuild;
  final String? updateUrl;

  /// A switch is on unless the console turned it off.
  bool on(String key) => switches[key] ?? true;

  factory AppConfig.fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v, List<String> fallback) =>
        v is List ? [for (final e in v) '$e'] : fallback;
    final sw = j['switches'];
    return AppConfig(
      version: (j['version'] as num?)?.toInt() ?? 0,
      pulse: j['pulse'] as String?,
      homeTiles: strings(j['home_tiles'], defaultTiles),
      homeSections: strings(j['home_sections'], defaultSections),
      switches: sw is Map ? {for (final e in sw.entries) '${e.key}': e.value == true} : const {},
      minBuild: (j['min_build'] as num?)?.toInt() ?? 0,
      latestBuild: (j['latest_build'] as num?)?.toInt() ?? 0,
      updateUrl: j['update_url'] as String?,
    );
  }
}

/// The salon's own news, between its dates (0119).
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.endsAt,
    this.body,
    this.titleHi,
    this.bodyHi,
    this.icon = 'campaign',
  });

  final String id;
  final String title;
  final String? body;
  final String? titleHi;
  final String? bodyHi;
  final String icon;
  final DateTime endsAt;
}

abstract interface class AppConfigApi {
  /// This salon's config. Null when there is no salon in the session.
  Future<AppConfig?> myAppConfig();

  /// Live announcements, soonest-ending first.
  Future<List<Announcement>> announcements();

  /// Fires when the salon's config row changes - the console saved something,
  /// or anything the pulse covers moved. Realtime; may never fire if the
  /// connection is down, which the regular re-read covers.
  Stream<void> configChanges(String salonId);
}
