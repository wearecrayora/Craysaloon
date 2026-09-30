import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/customer/customer.dart';
import '../../domain/records/records.dart';
import '../join/join_controller.dart';

/// The customer's own reads, when the signed-in API offers them. Null in a
/// test that did not provide one - every screen below degrades to saying less,
/// never to guessing.
final customerApiProvider = Provider<CustomerApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is CustomerApi ? api as CustomerApi : null;
});

final myProfileProvider = FutureProvider<CustomerProfile?>((ref) async {
  final api = ref.watch(customerApiProvider);
  return api?.me();
});

final nextDueProvider = FutureProvider<NextDue?>((ref) async {
  final api = ref.watch(customerApiProvider);
  return api?.nextDue();
});

final upcomingProvider = FutureProvider<List<UpcomingBooking>>((ref) async {
  final api = ref.watch(customerApiProvider);
  return await api?.upcoming() ?? const [];
});

final bookingDetailProvider =
    FutureProvider.family<UpcomingBooking?, String>((ref, id) async {
  final api = ref.watch(customerApiProvider);
  return api?.booking(id);
});

final historyProvider = FutureProvider<List<PastVisit>>((ref) async {
  final api = ref.watch(customerApiProvider);
  return await api?.history() ?? const [];
});

/// The booking catalogue, as a customer sees it: active only. Read live - a
/// customer choosing from yesterday's prices is a customer surprised at the
/// counter.
final bookableServicesProvider = FutureProvider<List<Service>>((ref) async {
  final api = ref.watch(crayApiProvider);
  if (api is! SalonReads) return const [];
  final all = await (api as SalonReads).services();
  return all.where((s) => s.active).toList();
});

final bookableAddOnsProvider = FutureProvider<List<AddOn>>((ref) async {
  final api = ref.watch(crayApiProvider);
  if (api is! SalonReads) return const [];
  final all = await (api as SalonReads).addOns();
  return all.where((a) => a.active).toList();
});

final bookableStaffProvider = FutureProvider<List<StaffMember>>((ref) async {
  final api = ref.watch(crayApiProvider);
  if (api is! SalonReads) return const [];
  final all = await (api as SalonReads).staff();
  return all.where((s) => s.active).toList();
});

/// The bookings API, for a customer booking themselves. The server takes the
/// customer from the token, and refuses a p_customer_id naming anyone else, so
/// the app sends none.
final customerBookingsProvider = Provider<SalonBookings?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is SalonBookings ? api as SalonBookings : null;
});
