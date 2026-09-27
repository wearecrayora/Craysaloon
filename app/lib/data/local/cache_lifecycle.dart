import '../../domain/join/cray_api.dart';
import 'branding_store.dart';
import 'cache_db.dart';

/// Decides, at startup, whether what is on this device still belongs to whoever
/// is signed in.
///
/// This is the moment a transfer or an unbind becomes visible on the phone. The
/// server ends those sessions (0035), so the app comes back with **no session**
/// or with a session naming a **different salon** - and the branding and rows
/// cached from the old one must not survive either case. Showing another salon's
/// brand is worse than showing none (`RULES.md` 8.6, `DESIGN.md` 3.3), and a
/// cached customer list from a salon this device is no longer bound to is a
/// small data leak that no policy can catch, because it is already on the phone.
///
/// Returns the branding the app should wear: the cached document when it still
/// belongs to this session, otherwise null - and the neutral default with it.
Future<CachedBranding?> brandingForSession(
  AppSession? session, {
  required BrandingStore store,
  required CacheDb cache,
}) async {
  final cached = await store.read();
  if (cached == null) return null;

  // Signed out - including the sign-out a transfer or an unbind forces. The join
  // screen starts neutral, not wearing the salon someone just left.
  //
  // A staff session has a salon but no customer binding; the same rule reads
  // correctly for it, because the salon is what the cache is keyed on.
  final salonId = session?.salonId;
  if (salonId == null || salonId != cached.salonId) {
    await store.clear();
    await cache.wipe();
    return null;
  }

  return cached;
}
