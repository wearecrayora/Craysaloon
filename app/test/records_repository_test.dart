import 'package:craysalon/data/local/cache_db.dart';
import 'package:craysalon/data/repositories/records_repository.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The read cache, and the promise it makes: **the owner's lists work when the
/// wi-fi does not**, and the app says when what it is showing came from this
/// device rather than the server (`ARCHITECTURE.md` 10.1, 10.2).
class FakeReads implements SalonReads {
  FakeReads();

  List<Service> serviceRows = const [];
  List<CustomerSummary> customerRows = const [];
  List<Visit> visitRows = const [];
  CrayApiException? failure;

  int serviceCalls = 0;
  final List<CustomerCursor?> cursors = [];
  final List<String?> searches = [];

  @override
  Future<List<Service>> services() async {
    serviceCalls++;
    if (failure != null) throw failure!;
    return serviceRows;
  }

  @override
  Future<List<AddOn>> addOns() async {
    if (failure != null) throw failure!;
    return const [];
  }

  @override
  Future<List<StaffMember>> staff() async {
    if (failure != null) throw failure!;
    return const [];
  }

  @override
  Future<CustomerPage> customers({
    String? search,
    CustomerCursor? after,
    int limit = 20,
  }) async {
    searches.add(search);
    cursors.add(after);
    if (failure != null) throw failure!;

    // Search the way list_customers does: a name prefix, or a WHOLE number.
    // Honouring it here matters - a fake that returns everything regardless
    // would let a screen claim a search works when it does not.
    final query = search?.trim().toLowerCase();
    final filtered = (query == null || query.isEmpty)
        ? customerRows
        : customerRows.where((c) {
            final digits = query.replaceAll(RegExp('[^0-9]'), '');
            if (digits.length >= 10) return c.phone == digits;
            return (c.name ?? '').toLowerCase().startsWith(query);
          }).toList();

    // Page by the cursor, exactly as the server would: everything strictly
    // after (lastVisitAt, id) in the list's own order.
    final sorted = [...filtered]..sort((a, b) {
        final aTime = a.lastVisitAt;
        final bTime = b.lastVisitAt;
        if (aTime == null && bTime != null) return 1;
        if (aTime != null && bTime == null) return -1;
        final byTime = aTime == null ? 0 : bTime!.compareTo(aTime);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });

    var rows = sorted;
    if (after != null) {
      final index = sorted.indexWhere((c) => c.id == after.id);
      rows = index < 0 ? const [] : sorted.sublist(index + 1);
    }

    final page = rows.take(limit).toList();
    final hasMore = rows.length > limit;
    return CustomerPage(
      customers: page,
      cursor: page.isEmpty || !hasMore
          ? null
          : CustomerCursor(lastVisitAt: page.last.lastVisitAt, id: page.last.id),
      hasMore: hasMore,
    );
  }

  @override
  Future<List<Visit>> visits(String customerId, {int limit = 20}) async {
    if (failure != null) throw failure!;
    return visitRows.where((v) => v.customerId == customerId).toList();
  }
}

CustomerSummary customer(String id, {DateTime? lastVisit, int balance = 0}) => CustomerSummary(
      id: id,
      name: 'Customer $id',
      phone: '98555000${id.padLeft(2, '0')}',
      lastVisitAt: lastVisit,
      balancePaise: balance,
      visitCount: 0,
    );

