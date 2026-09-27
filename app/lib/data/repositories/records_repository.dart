import 'package:drift/drift.dart';

import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../local/cache_db.dart';

/// What a screen gets back: the rows, and whether they came from the network.
///
/// The distinction is shown, never hidden. A list that quietly serves week-old
/// data looks identical to a live one, and the owner finds out it was stale by
/// making a decision on it.
class Cached<T> {
  const Cached(this.value, {required this.fromCache, this.refreshedAt, this.problem});

  final T value;
  final bool fromCache;
  final DateTime? refreshedAt;

  /// Why the refresh failed, when it did. The cache is still served.
  final CrayErrorKind? problem;
}

/// Catalogue and records, cache first.
///
/// The contract for every read here: **ask the server, write what it says into
/// the cache, and return it; if the server cannot be reached, return the cache
/// and say so.** The cache is never a source of truth (ARCHITECTURE 10.2) - it
/// is the last thing the server said, which is exactly what the owner needs when
/// the salon's wi-fi drops mid-appointment.
class RecordsRepository {
  RecordsRepository({
    required this.remote,
    required this.cache,
    required this.salonId,
  });

  final SalonReads remote;
  final CacheDb cache;

  /// The one salon this install belongs to. Every cache read is filtered by it,
  /// so a transfer cannot leave the previous salon's rows on screen.
  final String salonId;

