import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ui/load_failed.dart';
import '../../app/providers.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/join/cray_api.dart';
import '../../domain/records/records.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

/// Stylist hours and holidays (0098). What these screens edit is what
/// available_slots reads: a stylist's week decides when they can be booked, and
/// time off - theirs, or the whole salon's - takes times away.

final salonHoursApiProvider = Provider<SalonHoursApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is SalonHoursApi ? api as SalonHoursApi : null;
});

final shiftsProvider = FutureProvider<List<Shift>>((ref) async {
  final api = ref.watch(salonHoursApiProvider);
  return await api?.shifts() ?? const [];
});

final timeOffProvider = FutureProvider<List<TimeOff>>((ref) async {
  final api = ref.watch(salonHoursApiProvider);
  return await api?.timeOff() ?? const [];
});

/// The week as an Indian salon reads it: Monday first. Values are Postgres
/// day numbers (0 = Sunday).
const weekOrder = [1, 2, 3, 4, 5, 6, 0];

/// "Monday" in the reader's language - Hinglish reads Latin script.
String dayName(BuildContext context, int day) {
  final locale = Localizations.localeOf(context);
  final tag = locale.scriptCode == 'Latn' ? 'en' : locale.languageCode;
  // 11 Oct 2026 is a Sunday: day 0.
  return DateFormat.EEEE(tag).format(DateTime(2026, 10, 11 + day));
}

TimeOfDay _parse(String hm) {
  final p = hm.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

String _hm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _show(BuildContext context, String hm) =>
    MaterialLocalizations.of(context).formatTimeOfDay(_parse(hm));

// ---------------------------------------------------------------------------
// O11 - Hours: when the salon can actually be booked, and its holidays
// ---------------------------------------------------------------------------

class HoursScreen extends ConsumerWidget {
  const HoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final canEdit = ref.watch(canEditCatalogueProvider);
    final shifts = ref.watch(shiftsProvider);
    final timeOff = ref.watch(timeOffProvider);
    final staff =
        ref.watch(staffProvider).value?.value ?? const <StaffMember>[];
    String staffName(String? id) =>
        staff.where((s) => s.id == id).firstOrNull?.name ??
        l10n.hoursSalonClosed;
    final ml = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shiftsProvider);
          ref.invalidate(timeOffProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(l10n.hoursTitle, style: text.headlineMedium),
            const SizedBox(height: 12),
            Text(l10n.hoursBookable, style: text.titleLarge),
            const SizedBox(height: 4),
            switch (shifts) {
              AsyncData(:final value) when value.isEmpty => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.hoursNoneSet, style: text.bodyLarge),
                      if (canEdit) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => context.push('/staff'),
                          child: Text(l10n.hoursSetUnderTeam),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final day in weekOrder)
                    _Line(
                      dayName(context, day),
                      _span(
                            context,
                            value.where((s) => s.day == day).toList(),
                          ) ??
                          l10n.hoursClosed,
                    ),
                ],
              ),
              // Shown at once, even while a background retry runs.
              AsyncValue(hasError: true) => LoadFailed(
                inline: true,
                onRetry: () => ref.invalidate(shiftsProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            const SizedBox(height: 24),
            Text(l10n.hoursHolidays, style: text.titleLarge),
            const SizedBox(height: 4),
            switch (timeOff) {
              AsyncData(:final value) when value.isEmpty => Text(
                l10n.hoursNoHolidays,
                style: text.bodyMedium,
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final t in value)
                    Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.wholeSalon
                                      ? l10n.hoursSalonClosed
                                      : staffName(t.staffId),
                                  style: text.titleMedium,
                                ),
                                Text(
                                  [
                                    _range(ml, t),
                                    if ((t.reason ?? '').isNotEmpty) t.reason!,
                                  ].join(' · '),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (canEdit)
                            TextButton(
                              onPressed: () => _remove(context, ref, t),
                              child: Text(l10n.hoursRemove),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              _ => const SizedBox.shrink(),
            },
            if (canEdit) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _addHoliday(context, ref),
                icon: const Icon(Icons.event_busy_outlined),
                label: Text(l10n.hoursAddHoliday),
              ),
            ],
            const SizedBox(height: 20),
            Text(l10n.hoursFooter, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }

  /// Earliest start to latest end that day, across every stylist.
  static String? _span(BuildContext context, List<Shift> day) {
    if (day.isEmpty) return null;
    final start = day
        .map((s) => s.starts)
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final end = day
        .map((s) => s.ends)
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    return '${_show(context, start)} – ${_show(context, end)}';
  }

  static String _range(MaterialLocalizations ml, TimeOff t) {
    final last = t.endsAt.subtract(const Duration(minutes: 1));
    return DateUtils.isSameDay(t.startsAt, last)
        ? ml.formatMediumDate(t.startsAt)
        : '${ml.formatShortMonthDay(t.startsAt)} – ${ml.formatShortMonthDay(last)}';
  }

  Future<void> _addHoliday(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (range == null || !context.mounted) return;

    final reason = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.hoursAddHoliday,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _range(
                MaterialLocalizations.of(context),
                TimeOff(
                  id: '',
                  startsAt: range.start,
                  endsAt: range.end.add(const Duration(days: 1)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: l10n.hoursHolidayReason),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.hoursHolidayAdd),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final api = ref.read(salonHoursApiProvider);
    if (api == null) return;
    try {
      // Whole days, in the phone's (the salon's) time: midnight to midnight.
      await api.addTimeOff(
        startsAt: DateUtils.dateOnly(range.start),
        endsAt: DateUtils.dateOnly(range.end).add(const Duration(days: 1)),
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      ref.invalidate(timeOffProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.hoursHolidayAdded)));
    } on CrayApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.hoursSaveFailed)));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, TimeOff t) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(salonHoursApiProvider);
    if (api == null) return;
    try {
      await api.removeTimeOff(t.id);
      ref.invalidate(timeOffProvider);
    } on CrayApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.hoursSaveFailed)));
    }
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      // Both sides may wrap: at 200% text the hours outgrew the row.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A stylist's week
// ---------------------------------------------------------------------------

