import 'package:craysalon/data/local/branding_store.dart';
import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/local/cache_lifecycle.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'records_repository_test.dart' show FakeReads;
import 'support/fake_cray_api.dart';

/// What a transfer or an unbind looks like ON THE PHONE.
///
/// The server ends those sessions (0035), so the app comes back either signed
/// out or signed in to a different salon. Until this was wired, `wipe()` and
/// `clear()` existed, were tested, and **were never called** - so the device
/// would have kept wearing the old salon's brand and showing its cached customer
/// list. Showing another salon's branding is worse than showing none
/// (`RULES.md` 8.6, `DESIGN.md` 3.3), and cached rows from a salon this device
/// is no longer bound to are a leak already sitting on the phone.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late CacheDb cache;
  late BrandingStore store;
  late RecordsRepository repo;
  late FakeReads reads;

  const salonA = '11111111-0000-4000-8000-00000000000a';
  const salonB = '11111111-0000-4000-8000-00000000000b';

  setUp(() async {
    cache = CacheDb(NativeDatabase.memory());
    store = BrandingStore();
    reads = FakeReads()
      ..serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
      ];
    repo = RecordsRepository(remote: reads, cache: cache, salonId: salonA);

    // A bound device: branding stored, catalogue cached.
    await store.save(
      salonId: salonA,
      displayName: 'Studio Nine Salon',
      version: 3,
      document: publishedBranding(),
    );
    await repo.services();
  });

  tearDown(() => cache.close());

  Future<int> cachedServiceCount() async =>
      (await cache.select(cache.cachedServices).get()).length;

  test('a session for the SAME salon keeps everything - the normal open', () async {
    final branding = await brandingForSession(
      const AppSession(appRole: 'customer', salonId: salonA),
      store: store,
      cache: cache,
    );

    expect(branding?.displayName, 'Studio Nine Salon');
    expect(await cachedServiceCount(), 1);
  });

  test('a session for ANOTHER salon wipes the last one - this is a transfer', () async {
    final branding = await brandingForSession(
      const AppSession(appRole: 'customer', salonId: salonB),
      store: store,
      cache: cache,
    );

    expect(branding, isNull, reason: 'the new salon has not published to this device yet');
    expect(await store.read(), isNull, reason: 'never wear the previous salon\'s brand');
    expect(await cachedServiceCount(), 0, reason: 'nor show its rows');
  });

  test('no session wipes it too - this is an unbind, or a sign-out', () async {
    final branding = await brandingForSession(null, store: store, cache: cache);

    expect(branding, isNull);
    expect(await store.read(), isNull);
    expect(await cachedServiceCount(), 0);
  });

  test('an unbound customer is treated as signed out', () async {
    // customer_unbound carries no salon_id (0034), so there is nothing the
    // cached rows could still belong to.
    final branding = await brandingForSession(
      const AppSession(appRole: 'customer_unbound', salonId: null),
      store: store,
      cache: cache,
    );

    expect(branding, isNull);
    expect(await cachedServiceCount(), 0);
  });

  test('a device with nothing cached is not an error', () async {
    await store.clear();
    await cache.wipe();

    final branding = await brandingForSession(
      const AppSession(appRole: 'customer', salonId: salonA),
      store: store,
      cache: cache,
    );
    expect(branding, isNull);
  });
}
