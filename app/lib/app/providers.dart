import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/cache_db.dart';
import '../data/repositories/records_repository.dart';
import '../domain/join/cray_api.dart';
import '../domain/records/records.dart';
import '../features/join/join_controller.dart';

/// The read cache. One per app, closed by Riverpod when the scope dies.
final cacheDbProvider = Provider<CacheDb>((ref) {
  final db = CacheDb();
  ref.onDispose(db.close);
  return db;
});

/// Who is signed in. Overridden at startup from the stored session; null means
/// nobody, which is what a fresh install looks like.
final sessionProvider = Provider<AppSession?>((ref) => null);

/// Catalogue and records, cache first. Null until there is a salon to scope it
/// to - a screen that needs it is only reachable once there is.
final recordsRepositoryProvider = Provider<RecordsRepository?>((ref) {
  final session = ref.watch(sessionProvider);
  final salonId = session?.salonId;
  if (salonId == null) return null;

  final api = ref.watch(crayApiProvider);
  if (api is! SalonReads) return null;

  return RecordsRepository(
    remote: api as SalonReads,
    cache: ref.watch(cacheDbProvider),
    salonId: salonId,
  );
});

/// The catalogue lists. `Cached` carries whether the rows came from the network,
/// so the screen can say so rather than implying they are live.
final servicesProvider = FutureProvider<Cached<List<Service>>>((ref) async {
  final repo = ref.watch(recordsRepositoryProvider);
  if (repo == null) return const Cached([], fromCache: false);
  return repo.services();
});

final addOnsProvider = FutureProvider<Cached<List<AddOn>>>((ref) async {
  final repo = ref.watch(recordsRepositoryProvider);
  if (repo == null) return const Cached([], fromCache: false);
  return repo.addOns();
});

final staffProvider = FutureProvider<Cached<List<StaffMember>>>((ref) async {
  final repo = ref.watch(recordsRepositoryProvider);
  if (repo == null) return const Cached([], fromCache: false);
  return repo.staff();
});

final visitsProvider =
    FutureProvider.family<Cached<List<Visit>>, String>((ref, customerId) async {
  final repo = ref.watch(recordsRepositoryProvider);
  if (repo == null) return const Cached([], fromCache: false);
  return repo.visits(customerId);
});
