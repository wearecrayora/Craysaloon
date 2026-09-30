import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/glass.dart';
import '../../core/ui/salon_mark.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show kEnglish, kHindi, kHinglish, localeProvider;
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
          const SizedBox(height: 32),
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
