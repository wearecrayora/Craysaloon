/// The salon's catalogue and its records, as the app understands them.
///
/// Pure Dart: no Supabase, no Drift (`ARCHITECTURE.md` 9.1). Money is always
/// `int` **paise** - never a double, anywhere, ever (ADR-06).
library;

class Service {
  const Service({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.durationMinutes,
    required this.active,
  });

  final String id;
  final String name;
  final int pricePaise;
  final int durationMinutes;
  final bool active;
}

class AddOn {
  const AddOn({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.extraDurationMinutes,
    required this.active,
  });

  final String id;
  final String name;
  final int pricePaise;
  final int extraDurationMinutes;
  final bool active;
}

class StaffMember {
  const StaffMember({required this.id, required this.name, required this.active});

  final String id;
  final String name;
  final bool active;
}

/// A row of the owner's customer list (screen O4).
///
/// [balancePaise] is **read-only everywhere in this app**. There is no adjust
/// control, no endpoint and no permission (`RULES.md` §2, §5.2): if a screen
/// sketch contains one, the sketch is wrong.
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.lastVisitAt,
    required this.balancePaise,
    required this.visitCount,
    this.loyaltyPoints = 0,
    this.tier,
  });

  final String id;
  final String? name;
  final String? phone;
  final DateTime? lastVisitAt;
  final int balancePaise;
  final int visitCount;
  final int loyaltyPoints;
  final String? tier;
}

/// Where the last page ended. Keyset, not a page number: the list is sorted by
/// (lastVisitAt, id), so the cursor is those two values and nothing else can
/// make a row repeat or vanish while someone scrolls.
class CustomerCursor {
  const CustomerCursor({required this.lastVisitAt, required this.id});

  final DateTime? lastVisitAt;
  final String id;
}

class CustomerPage {
  const CustomerPage({required this.customers, required this.cursor, required this.hasMore});

  final List<CustomerSummary> customers;

  /// Pass back to fetch the next page; null when this is the end.
  final CustomerCursor? cursor;
  final bool hasMore;
}

class Visit {
  const Visit({
    required this.id,
    required this.customerId,
    required this.completedAt,
    required this.finalAmountPaise,
    this.serviceNames = '',
  });

  final String id;
  final String customerId;
  final DateTime completedAt;
  final int finalAmountPaise;
  final String serviceNames;
}

/// Everything the owner's records screens read. Implemented against Supabase in
/// `data/remote`, and faked in tests - the screens never know which.
abstract interface class SalonReads {
  Future<List<Service>> services();

  Future<List<AddOn>> addOns();

  Future<List<StaffMember>> staff();

  /// One page of the customer list. [search] is a name prefix or a WHOLE phone
  /// number; there is deliberately no partial-number search (`RULES.md` 4.7).
  Future<CustomerPage> customers({String? search, CustomerCursor? after, int limit = 20});

  Future<List<Visit>> visits(String customerId, {int limit = 20});
}
