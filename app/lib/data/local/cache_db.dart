import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'cache_db.g.dart';

/// The **read cache**: last-known server state, safe to discard (ARCHITECTURE
/// 10.2).
///
/// Two rules this file exists to keep:
///
/// 1. **Nothing here is a source of truth.** Every row is a copy of something
///    the server said, kept so the owner's day works on salon wi-fi. Deleting
///    this database must never lose anything - the outbox (M6) is the only local
///    source of truth, and it is a separate concern on purpose.
/// 2. **One salon per install.** Every table carries `salonId` and every read is
///    filtered by it, so a transfer or an unbind cannot leave another salon's
///    rows visible. [wipe] exists for exactly that moment.
///
/// Money is cached as `int` **paise**, like everywhere else - never a double.

@DataClassName('CachedService')
class CachedServices extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get name => text()();
  IntColumn get pricePaise => integer()();
  IntColumn get durationMinutes => integer()();
  BoolColumn get active => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CachedAddOn')
class CachedAddOns extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get name => text()();
  IntColumn get pricePaise => integer()();
  IntColumn get extraDurationMinutes => integer()();
  BoolColumn get active => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CachedStaff')
class CachedStaffMembers extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get name => text()();
  BoolColumn get active => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CachedCustomer')
class CachedCustomers extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get name => text().nullable()();
  TextColumn get phone => text().nullable()();
  DateTimeColumn get lastVisitAt => dateTime().nullable()();
  IntColumn get balancePaise => integer().withDefault(const Constant(0))();
  IntColumn get visitCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CachedVisit')
class CachedVisits extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get customerId => text()();
  DateTimeColumn get completedAt => dateTime()();
  IntColumn get finalAmountPaise => integer()();
  TextColumn get serviceNames => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// **The outbox: the only local source of truth in this database.**
///
/// Everything else here is a copy of something the server said and can be thrown
/// away. These rows are the opposite - they are work the owner did that the
/// server has NOT accepted yet (`ARCHITECTURE.md` 10.2), so they survive the
/// cache being wiped, survive an app upgrade, and are never dropped silently: a
/// rejected row goes to "Needs attention" with its reason (`RULES.md` 9.6).
@DataClassName('OutboxAction')
class OutboxActions extends Table {
  /// The idempotency key the server dedupes on (RULES 9.3). Generated once, on
  /// this device, and reused for every retry - which is what makes a replay a
  /// no-op rather than a second booking.
  TextColumn get clientActionId => text()();

  TextColumn get salonId => text()();

  /// mark_visit_complete | create_booking | cancel_booking
  TextColumn get op => text()();

  /// The call's arguments, as JSON. Deliberately opaque to the cache: the
  /// server's function signature is the contract, not a local table shape.
  TextColumn get payload => text()();

  /// pending | syncing | applied | rejected
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Why the server said no, in words a person can act on.
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientActionId};
}

/// When each list was last refreshed, so a screen can say "as of …" rather than
/// implying cached data is live.
/// Today's appointments, cached so the day view opens on salon wi-fi.
@DataClassName('CachedBooking')
class CachedBookings extends Table {
  TextColumn get id => text()();
  TextColumn get salonId => text()();
  TextColumn get customerId => text()();
  TextColumn get customerName => text().nullable()();
  TextColumn get staffName => text().nullable()();
  TextColumn get serviceNames => text().withDefault(const Constant(''))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  IntColumn get totalPaise => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CacheStamp')
class CacheStamps extends Table {
  TextColumn get key => text()();
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    CachedServices,
    CachedAddOns,
    CachedStaffMembers,
    CachedCustomers,
    CachedVisits,
    CachedBookings,
    CacheStamps,
    OutboxActions,
  ],
)
class CacheDb extends _$CacheDb {
  CacheDb([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'cray_cache'));

  @override
  int get schemaVersion => 2;

  /// Every table that is a COPY of server state, and may be thrown away.
  /// [outboxActions] is deliberately absent: it is not a copy of anything.
  List<TableInfo<Table, dynamic>> get _cacheTables => [
        cachedServices,
        cachedAddOns,
        cachedStaffMembers,
        cachedCustomers,
        cachedVisits,
        cachedBookings,
        cacheStamps,
      ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // A read cache has nothing worth migrating: throw it away and let the
          // next refresh refill it. Attempting a careful migration of data that
          // is a copy anyway is how a cache becomes a liability.
          //
          // THE OUTBOX IS NOT IN THAT LIST. It holds work the server has not
          // accepted yet, so an app update must not discard it - that would be
          // losing a morning of mark-completes to a routine release.
          for (final table in _cacheTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
        },
      );

  /// Called when the binding changes - a transfer, an unbind, a sign-out. The
  /// next salon must never inherit the last one's rows.
  ///
  /// Again, not the outbox: unsent work is not the new salon's, but it is not
  /// ours to delete either. [rejectOutboxFor] marks it instead, so it surfaces
  /// in "Needs attention" rather than vanishing (RULES 9.6).
  Future<void> wipe() => transaction(() async {
        for (final table in _cacheTables) {
          await delete(table).go();
        }
      });

  /// Unsent work that belongs to a salon this device no longer serves. Marked,
  /// never deleted - someone did that work, and they are owed an explanation.
  Future<int> rejectOutboxFor(String salonId, String reason) {
    return (update(outboxActions)
          ..where((t) => t.salonId.equals(salonId) & t.status.isIn(['pending', 'syncing'])))
        .write(OutboxActionsCompanion(
      status: const Value('rejected'),
      lastError: Value(reason),
      updatedAt: Value(DateTime.now()),
    ));
  }
}
