import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/format/money.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import '../customers/customers_controller.dart';
import '../join/join_controller.dart';
import 'day_controller.dart';

/// O2 - the walk-in booking.
///
/// **No add-on is ever pre-selected** (`RULES.md` 9, `DESIGN.md` 6.3). Every box
/// starts empty and the customer is asked, rather than charged for something a
/// default ticked on their behalf. The times offered come from the same function
/// the database uses to accept the booking, so a slot that appears here is a
/// slot that will be taken (ARCHITECTURE 6.5).
class WalkInScreen extends ConsumerStatefulWidget {
  const WalkInScreen({super.key});

  @override
  ConsumerState<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends ConsumerState<WalkInScreen> {
  CustomerSummary? _customer;
  Service? _service;
  StaffMember? _staff;
  Slot? _slot;

  /// Empty by default, and it stays empty until somebody taps.
  final Set<String> _addOnIds = {};

  List<Slot> _slots = const [];
  bool _loadingSlots = false;
  bool _saving = false;

  Future<void> _loadSlots() async {
    final service = _service;
    final api = ref.read(crayApiProvider);
    if (service == null || api is! SalonBookings) return;
    final bookings = api as SalonBookings;

    setState(() {
      _loadingSlots = true;
      _slot = null;
    });
    try {
      final slots = await bookings.slots(
        serviceId: service.id,
        day: DateTime.now(),
        staffId: _staff?.id,
        addOnIds: _addOnIds.toList(),
      );
      if (mounted) setState(() => _slots = slots);
    } on CrayApiException {
      // Offline: no grid to show. The booking itself can still be queued for a
      // time the owner knows is free, but guessing a slot list would be worse
      // than saying there is none.
      if (mounted) setState(() => _slots = const []);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _book() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repo = ref.read(dayRepositoryProvider);
    final customer = _customer;
    final service = _service;
    final slot = _slot;
    if (repo == null || customer == null || service == null || slot == null) return;

    setState(() => _saving = true);
    await repo.book(
      serviceId: service.id,
      startsAt: slot.startsAt,
      staffId: slot.staffId,
      customerId: customer.id,
      addOnIds: _addOnIds.toList(),
    );
    if (!mounted) return;

    // Queued either way; the message says which happened, because "booked" when
    // it is only queued is the kind of small lie that costs trust at a till.
    final waiting = await ref.read(outboxProvider)?.pending() ?? const [];
    messenger.showSnackBar(SnackBar(
      content: Text(waiting.isEmpty ? l10n.walkInBooked : l10n.walkInQueuedOffline),
    ));
    ref.read(dayControllerProvider.notifier).refresh();
    router.go('/day');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final services = ref.watch(servicesProvider).value?.value ?? const <Service>[];
    final addOns = ref.watch(addOnsProvider).value?.value ?? const <AddOn>[];
    final staff = ref.watch(staffProvider).value?.value ?? const <StaffMember>[];
    final customers = ref.watch(customersControllerProvider).customers;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.walkInTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.walkInCustomer, style: Theme.of(context).textTheme.labelMedium),
            DropdownButtonFormField<CustomerSummary>(
              initialValue: _customer,
              items: [
                for (final c in customers)
                  DropdownMenuItem(
                    value: c,
                    child: Text(c.name?.trim().isNotEmpty == true ? c.name! : (c.phone ?? '')),
                  ),
              ],
              onChanged: (c) => setState(() => _customer = c),
            ),
            const SizedBox(height: 16),

            Text(l10n.walkInService, style: Theme.of(context).textTheme.labelMedium),
            DropdownButtonFormField<Service>(
              initialValue: _service,
              items: [
                for (final s in services.where((s) => s.active))
                  DropdownMenuItem(
                    value: s,
                    child: Text('${s.name} · ${rupees(s.pricePaise)}'),
                  ),
              ],
              onChanged: (s) {
                setState(() {
                  _service = s;
                  // A service change invalidates the add-ons chosen for the old
                  // one; re-ticking is better than silently charging for
                  // something that belongs to a different service.
                  _addOnIds.clear();
                });
                _loadSlots();
              },
            ),
            const SizedBox(height: 16),

            if (addOns.isNotEmpty) ...[
              Text(l10n.walkInAddOns, style: Theme.of(context).textTheme.labelMedium),
              for (final a in addOns.where((a) => a.active))
                CheckboxListTile(
                  // UNTICKED. Always (RULES 9).
                  value: _addOnIds.contains(a.id),
                  onChanged: (on) {
                    setState(() {
                      if (on ?? false) {
                        _addOnIds.add(a.id);
                      } else {
                        _addOnIds.remove(a.id);
                      }
                    });
                    _loadSlots();
                  },
                  title: Text('${a.name} · ${rupees(a.pricePaise)}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const SizedBox(height: 16),
            ],

            Text(l10n.walkInStaff, style: Theme.of(context).textTheme.labelMedium),
            DropdownButtonFormField<StaffMember?>(
              initialValue: _staff,
              items: [
                DropdownMenuItem<StaffMember?>(value: null, child: Text(l10n.walkInAnyStaff)),
                for (final s in staff.where((s) => s.active))
                  DropdownMenuItem<StaffMember?>(value: s, child: Text(s.name)),
              ],
              onChanged: (s) {
                setState(() => _staff = s);
                _loadSlots();
              },
            ),
            const SizedBox(height: 16),

            Text(l10n.walkInTime, style: Theme.of(context).textTheme.labelMedium),
            if (_loadingSlots)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_service == null)
              const SizedBox.shrink()
            else if (_slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.walkInNoSlots),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final slot in _slots.take(24))
                    ChoiceChip(
                      selected: _slot?.startsAt == slot.startsAt,
                      onSelected: (_) => setState(() => _slot = slot),
                      label: Text(DateFormat.jm().format(slot.startsAt)),
                    ),
                ],
              ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _saving || _customer == null || _service == null || _slot == null
                  ? null
                  : _book,
              child: Text(l10n.walkInBook),
            ),
          ],
        ),
      ),
    );
  }
}
