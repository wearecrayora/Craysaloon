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

/// Changing the catalogue.
///
/// **Only an owner or a manager can do any of this, and that is enforced in the
/// database** (migration 0041), not by hiding buttons: a customer, a stylist or
/// a stolen session is refused by a policy, whatever the app sends. The app hides
/// the controls as a courtesy, so nobody is invited to fail.
///
/// Nothing here is queued offline. Catalogue edits are not in the offline set
/// (`ARCHITECTURE.md` 10.1) - the day's work is, and the outbox that carries it
/// arrives with M6. A change that cannot reach the server is reported as not
/// saved, rather than held somewhere the owner cannot see it.
abstract interface class SalonWrites {
  /// [id] null creates, non-null updates. Returns the id either way.
  Future<String> saveService({
    String? id,
    required String name,
    required int pricePaise,
    required int durationMinutes,
    required bool active,
  });

  Future<String> saveAddOn({
    String? id,
    required String name,
    required int pricePaise,
    required int extraDurationMinutes,
    required bool active,
  });

  Future<String> saveStaff({String? id, required String name, required bool active});
}

/// An appointment, as the day view shows it.
class BookingRow {
  const BookingRow({
    required this.id,
    required this.customerId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.totalPaise,
    this.customerName,
    this.staffName,
    this.serviceNames = '',
    this.paymentStatus,
    this.customerHasApp = false,
    this.counterRequested = false,
  });

  final String id;
  final String customerId;
  final DateTime startsAt;
  final DateTime endsAt;

  /// pending | confirmed | in_progress | completed | cancelled | no_show
  final String status;
  final int totalPaise;
  final String? customerName;
  final String? staffName;
  final String serviceNames;

  /// The visit's settlement: unpaid | partial | paid. Null until the booking
  /// has become a visit. Comes from the SERVER - the app never decides that
  /// money arrived (RULES 9: money does not move offline).
  final String? paymentStatus;

  /// Booked and not yet begun: the row offers START, with the customer's code
  /// when they have the app (0084).
  bool get isOpen => status == 'pending' || status == 'confirmed';

  /// In the chair. The row offers mark-complete - still one tap (RULES 13).
  bool get isInProgress => status == 'in_progress';

  /// Done, and the money not yet taken. What the "Take payment" action is for.
  bool get awaitsPayment => status == 'completed' && paymentStatus != 'paid';

  /// Whether the customer can show a start code at all. Without the app there
  /// is no code to read out, and the stylist starts without one - allowed, and
  /// counted on the owner's dashboard (decision of 29 Sep 2026).
  final bool customerHasApp;

  /// The customer said they will pay at the counter. It settles nothing - staff
  /// still take the money (decision of 29 Sep 2026); it only tells the counter.
  final bool counterRequested;

  /// The same row in a new state - what the screen shows the moment a tap
  /// lands, before the server has answered.
  BookingRow withStatus(String next) => BookingRow(
        id: id,
        customerId: customerId,
        startsAt: startsAt,
        endsAt: endsAt,
        status: next,
        totalPaise: totalPaise,
        customerName: customerName,
        staffName: staffName,
        serviceNames: serviceNames,
        paymentStatus: paymentStatus,
        customerHasApp: customerHasApp,
        counterRequested: counterRequested,
      );
}

/// Why a start was refused. Each is a different sentence to the stylist, which
/// is the only reason they are separate.
enum StartRefusal {
  /// Not the customer's code. [StartResult.attemptsLeft] says how many remain.
  wrongCode,

  /// Five wrong guesses. The code cannot be used now; start without it.
  codeLocked,

  /// The customer never opened this booking in their app, so no code exists.
  noCodeIssued,

  /// Already completed, cancelled, or a no-show.
  notStartable,
}

class StartResult {
  const StartResult.started() : refusal = null, attemptsLeft = null;
  const StartResult.refused(StartRefusal this.refusal, {this.attemptsLeft});

  final StartRefusal? refusal;
  final int? attemptsLeft;

  bool get started => refusal == null;
}

class Slot {
  const Slot({required this.staffId, required this.startsAt, required this.endsAt});

  final String staffId;
  final DateTime startsAt;
  final DateTime endsAt;
}

/// What a checkout WOULD do, from the server, before anyone collects cash.
///
/// Online only, on purpose. Offline the wallet balance on the phone is a cached
/// copy, and a split guessed from it could have the server record cash the
/// owner never collected (0080). When this cannot be fetched, the screen says
/// so and does not guess.
class CheckoutQuote {
  const CheckoutQuote({
    required this.duePaise,
    required this.walletAvailablePaise,
    required this.fromWalletPaise,
    required this.fromCounterPaise,
  });

  final int duePaise;
  final int walletAvailablePaise;
  final int fromWalletPaise;

  /// What the owner collects in cash, UPI or card.
  final int fromCounterPaise;

  bool get alreadyPaid => duePaise == 0;
}

/// The day's work: what is booked, and the writes that change it.
///
/// Every write takes a `clientActionId` the CALLER generates and reuses for
/// every retry (`RULES.md` 9.3). That is what lets the app send the same
/// instruction twice - which offline guarantees it will - without doing the work
/// twice. The server decides everything else: a race for the same chair, whether
/// a booking can still be completed, whether this account may.
abstract interface class SalonBookings {
  Future<List<BookingRow>> bookingsOn(DateTime day);

  Future<List<Slot>> slots({
    required String serviceId,
    required DateTime day,
    String? staffId,
    List<String> addOnIds = const [],
  });

  /// Returns the booking id. Throws [CrayApiException] with
  /// [CrayErrorKind.slotTaken] when the chair went to someone else.
  Future<String> createBooking({
    required String clientActionId,
    required String serviceId,
    required DateTime startsAt,
    String? staffId,
    String? customerId,
    List<String> addOnIds = const [],
    String? notes,
  });

  Future<void> markComplete({
    required String clientActionId,
    required String bookingId,
    int? finalAmountPaise,
    int tipPaise = 0,
  });

  Future<void> cancelBooking({
    required String clientActionId,
    required String bookingId,
    String? reason,
  });

  /// Settles the visit a booking became: the customer's wallet first, as far as
  /// it goes, the rest by [method] at the counter. The AMOUNT is the server's,
  /// from the visit - never a number the app sends (0069).
  Future<void> checkout({
    required String clientActionId,
    required String bookingId,
    bool useWallet = true,
    String method = 'cash',
  });

  /// Online only. Throws [CrayApiException] with [CrayErrorKind.network] when
  /// there is no connection - which the screen treats as "cannot check", never
  /// as a zero balance.
  Future<CheckoutQuote> checkoutQuote(String bookingId);

  /// Starts a booked service. With [code], the server checks it against the
  /// customer's; without, it starts anyway and records why (0084). Throws
  /// [CrayApiException] with [CrayErrorKind.network] when there is no
  /// connection - the caller then offers to start without the code.
  Future<StartResult> startService({
    required String clientActionId,
    required String bookingId,
    String? code,
  });
}
