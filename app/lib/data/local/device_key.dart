import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random key for this install, used only to count rate limits against
/// something more specific than an IP address (migration 0030).
///
/// It is not an identity and must never become one: no phone number, no
/// hardware id, nothing derived from the person. A reinstall gets a new one,
/// which is the correct trade - a rate limit is not worth tracking someone for.
class DeviceKey {
  static const _key = 'cray.device_key';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.length == 32) return existing;

    final random = Random.secure();
    final fresh = List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_key, fresh);
    return fresh;
  }
}
