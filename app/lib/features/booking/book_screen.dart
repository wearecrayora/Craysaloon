import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../data/local/outbox.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';

/// C5-C8 - a customer books themselves, in four steps: service, add-ons,
/// stylist and time, review (Claude Design, 30 Sep 2026).
///
/// The rules that shape it:
///
/// * **Nothing is chosen for them.** No service is selected on open, and no
///   add-on is ever pre-ticked (RULES: add-ons never pre-selected).
/// * **Only free times are offered**, from `available_slots` - with the add-ons
///   in, because they change the length. The server still decides: a time taken
///   between showing it and confirming comes back as "slot taken", and the
///   customer is sent back to pick again, never booked on top of someone.
/// * **One booking per confirm**, however many times it is pressed or retried:
///   the action id is made once per review and reused (RULES 9.3).
/// * **Nothing is paid here.** Payment follows the visit, so the review says
///   so rather than implying a charge.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key});

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

enum _Step { service, addOns, time, review }

class _BookScreenState extends ConsumerState<BookScreen> {
  _Step _step = _Step.service;
  Service? _service;
  final Set<String> _addOnIds = {};
  String? _staffId; // null = anyone
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  Slot? _slot;
  String? _actionId;
  bool _busy = false;
  String? _problem;

  List<AddOn> get _addOns => ref.read(bookableAddOnsProvider).value ?? const [];
  List<AddOn> get _chosenAddOns => _addOns.where((a) => _addOnIds.contains(a.id)).toList();
  bool get _hasAddOnStep => (ref.watch(bookableAddOnsProvider).value ?? const []).isNotEmpty;

  int get _totalPaise =>
      (_service?.pricePaise ?? 0) + _chosenAddOns.fold(0, (sum, a) => sum + a.pricePaise);
  int get _minutes =>
      (_service?.durationMinutes ?? 0) +
      _chosenAddOns.fold(0, (sum, a) => sum + a.extraDurationMinutes);

  List<_Step> get _steps => [
        _Step.service,
        if (_hasAddOnStep) _Step.addOns,
        _Step.time,
        _Step.review,
      ];

  void _go(_Step step) => setState(() {
        _step = step;
        _problem = null;
        // Anything that changes the time invalidates the chosen time, and a
        // new review gets a new action id.
        if (step != _Step.review) _actionId = null;
      });

