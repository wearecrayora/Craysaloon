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

/// When each list was last refreshed, so a screen can say "as of …" rather than
/// implying cached data is live.
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
    CacheStamps,
  ],
)
class CacheDb extends _$CacheDb {
  CacheDb([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'cray_cache'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // A read cache has nothing worth migrating: throw it away and let the
          // next refresh refill it. Attempting a careful migration of data that
          // is a copy anyway is how a cache becomes a liability.
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
        },
      );

  /// Called when the binding changes - a transfer, an unbind, a sign-out. The
  /// next salon must never inherit the last one's rows.
  Future<void> wipe() => transaction(() async {
        for (final table in allTables) {
          await delete(table).go();
        }
      });
}