class StaffHoursScreen extends ConsumerStatefulWidget {
  const StaffHoursScreen({required this.staffId, super.key});

  final String staffId;

  @override
  ConsumerState<StaffHoursScreen> createState() => _StaffHoursScreenState();
}

class _DayDraft {
  _DayDraft({required this.working, required this.starts, required this.ends});

  bool working;
  String starts;
  String ends;
}

class _StaffHoursScreenState extends ConsumerState<StaffHoursScreen> {
  Map<int, _DayDraft>? _week;
  bool _saving = false;

  /// One shift a day here: earliest start to latest end of whatever was saved.
  /// New days start at 10:00-20:00, a common salon day, for the owner to change.
  Map<int, _DayDraft> _from(List<Shift> shifts) => {
    for (final d in weekOrder)
      d: () {
        final day = shifts
            .where((s) => s.staffId == widget.staffId && s.day == d)
            .toList();
        if (day.isEmpty) {
          return _DayDraft(working: false, starts: '10:00', ends: '20:00');
        }
        final start = day
            .map((s) => s.starts)
            .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
        final end = day
            .map((s) => s.ends)
            .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
        return _DayDraft(working: true, starts: start, ends: end);
      }(),
  };

  Future<void> _pick(_DayDraft day, bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(start ? day.starts : day.ends),
    );
    if (picked == null) return;
    setState(() => start ? day.starts = _hm(picked) : day.ends = _hm(picked));
  }

  Future<void> _save(String name) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final week = _week!;
    for (final d in weekOrder) {
      final day = week[d]!;
      if (day.working && day.ends.compareTo(day.starts) <= 0) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.staffHoursInvalid(dayName(context, d)))),
        );
        return;
      }
    }
    final api = ref.read(salonHoursApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      await api.setStaffWeek(widget.staffId, [
        for (final d in weekOrder)
          if (week[d]!.working)
            Shift(
              staffId: widget.staffId,
              day: d,
              starts: week[d]!.starts,
              ends: week[d]!.ends,
            ),
      ]);
      ref.invalidate(shiftsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.staffHoursSaved(name))),
      );
      if (mounted) context.pop();
    } on CrayApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.hoursSaveFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final shifts = ref.watch(shiftsProvider);
    final staff =
        ref.watch(staffProvider).value?.value ?? const <StaffMember>[];
    final name =
        staff.where((s) => s.id == widget.staffId).firstOrNull?.name ?? '';
    if (shifts.hasValue) _week ??= _from(shifts.value!);
    final week = _week;

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      // An error is an answer, not a wait: without this the stylist's week
      // spun forever when the hours could not be read.
      body: week == null
          ? (shifts.hasError
              ? LoadFailed(onRetry: () => ref.invalidate(shiftsProvider))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text(l10n.staffHoursFor(name), style: text.headlineMedium),
                const SizedBox(height: 4),
                Text(l10n.staffHoursNote, style: text.bodyMedium),
                const SizedBox(height: 12),
                for (final d in weekOrder)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    // The day and its switch on one line, the hours under
                    // it: side by side, "10:00 AM - 5:00 PM" did not fit
                    // beside a day name and a switch on a 360dp phone.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dayName(context, d),
                                style: text.titleMedium,
                              ),
                            ),
                            if (!week[d]!.working)
                              Text(
                                l10n.staffHoursDayOff,
                                style: text.bodyMedium,
                              ),
                            const SizedBox(width: 8),
                            Switch(
                              value: week[d]!.working,
                              onChanged: (v) =>
                                  setState(() => week[d]!.working = v),
                            ),
                          ],
                        ),
                        if (week[d]!.working)
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _TimeButton(
                                label: _show(context, week[d]!.starts),
                                onTap: () => _pick(week[d]!, true),
                              ),
                              const Text('–'),
                              _TimeButton(
                                label: _show(context, week[d]!.ends),
                                onTap: () => _pick(week[d]!, false),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : () => _save(name),
                  child: Text(l10n.staffHoursSave),
                ),
              ],
            ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onTap, child: Text(label));
}
