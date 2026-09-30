import 'package:craysalon/domain/customer/customer.dart';
import 'package:craysalon/domain/join/cray_api.dart';
import 'package:craysalon/domain/records/records.dart';

import 'fake_cray_api.dart';

/// The server as a signed-in CUSTOMER sees it: their own rows, the salon's
/// catalogue, and the booking calls. Owner-only calls are not implemented -
/// a customer screen that reached one would fail the test loudly.
class FakeCustomerApi extends FakeCrayApi implements CustomerApi, SalonReads, SalonBookings {
  FakeCustomerApi() {
    sessionValue = const AppSession(appRole: 'customer', salonId: '11111111-0000-4000-8000-000000000001');
  }

  CustomerProfile? profile = const CustomerProfile(name: 'Asha Rao', phone: '9812344821');
  NextDue? due;
  List<UpcomingBooking> upcomingList = [];
  List<PastVisit> visitsList = [];

  List<Service> serviceList = const [
    Service(id: 's-cut', name: 'Haircut', pricePaise: 60000, durationMinutes: 45, active: true, category: 'Hair'),
    Service(id: 's-wash', name: 'Hair wash and blow-dry', pricePaise: 40000, durationMinutes: 30, active: true, category: 'Hair'),
    Service(id: 's-beard', name: 'Beard trim', pricePaise: 30000, durationMinutes: 20, active: true, category: 'Beard'),
    Service(id: 's-old', name: 'Retired service', pricePaise: 10000, durationMinutes: 10, active: false),
  ];
  List<AddOn> addOnList = const [
    AddOn(id: 'a-massage', name: 'Head massage', pricePaise: 15000, extraDurationMinutes: 15, active: true),
  ];
  List<StaffMember> staffList = const [
    StaffMember(id: 'st-suresh', name: 'Suresh', active: true),
    StaffMember(id: 'st-priya', name: 'Priya', active: true),
  ];

  /// Times offered for any day: 10:00 (Suresh), 10:00 (Priya), 12:00 (Priya),
  /// on the day asked about - tomorrow onwards, so none are in the past.
  List<Slot> Function(DateTime day, String? staffId) slotsFor = (day, staffId) {
    Slot at(int h, String staff) => Slot(
          staffId: staff,
          startsAt: DateTime(day.year, day.month, day.day, h),
          endsAt: DateTime(day.year, day.month, day.day, h, 45),
        );
    return [
      at(10, 'st-suresh'),
      at(10, 'st-priya'),
      at(12, 'st-priya'),
    ].where((s) => staffId == null || s.staffId == staffId).toList();
  };

  final List<Map<String, Object?>> slotQueries = [];
  final List<Map<String, Object?>> bookings = [];
  final List<Map<String, Object?>> cancels = [];

  /// Errors for the next createBooking calls, in order; empty = succeed.
  final List<CrayApiException> bookErrors = [];

  @override
  Future<CustomerProfile?> me() async => profile;

  @override
  Future<NextDue?> nextDue() async => due;

  @override
  Future<List<UpcomingBooking>> upcoming() async => upcomingList;

  @override
  Future<UpcomingBooking?> booking(String id) async =>
      upcomingList.where((b) => b.id == id).firstOrNull;

  @override
  Future<List<PastVisit>> history({int limit = 30}) async => visitsList;

  @override
  Future<List<Service>> services() async => serviceList;

  @override
  Future<List<AddOn>> addOns() async => addOnList;

  @override
  Future<List<StaffMember>> staff() async => staffList;

  @override
  Future<List<Slot>> slots({
    required String serviceId,
    required DateTime day,
    String? staffId,
    List<String> addOnIds = const [],
  }) async {
    slotQueries.add({'service': serviceId, 'day': day, 'staff': staffId, 'addOns': addOnIds});
    return slotsFor(day, staffId);
  }

  @override
  Future<String> createBooking({
    required String clientActionId,
    required String serviceId,
    required DateTime startsAt,
    String? staffId,
    String? customerId,
    List<String> addOnIds = const [],
    String? notes,
  }) async {
    bookings.add({
      'action': clientActionId,
      'service': serviceId,
      'startsAt': startsAt,
      'staff': staffId,
      'customer': customerId,
      'addOns': addOnIds,
    });
    if (bookErrors.isNotEmpty) throw bookErrors.removeAt(0);
    final id = 'b-${bookings.length}';
    upcomingList = [
      ...upcomingList,
      UpcomingBooking(
        id: id,
        startsAt: startsAt,
        endsAt: startsAt.add(const Duration(minutes: 45)),
        status: 'confirmed',
        totalPaise: 60000,
        serviceNames: 'Haircut',
        staffName: staffList.where((s) => s.id == staffId).firstOrNull?.name,
      ),
    ];
    return id;
  }

  @override
  Future<void> cancelBooking({
    required String clientActionId,
    required String bookingId,
    String? reason,
  }) async {
    cancels.add({'action': clientActionId, 'booking': bookingId});
    upcomingList = [
      for (final b in upcomingList)
        b.id == bookingId
            ? UpcomingBooking(
                id: b.id,
                startsAt: b.startsAt,
                endsAt: b.endsAt,
                status: 'cancelled',
                totalPaise: b.totalPaise,
                serviceNames: b.serviceNames,
                staffName: b.staffName,
              )
            : b,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a customer screen called ${invocation.memberName}');
}