void main() {
  late CacheDb cache;
  late FakeReads remote;
  late RecordsRepository repo;

  setUp(() {
    // In-memory, so each test starts with an empty cache and nothing is left on
    // the machine running the suite.
    cache = CacheDb(NativeDatabase.memory());
    remote = FakeReads();
    repo = RecordsRepository(remote: remote, cache: cache, salonId: 'salon-a');
  });

  tearDown(() => cache.close());

  group('the catalogue', () {
    test('comes from the server and is kept', () async {
      remote.serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
      ];

      final fresh = await repo.services();
      expect(fresh.fromCache, isFalse);
      expect(fresh.value.single.name, 'Haircut');

      // Now the wi-fi drops.
      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.services();

      expect(cached.fromCache, isTrue, reason: 'the screen must be able to say so');
      expect(cached.value.single.name, 'Haircut');
      expect(cached.refreshedAt, isNotNull, reason: '"as of" needs a time to show');
      expect(cached.problem, CrayErrorKind.network);
    });

    test('a refresh replaces rather than accumulates', () async {
      remote.serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
        Service(id: 's2', name: 'Shave', pricePaise: 15000, durationMinutes: 15, active: true),
      ];
      await repo.services();

      // Shave is withdrawn from the menu.
      remote.serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
      ];
      await repo.services();

      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.services();
      expect(cached.value.map((s) => s.id), ['s1'],
          reason: 'a deleted service must not live on in the cache');
    });

    test('an empty cache offline is empty, not an error', () async {
      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.services();
      expect(cached.value, isEmpty);
      expect(cached.fromCache, isTrue);
      expect(cached.refreshedAt, isNull, reason: 'never loaded - the screen says exactly that');
    });
  });

  group('the customer list', () {
    test('pages by cursor, with no repeat and no gap', () async {
      final now = DateTime.now();
      remote.customerRows = [
        for (var i = 0; i < 5; i++)
          customer('c$i', lastVisit: now.subtract(Duration(days: i))),
      ];

      final first = await repo.customers();
      expect(first.value.customers.map((c) => c.id), ['c0', 'c1', 'c2', 'c3', 'c4']);

      final page = await remote.customers(limit: 2);
      expect(page.customers.map((c) => c.id), ['c0', 'c1']);
      final next = await remote.customers(after: page.cursor, limit: 2);
      expect(next.customers.map((c) => c.id), ['c2', 'c3'],
          reason: 'the cursor continues, it does not restart');
    });

    test('only the first page is cached, and it is served offline', () async {
      final now = DateTime.now();
      remote.customerRows = [customer('c0', lastVisit: now, balance: 55000)];
      await repo.customers();

      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.customers();

      expect(cached.fromCache, isTrue);
      expect(cached.value.customers.single.balancePaise, 55000);
      expect(cached.value.hasMore, isFalse,
          reason: 'offline there is no next page, and a spinner that never ends is worse');
    });

    test('a SEARCH is never answered from the cache', () async {
      remote.customerRows = [customer('c0', lastVisit: DateTime.now())];
      await repo.customers();

      remote.failure = const CrayApiException(CrayErrorKind.network);

      // A stale search result is worse than an honest "you are offline": it
      // looks like an answer about who is a customer.
      expect(
        () => repo.customers(search: 'Customer'),
        throwsA(isA<CrayApiException>()),
      );
    });

    test('a later page is never faked from the cache either', () async {
      remote.customerRows = [customer('c0', lastVisit: DateTime.now())];
      await repo.customers();
      remote.failure = const CrayApiException(CrayErrorKind.network);

      expect(
        () => repo.customers(after: const CustomerCursor(lastVisitAt: null, id: 'c0')),
        throwsA(isA<CrayApiException>()),
      );
    });
  });

  group('visit history', () {
    test('is cached per customer, and does not leak across customers', () async {
      final now = DateTime.now();
      remote.visitRows = [
        Visit(id: 'v1', customerId: 'c1', completedAt: now, finalAmountPaise: 40000),
        Visit(id: 'v2', customerId: 'c2', completedAt: now, finalAmountPaise: 15000),
      ];

      await repo.visits('c1');
      await repo.visits('c2');

      remote.failure = const CrayApiException(CrayErrorKind.network);
      final c1 = await repo.visits('c1');
      final c2 = await repo.visits('c2');

      expect(c1.value.map((v) => v.id), ['v1']);
      expect(c2.value.map((v) => v.id), ['v2']);
    });
  });

  group('the cache belongs to ONE salon', () {
    test('another salon\'s repository sees nothing of the first\'s', () async {
      remote.serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
      ];
      await repo.services();

      // What a transfer looks like before the wipe runs: the same device, a
      // different salon. It must not inherit the previous salon's menu.
      final other = RecordsRepository(remote: remote, cache: cache, salonId: 'salon-b');
      remote.failure = const CrayApiException(CrayErrorKind.network);

      final cached = await other.services();
      expect(cached.value, isEmpty);
    });

    test('wipe clears everything, for an unbind or a transfer', () async {
      remote.serviceRows = const [
        Service(id: 's1', name: 'Haircut', pricePaise: 40000, durationMinutes: 30, active: true),
      ];
      await repo.services();
      await cache.wipe();

      remote.failure = const CrayApiException(CrayErrorKind.network);
      final cached = await repo.services();
      expect(cached.value, isEmpty);
      expect(cached.refreshedAt, isNull);
    });
  });
}
