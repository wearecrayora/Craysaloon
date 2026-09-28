import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/join/cray_api.dart';

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
    GrievanceContact? grievance,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'salon_id': salonId,
        'display_name': displayName,
        'version': version,
        'document': document,
        // The salon's privacy contact rides with the branding because it is the
        // same kind of thing - published business information about the salon,
        // not personal data - and because "Your data" must be able to show
        // somebody to complain to on a phone with no signal. A complaint that
        // needs connectivity is a complaint that does not get made.
        if (grievance != null)
          'grievance': {
            'name': grievance.name,
            'email': grievance.email,
            'phone': grievance.phone,
          },
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
        grievance: GrievanceContact.fromJson(
          map['grievance'] is Map
              ? (map['grievance']! as Map).cast<String, Object?>()
              : null,
        ),
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
    this.grievance,
  });

  final String salonId;
  final String displayName;
  final int version;
  final Map<String, Object?> document;

  /// Who at the salon answers a data question (DPDP ss.5, 13). Null for a salon
  /// activated before the contact became mandatory, and for a cache written by
  /// an older build - the notice degrades rather than inventing a name.
  final GrievanceContact? grievance;
}