  void _next() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i < steps.length - 1) _go(steps[i + 1]);
  }

  bool _back() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i <= 0) return false;
    _go(steps[i - 1]);
    return true;
  }

  bool get _canContinue => switch (_step) {
        _Step.service => _service != null,
        _Step.addOns => true,
        _Step.time => _slot != null,
        _Step.review => !_busy,
      };

  Future<void> _confirm() async {
    final api = ref.read(customerBookingsProvider);
    final service = _service;
    final slot = _slot;
    if (api == null || service == null || slot == null) return;
    final l10n = AppL10n.of(context);
    final ml = MaterialLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    _actionId ??= Outbox.newActionId();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final id = await api.createBooking(
        clientActionId: _actionId!,
        serviceId: service.id,
        startsAt: slot.startsAt,
        staffId: slot.staffId,
        addOnIds: _addOnIds.toList(),
      );
      ref.invalidate(upcomingProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.bookDone(ml.formatShortMonthDay(slot.startsAt)))),
      );
      _reset();
      context.push('/booking/$id');
    } on CrayApiException catch (e) {
      if (!mounted) return;
      if (e.kind == CrayErrorKind.slotTaken) {
        // Someone else got the chair. Back to the times, freshly read.
        setState(() {
          _busy = false;
          _slot = null;
          _step = _Step.time;
          _actionId = null;
          _problem = l10n.bookSlotTaken;
        });
      } else {
        // Same action id kept: a retry cannot book twice.
        setState(() {
          _busy = false;
          _problem = l10n.bookFailed;
        });
      }
    }
  }

  void _reset() => setState(() {
        _step = _Step.service;
        _service = null;
        _addOnIds.clear();
        _staffId = null;
        _slot = null;
        _actionId = null;
        _busy = false;
        _problem = null;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final steps = _steps;
    final index = steps.indexOf(_step);

    return PopScope(
      canPop: index <= 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: index > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _back,
                )
              : null,
          title: const SalonTitle(),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(l10n.bookStep(index + 1, steps.length), style: text.bodySmall),
                  const SizedBox(height: 2),
                  // The step heading changes with a short cross-fade; with
                  // reduced motion it simply changes.
                  AnimatedSwitcher(
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Text(
                      switch (_step) {
                        _Step.service => l10n.bookChooseService,
                        _Step.addOns => l10n.bookAddOnsTitle,
                        _Step.time => l10n.bookStylistTime,
                        _Step.review => l10n.bookReview,
                      },
                      key: ValueKey(_step),
                      style: text.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_problem != null) ...[
                    _Problem(_problem!),
                    const SizedBox(height: 12),
                  ],
                  switch (_step) {
                    _Step.service => _ServiceStep(
                        selected: _service?.id,
                        onSelect: (s) => setState(() {
                          _service = s;
                          _slot = null;
                        }),
                      ),
                    _Step.addOns => _AddOnStep(
                        chosen: _addOnIds,
                        onToggle: (id, on) => setState(() {
                          on ? _addOnIds.add(id) : _addOnIds.remove(id);
                          _slot = null;
                        }),
                      ),
                    _Step.time => _TimeStep(
                        serviceId: _service!.id,
                        addOnIds: _addOnIds.toList()..sort(),
                        staffId: _staffId,
                        day: _day,
                        slot: _slot,
                        onStaff: (id) => setState(() {
                          _staffId = id;
                          _slot = null;
                        }),
                        onDay: (d) => setState(() {
                          _day = d;
                          _slot = null;
                        }),
                        onSlot: (s) => setState(() => _slot = s),
                      ),
                    _Step.review => _Review(
                        service: _service!,
                        addOns: _chosenAddOns,
                        slot: _slot!,
                        minutes: _minutes,
                        totalPaise: _totalPaise,
                      ),
                  },
                ],
              ),
            ),
            _BottomBar(
              totalPaise: _service == null || _step == _Step.review ? null : _totalPaise,
              minutes: _minutes,
              label: _step == _Step.review ? l10n.bookConfirm : l10n.bookContinue,
              busy: _busy,
              onPressed: _canContinue ? (_step == _Step.review ? _confirm : _next) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Appear(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// C5 - service
// ---------------------------------------------------------------------------

class _ServiceStep extends ConsumerWidget {
  const _ServiceStep({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<Service> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final services = ref.watch(bookableServicesProvider);

    return switch (services) {
      AsyncData(:final value) when value.isEmpty =>
        Text(l10n.bookNoServices, style: text.bodyLarge),
      AsyncData(:final value) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in _grouped(value, l10n.bookOther).entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(group.key, style: text.titleLarge),
              ),
              for (final s in group.value)
                _ChoiceRow(
                  selected: s.id == selected,
                  onTap: () => onSelect(s),
                  leading: _ServiceTile(name: s.name, category: s.category),
                  title: s.name,
                  subtitle: l10n.bookMinutes(s.durationMinutes),
                  trailing: rupees(s.pricePaise),
                  radio: true,
                ),
            ],
          ],
        ),
      AsyncError() => _Retry(onRetry: () => ref.invalidate(bookableServicesProvider)),
      _ => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
    };
  }

  /// Grouped by the salon's own categories, in first-seen order; services with
  /// none go last under "Other" - or ungrouped entirely, if none have one.
  static Map<String, List<Service>> _grouped(List<Service> services, String other) {
    final out = <String, List<Service>>{};
    final hasAny = services.any((s) => (s.category ?? '').trim().isNotEmpty);
    for (final s in services) {
      final key = (s.category ?? '').trim();
      out.putIfAbsent(key.isEmpty ? (hasAny ? other : '') : key, () => []).add(s);
    }
    final loose = out.remove(other);
    if (loose != null) out[other] = loose;
    return out.map((k, v) => MapEntry(k, v));
  }
}