  Future<Cached<List<Service>>> services() => _list(
        key: 'services',
        fetch: remote.services,
        write: (rows) async {
          await cache.delete(cache.cachedServices).go();
          await cache.batch((b) => b.insertAll(
                cache.cachedServices,
                rows.map((s) => CachedService(
                      id: s.id,
                      salonId: salonId,
                      name: s.name,
                      pricePaise: s.pricePaise,
                      durationMinutes: s.durationMinutes,
                      active: s.active,
                    )),
              ));
        },
        read: () async {
          final rows = await (cache.select(cache.cachedServices)
                ..where((t) => t.salonId.equals(salonId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.active, mode: OrderingMode.desc),
                  (t) => OrderingTerm(expression: t.name),
                ]))
              .get();
          return rows
              .map((r) => Service(
                    id: r.id,
                    name: r.name,
                    pricePaise: r.pricePaise,
                    durationMinutes: r.durationMinutes,
                    active: r.active,
                  ))
              .toList();
        },
      );

  Future<Cached<List<AddOn>>> addOns() => _list(
        key: 'add_ons',
        fetch: remote.addOns,
        write: (rows) async {
          await cache.delete(cache.cachedAddOns).go();
          await cache.batch((b) => b.insertAll(
                cache.cachedAddOns,
                rows.map((a) => CachedAddOn(
                      id: a.id,
                      salonId: salonId,
                      name: a.name,
                      pricePaise: a.pricePaise,
                      extraDurationMinutes: a.extraDurationMinutes,
                      active: a.active,
                    )),
              ));
        },
        read: () async {
          final rows = await (cache.select(cache.cachedAddOns)
                ..where((t) => t.salonId.equals(salonId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.active, mode: OrderingMode.desc),
                  (t) => OrderingTerm(expression: t.name),
                ]))
              .get();
          return rows
              .map((r) => AddOn(
                    id: r.id,
                    name: r.name,
                    pricePaise: r.pricePaise,
                    extraDurationMinutes: r.extraDurationMinutes,
                    active: r.active,
                  ))
              .toList();
        },
      );

  Future<Cached<List<StaffMember>>> staff() => _list(
        key: 'staff',
        fetch: remote.staff,
        write: (rows) async {
          await cache.delete(cache.cachedStaffMembers).go();
          await cache.batch((b) => b.insertAll(
                cache.cachedStaffMembers,
                rows.map((s) => CachedStaff(
                      id: s.id,
                      salonId: salonId,
                      name: s.name,
                      active: s.active,
                    )),
              ));
        },
        read: () async {
          final rows = await (cache.select(cache.cachedStaffMembers)
                ..where((t) => t.salonId.equals(salonId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.active, mode: OrderingMode.desc),
                  (t) => OrderingTerm(expression: t.name),
                ]))
              .get();
          return rows.map((r) => StaffMember(id: r.id, name: r.name, active: r.active)).toList();
        },
      );

  /// The customer list. Only the FIRST page is cached: it is what the owner
  /// opens on, and caching an endless scroll would mean caching a query rather
  /// than data. A search is never served from the cache - a stale search result
  /// is worse than an honest "you are offline".
  Future<Cached<CustomerPage>> customers({String? search, CustomerCursor? after}) async {
    final searching = (search?.trim().isNotEmpty ?? false);
    try {
      final page = await remote.customers(search: search, after: after);
      if (!searching && after == null) {
        await cache.transaction(() async {
          await cache.delete(cache.cachedCustomers).go();
          await cache.batch((b) => b.insertAll(
                cache.cachedCustomers,
                page.customers.map((c) => CachedCustomer(
                      id: c.id,
                      salonId: salonId,
                      name: c.name,
                      phone: c.phone,
                      lastVisitAt: c.lastVisitAt,
                      balancePaise: c.balancePaise,
                      visitCount: c.visitCount,
                    )),
              ));
          await _stamp('customers');
        });
      }
      return Cached(page, fromCache: false, refreshedAt: DateTime.now());
    } on CrayApiException catch (e) {
      if (searching || after != null) rethrow;
      final rows = await (cache.select(cache.cachedCustomers)
            ..where((t) => t.salonId.equals(salonId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.lastVisitAt, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ]))
          .get();
      return Cached(
        CustomerPage(
          customers: rows
              .map((r) => CustomerSummary(
                    id: r.id,
                    name: r.name,
                    phone: r.phone,
                    lastVisitAt: r.lastVisitAt,
                    balancePaise: r.balancePaise,
                    visitCount: r.visitCount,
                  ))
              .toList(),
          cursor: null,
          // Offline, the cached first page is all there is. Claiming more would
          // produce a spinner that never resolves.
          hasMore: false,
        ),
        fromCache: true,
        refreshedAt: await _refreshedAt('customers'),
        problem: e.kind,
      );
    }
  }

  Future<Cached<List<Visit>>> visits(String customerId) => _list(
        key: 'visits:$customerId',
        fetch: () => remote.visits(customerId),
        write: (rows) async {
          await (cache.delete(cache.cachedVisits)
                ..where((t) => t.customerId.equals(customerId)))
              .go();
          await cache.batch((b) => b.insertAll(
                cache.cachedVisits,
                rows.map((v) => CachedVisit(
                      id: v.id,
                      salonId: salonId,
                      customerId: v.customerId,
                      completedAt: v.completedAt,
                      finalAmountPaise: v.finalAmountPaise,
                      serviceNames: v.serviceNames,
                    )),
              ));
        },
        read: () async {
          final rows = await (cache.select(cache.cachedVisits)
                ..where((t) => t.salonId.equals(salonId) & t.customerId.equals(customerId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
                ]))
              .get();
          return rows
              .map((r) => Visit(
                    id: r.id,
                    customerId: r.customerId,
                    completedAt: r.completedAt,
                    finalAmountPaise: r.finalAmountPaise,
                    serviceNames: r.serviceNames,
                  ))
              .toList();
        },
      );

  Future<Cached<List<T>>> _list<T>({
    required String key,
    required Future<List<T>> Function() fetch,
    required Future<void> Function(List<T>) write,
    required Future<List<T>> Function() read,
  }) async {
    try {
      final rows = await fetch();
      await cache.transaction(() async {
        await write(rows);
        await _stamp(key);
      });
      return Cached(rows, fromCache: false, refreshedAt: DateTime.now());
    } on CrayApiException catch (e) {
      return Cached(
        await read(),
        fromCache: true,
        refreshedAt: await _refreshedAt(key),
        problem: e.kind,
      );
    }
  }

  Future<void> _stamp(String key) => cache
      .into(cache.cacheStamps)
      .insertOnConflictUpdate(CacheStamp(key: key, refreshedAt: DateTime.now()));

  Future<DateTime?> _refreshedAt(String key) async {
    final row = await (cache.select(cache.cacheStamps)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.refreshedAt;
  }
}
