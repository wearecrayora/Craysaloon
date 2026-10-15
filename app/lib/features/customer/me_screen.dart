import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ui/fine_print.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/customer/customer.dart';
import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show kEnglish, kHindi, kHinglish, localeProvider;
import '../join/join_controller.dart' show resolvedBrandingProvider;
import 'customer_providers.dart';

/// C12 - Me: who the app thinks you are, your language, your visits, your data.
///
/// Read-only by design: the name and number are the salon's record of the
/// customer, and there is no path here to change the phone a binding hangs on
/// (RULES 4). "App by Crayora" at the foot is the only place the customer app
/// names its maker.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(myProfileProvider).value;
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? l10n.appTitle;
    final locale = ref.watch(localeProvider);

    final languageName = locale == kHindi
        ? l10n.languageHindi
        : locale == kHinglish
        ? l10n.languageHinglish
        : l10n.languageEnglish;

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(l10n.meTitle, style: text.headlineMedium),
          const SizedBox(height: 12),
          if (profile?.name case final name? when name.trim().isNotEmpty)
            _Field(label: l10n.meName, value: name),
          if (profile?.maskedPhone case final phone?)
            _Field(label: l10n.mePhone, value: phone),
          const SizedBox(height: 12),
          _Row(
            icon: Icons.translate,
            title: l10n.meLanguage,
            subtitle: languageName,
            onTap: () => _pickLanguage(context, ref),
          ),
          // Optional, and never for a child (0113): day and month only.
          if (profile != null && !profile.isMinor)
            _Row(
              icon: Icons.cake_outlined,
              title: l10n.meBirthday,
              subtitle: profile.birthdayMonth == null
                  ? l10n.meBirthdayAdd(salonName)
                  : _dayMonth(context, profile.birthdayMonth!, profile.birthdayDay!),
              onTap: () => _editBirthday(context, ref, profile, salonName),
            ),
          _Row(
            icon: Icons.history,
            title: l10n.historyTitle,
            subtitle: l10n.meHistorySub,
            onTap: () => context.push('/visits'),
          ),
          _Row(
            icon: Icons.receipt_long_outlined,
            title: l10n.docsTitle,
            subtitle: l10n.docsSub,
            onTap: () => context.push('/documents'),
          ),
          _Row(
            icon: Icons.shield_outlined,
            title: l10n.yourDataTitle,
            subtitle: l10n.meYourDataSub,
            onTap: () => context.push('/your-data'),
          ),
          const SizedBox(height: 24),
          const FinePrint(),
          const SizedBox(height: 24),
          Text(l10n.meAppBy, style: text.bodySmall),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final current = ref.read(localeProvider);
    final choice = await showModalBottomSheet<Locale>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (locale, name) in [
              (kEnglish, l10n.languageEnglish),
              (kHindi, l10n.languageHindi),
              (kHinglish, l10n.languageHinglish),
            ])
              ListTile(
                minTileHeight: 56,
                title: Text(name),
                trailing: locale == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(locale),
              ),
          ],
        ),
      ),
    );
    if (choice != null) ref.read(localeProvider.notifier).select(choice);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall),
          Text(value, style: text.titleMedium),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}


/// "16 March" in the reader's language - no year, because none is kept.
String _dayMonth(BuildContext context, int month, int day) {
  final locale = Localizations.localeOf(context);
  final tag = locale.scriptCode == 'Latn' ? 'en' : locale.toLanguageTag();
  try {
    return DateFormat.MMMMd(tag).format(DateTime(2000, month, day));
  } catch (_) {
    return DateFormat.MMMMd().format(DateTime(2000, month, day));
  }
}

Future<void> _editBirthday(
  BuildContext context,
  WidgetRef ref,
  CustomerProfile profile,
  String salonName,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BirthdaySheet(profile: profile, salonName: salonName),
  );
  if (saved == true) {
    ref.invalidate(myProfileProvider);
    ref.invalidate(myBirthdayOfferProvider);
  }
}

class _BirthdaySheet extends ConsumerStatefulWidget {
  const _BirthdaySheet({required this.profile, required this.salonName});

  final CustomerProfile profile;
  final String salonName;

  @override
  ConsumerState<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends ConsumerState<_BirthdaySheet> {
  late int? _month = widget.profile.birthdayMonth;
  late int? _day = widget.profile.birthdayDay;
  bool _busy = false;
  bool _failed = false;

  // 2000 is a leap year, so 29 February is a birthday that can be kept.
  int get _daysIn => _month == null ? 31 : DateUtils.getDaysInMonth(2000, _month!);

  Future<void> _save(int? month, int? day) async {
    final api = ref.read(customerApiProvider);
    if (api == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await api.setMyBirthday(month, day);
      if (mounted) Navigator.of(context).pop(true);
    } on CrayApiException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final locale = Localizations.localeOf(context);
    final tag = locale.scriptCode == 'Latn' ? 'en' : locale.toLanguageTag();
    String monthName(int m) {
      try {
        return DateFormat.MMMM(tag).format(DateTime(2000, m));
      } catch (_) {
        return DateFormat.MMMM().format(DateTime(2000, m));
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.meBirthday, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.meBirthdayExplain(widget.salonName), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.meBirthdayMonth),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(monthName(m))),
                    ],
                    onChanged: (m) => setState(() {
                      _month = m;
                      if (_day != null && _day! > _daysIn) _day = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_month),
                    initialValue: _day,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.meBirthdayDay),
                    items: [
                      for (var d = 1; d <= _daysIn; d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (d) => setState(() => _day = d),
                  ),
                ),
              ],
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(l10n.consentSaveFailed, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy || _month == null || _day == null ? null : () => _save(_month, _day),
              child: Text(_busy ? '…' : l10n.meBirthdaySave),
            ),
            if (widget.profile.birthdayMonth != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _save(null, null),
                child: Text(l10n.meBirthdayRemove),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