/// A tinted tile with an icon, where the design had a service photo: there are
/// no photos of each salon's own services, and a stock photo of somebody
/// else's haircut would be a promise (DESIGN 10). Container fill, not primary:
/// the brand is never painted on a surface.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.name, this.category});

  final String name;
  final String? category;

  static IconData iconFor(String name, String? category) {
    final s = '${category ?? ''} $name'.toLowerCase();
    if (s.contains('beard') || s.contains('shave')) return Icons.face_retouching_natural;
    if (s.contains('colour') || s.contains('color') || s.contains('dye')) return Icons.palette_outlined;
    if (s.contains('spa') || s.contains('massage')) return Icons.spa_outlined;
    if (s.contains('facial') || s.contains('clean') || s.contains('skin')) return Icons.face_outlined;
    if (s.contains('nail') || s.contains('mani') || s.contains('pedi')) return Icons.back_hand_outlined;
    if (s.contains('wash') || s.contains('blow')) return Icons.water_drop_outlined;
    return Icons.content_cut;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(g.radiusChip + 4),
      ),
      child: Icon(iconFor(name, category), color: scheme.onPrimaryContainer),
    );
  }
}

/// One choosable row: a radio or checkbox, the thing, its price. The whole row
/// is the target (48dp+), and it settles under the thumb.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.trailing,
    required this.radio,
    this.subtitle,
    this.leading,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String trailing;
  final bool radio;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: radio,
      button: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? g.card : Colors.transparent,
            borderRadius: BorderRadius.circular(g.radius),
            border: Border.all(color: selected ? g.ink : g.line, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(
                radio
                    ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked)
                    : (selected ? Icons.check_box : Icons.check_box_outline_blank),
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (subtitle != null) Text(subtitle!, style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message ?? l10n.bookFailed, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// C6 - add-ons
// ---------------------------------------------------------------------------

class _AddOnStep extends ConsumerWidget {
  const _AddOnStep({required this.chosen, required this.onToggle});

  final Set<String> chosen;
  final void Function(String id, bool on) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final addOns = ref.watch(bookableAddOnsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.bookAddOnsHint, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        for (final a in addOns)
          _ChoiceRow(
            selected: chosen.contains(a.id),
            onTap: () => onToggle(a.id, !chosen.contains(a.id)),
            title: a.name,
            subtitle: a.extraDurationMinutes > 0 ? '+${l10n.bookMinutes(a.extraDurationMinutes)}' : null,
            trailing: '+${rupees(a.pricePaise)}',
            radio: false,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// C7 - stylist and time
// ---------------------------------------------------------------------------

typedef _SlotKey = ({String service, String addOns, String? staff, DateTime day});

final _slotsProvider = FutureProvider.family<List<Slot>, _SlotKey>((ref, key) async {
  final api = ref.watch(customerBookingsProvider);
  if (api == null) return const [];
  final slots = await api.slots(
    serviceId: key.service,
    day: key.day,
    staffId: key.staff,
    addOnIds: key.addOns.isEmpty ? const [] : key.addOns.split(','),
  );
  // "Anyone": one button per time, the first free stylist behind it.
  final seen = <DateTime>{};
  final now = DateTime.now();
  return [
    for (final s in [...slots]..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
      if (s.startsAt.isAfter(now) && seen.add(s.startsAt)) s,
  ];
});

class _TimeStep extends ConsumerWidget {
  const _TimeStep({
    required this.serviceId,
    required this.addOnIds,
    required this.staffId,
    required this.day,
    required this.slot,
    required this.onStaff,
    required this.onDay,
    required this.onSlot,
  });

  final String serviceId;
  final List<String> addOnIds;
  final String? staffId;
  final DateTime day;
  final Slot? slot;
  final ValueChanged<String?> onStaff;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<Slot> onSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final staff = ref.watch(bookableStaffProvider).value ?? const [];
    final key = (service: serviceId, addOns: addOnIds.join(','), staff: staffId, day: day);
    final slots = ref.watch(_slotsProvider(key));
    final locale = Localizations.localeOf(context);
    // Hinglish reads Latin script: weekday names in English, not Devanagari.
    final dateLocale = locale.scriptCode == 'Latn' ? 'en' : locale.languageCode;
    final today = DateUtils.dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.bookStylist, style: text.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(label: l10n.bookAnyone, selected: staffId == null, onTap: () => onStaff(null)),
            for (final s in staff)
              _Chip(label: s.name, selected: staffId == s.id, onTap: () => onStaff(s.id)),
          ],
        ),
        const SizedBox(height: 20),
        Text(l10n.bookDate, style: text.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 14,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = today.add(Duration(days: i));
              return _DayChip(
                weekday: DateFormat.E(dateLocale).format(d),
                day: '${d.day}',
                selected: DateUtils.isSameDay(d, day),
                onTap: () => onDay(d),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        Text(ml.formatMediumDate(day), style: text.titleMedium),
        const SizedBox(height: 8),
        switch (slots) {
          AsyncData(:final value) when value.isEmpty =>
            Text(l10n.bookNoTimes, style: text.bodyLarge),
          AsyncData(:final value) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in value)
                  _Chip(
                    label: ml.formatTimeOfDay(TimeOfDay.fromDateTime(s.startsAt)),
                    selected: slot?.startsAt == s.startsAt,
                    onTap: () => onSlot(s),
                    wide: true,
                  ),
              ],
            ),
          AsyncError() => _Retry(
              message: l10n.bookTimesFailed,
              onRetry: () => ref.invalidate(_slotsProvider(key)),
            ),
          _ => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        },
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.wide = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: 48, minWidth: wide ? 100 : 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : g.card,
            borderRadius: BorderRadius.circular(g.radiusChip + 4),
            border: Border.all(color: selected ? scheme.primary : scheme.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 18, color: scheme.onPrimary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: text.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontFeatures: moneyFeatures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.weekday,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final String weekday;
  final String day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);
    final text = Theme.of(context).textTheme;
    final ink = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          width: 56,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : g.card,
            borderRadius: BorderRadius.circular(g.radiusChip + 6),
            border: Border.all(color: selected ? scheme.primary : g.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(weekday, style: text.bodySmall?.copyWith(color: ink)),
              Text(day, style: text.titleMedium?.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// C8 - review
// ---------------------------------------------------------------------------

class _Review extends ConsumerWidget {
  const _Review({
    required this.service,
    required this.addOns,
    required this.slot,
    required this.minutes,
    required this.totalPaise,
  });

  final Service service;
  final List<AddOn> addOns;
  final Slot slot;
  final int minutes;
  final int totalPaise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final ml = MaterialLocalizations.of(context);
    final staff = ref.watch(bookableStaffProvider).value ?? const [];
    final stylist = staff.where((s) => s.id == slot.staffId).firstOrNull?.name ?? l10n.bookAnyone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailRow(label: l10n.bookService, value: service.name),
        DetailRow(
          label: l10n.bookAddOns,
          value: addOns.isEmpty ? l10n.bookNone : addOns.map((a) => a.name).join(', '),
        ),
        DetailRow(label: l10n.bookStylist, value: stylist),
        DetailRow(
          label: l10n.bookDateTime,
          value: '${ml.formatShortMonthDay(slot.startsAt)} · '
              '${ml.formatTimeOfDay(TimeOfDay.fromDateTime(slot.startsAt))}',
        ),
        DetailRow(label: l10n.bookTakesAbout, value: l10n.bookMinutes(minutes)),
        DetailRow(label: l10n.bookTotal, value: rupees(totalPaise), emphasis: true),
        const SizedBox(height: 20),
        Text(l10n.bookPayAfter, style: text.bodyMedium),
        const SizedBox(height: 8),
        Text(l10n.bookChangeHint, style: text.bodySmall),
      ],
    );
  }
}

/// Label left, value right, a hairline under it - the review and the booking
/// detail share it.
class DetailRow extends StatelessWidget {
  const DetailRow({required this.label, required this.value, this.emphasis = false, super.key});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: emphasis ? text.titleMedium : text.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (emphasis ? text.headlineSmall : text.titleMedium)
                  ?.copyWith(fontFeatures: moneyFeatures),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalPaise,
    required this.minutes,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final int? totalPaise;
  final int minutes;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final g = CrayGlass.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: g.bar,
        border: Border(top: BorderSide(color: g.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totalPaise != null) ...[
                Row(
                  children: [
                    Text(l10n.bookTotal, style: text.bodyMedium),
                    const Spacer(),
                    // A total that changes as add-ons are ticked is shown, not
                    // counted up: money never animates (DESIGN 6.1).
                    Text(
                      '${rupees(totalPaise!)} · ${l10n.bookMinutes(minutes)}',
                      style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: busy ? null : onPressed,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
