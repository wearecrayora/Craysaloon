import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The salon's branding, kept on the device.
///
/// `DESIGN.md` 3.3 and PRD §15: the cached document is authoritative offline, so
/// a customer opening the app on a train still sees their salon rather than a
/// half-themed screen. Only ever ONE salon's branding is stored - the salon this
/// install is bound to - because showing another salon's brand would be worse
/// than showing none (`RULES.md` 8.6).
class BrandingStore {
  static const _key = 'cray.branding';

  /// Branding is public-facing: a name, colours, a logo URL. Nothing here is
  /// personal data, so plain preferences are the right storage.
  Future<void> save({
    required String salonId,
    required String displayName,
    required int version,
    required Map<String, Object?> document,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'salon_id': salonId,
        'display_name': displayName,
        'version': version,
        'document': document,
      }),
    );
  }

  Future<CachedBranding?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final document = map['document'];
      return CachedBranding(
        salonId: map['salon_id'] as String? ?? '',
        displayName: map['display_name'] as String? ?? '',
        version: (map['version'] as num?)?.toInt() ?? 0,
        document: document is Map ? document.cast<String, Object?>() : const {},
      );
    } catch (_) {
      // A cache we cannot read is a cache we do not have. The app falls back to
      // the neutral default rather than failing to start.
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class CachedBranding {
  const CachedBranding({
    required this.salonId,
    required this.displayName,
    required this.version,
    required this.document,
  });

  final String salonId;
  final String displayName;
  final int version;
  final Map<String, Object?> document;
}
