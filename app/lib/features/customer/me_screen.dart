import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/sign_out.dart' show SignOutButton;
import '../../core/ui/action_tile.dart';
import '../../core/ui/fine_print.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/menu.dart';
import '../../core/ui/salon_mark.dart';
import '../../domain/customer/customer.dart';
import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show kEnglish, kHindi, kHinglish, localeCode, localeProvider;
import '../join/join_controller.dart' show resolvedBrandingProvider;
import '../salon/salon_account.dart' show hasFeature;
import 'customer_providers.dart';

/// C12 - Me: the customer's profile, and every menu they have, in plain sight
/// (redesigned 21 Oct 2026).
///
/// Who the app thinks you are, with Edit right there; your things as tiles;
/// then labelled menus - your details, privacy, the fine print - and Sign out
/// at the foot. "App by Crayora" is the only place the customer app names its
/// maker.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(myProfileProvider).value;
    final salonName = ref.watch(resolvedBrandingProvider)?.displayName ?? l10n.appTitle;
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: const SalonTitle()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _ProfileCard(profile: profile),
          const SizedBox(height: 24),
          ActionGrid(
            tiles: [
              ActionTile(
                icon: Icons.history_rounded,
                label: l10n.meTileVisits,
                onTap: () => context.push('/visits'),
              ),
              ActionTile(
                icon: Icons.receipt_long_outlined,
                label: l10n.meTileBills,
                onTap: () => context.push('/documents'),
              ),
              ActionTile(
                icon: Icons.account_balance_wallet_outlined,
                label: l10n.walletTitle,
                onTap: () => context.go('/wallet'),
              ),
              if (hasFeature(ref, 'referrals'))
                ActionTile(
                  icon: Icons.card_giftcard_outlined,
                  label: l10n.referTitle,
                  onTap: () => context.push('/refer'),
                )
              else
                ActionTile(
                  icon: Icons.shield_outlined,
                  label: l10n.yourDataTitle,
                  onTap: () => context.push('/your-data'),
                ),
            ],
          ),
          MenuSection(
            title: l10n.meSectionDetails,
            children: [
              MenuRow(
                icon: Icons.person_outline,
                title: l10n.meEditProfile,
                subtitle: l10n.meEditProfileSub,
                onTap: () => context.push('/me/edit'),
              ),
              MenuRow(
                icon: Icons.translate,
                title: l10n.meLanguage,
                subtitle: languageName(l10n, locale),
                onTap: () => pickLanguage(context, ref),
              ),
              // Optional, and never for a child (0113): day and month only.
              if (profile != null && !profile.isMinor)
                MenuRow(
                  icon: Icons.cake_outlined,
                  title: l10n.meBirthday,
                  subtitle: profile.birthdayMonth == null
                      ? l10n.meBirthdayAdd(salonName)
                      : dayMonthLabel(context, profile.birthdayMonth!, profile.birthdayDay!),
                  onTap: () => editBirthday(context, ref, profile, salonName),
                ),
            ],
          ),
          MenuSection(
            title: l10n.meSectionActivity,
            children: [
              MenuRow(
                icon: Icons.history,
                title: l10n.historyTitle,
                subtitle: l10n.meHistorySub,
                onTap: () => context.push('/visits'),
              ),
              MenuRow(
                icon: Icons.receipt_long_outlined,
                title: l10n.docsTitle,
                subtitle: l10n.docsSub,
                onTap: () => context.push('/documents'),
              ),
            ],
          ),
          MenuSection(
            title: l10n.meSectionPrivacy,
            children: [
              MenuRow(
                icon: Icons.shield_outlined,
                title: l10n.yourDataTitle,
                subtitle: l10n.meYourDataSub,
                onTap: () => context.push('/your-data'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const FinePrint(),
          const SizedBox(height: 24),
          const SignOutButton(),
          const SizedBox(height: 16),
          Text(l10n.meAppBy, style: text.bodySmall),
        ],
      ),
    );
  }
}

String languageName(AppL10n l10n, Locale locale) => locale == kHindi
    ? l10n.languageHindi
    : locale == kHinglish
    ? l10n.languageHinglish
    : l10n.languageEnglish;

/// The language sheet: the choice applies at once, on the phone, and is saved
/// to the profile so the salon's messages follow it (0118).
Future<void> pickLanguage(BuildContext context, WidgetRef ref) async {
  final l10n = AppL10n.of(context);
  final current = ref.read(localeProvider);
  final choice = await showModalBottomSheet<Locale>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.meLanguage, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final (locale, name) in [
            (kEnglish, l10n.languageEnglish),
            (kHindi, l10n.languageHindi),
            (kHinglish, l10n.languageHinglish),
          ])
            ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(name),
              trailing: locale == current ? const Icon(Icons.check_circle) : null,
              onTap: () => Navigator.of(context).pop(locale),
            ),
        ],
      ),
    ),
  );
  if (choice == null || choice == current) return;
  ref.read(localeProvider.notifier).select(choice);
  final api = ref.read(customerApiProvider);
  if (api == null) return;
  try {
    await api.updateMyProfile(language: localeCode(choice));
    ref.invalidate(myProfileProvider);
  } on CrayApiException {
    // The app is already in the new language; the next save carries it.
  }
}

/// Who you are, at the top: your initials in a soft circle, your name, your
/// number (partly hidden), and Edit.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final CustomerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final name = profile?.name?.trim();
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Initials(profile?.initials, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name == null || name.isEmpty ? l10n.meNoName : name,
                      style: text.titleLarge,
                    ),
                    if (profile?.maskedPhone case final phone?) ...[
                      const SizedBox(height: 4),
                      Text(phone, style: text.bodyMedium),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/me/edit'),
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.meEditProfile),
          ),
        ],
      ),
    );
  }
}

/// "16 March" in the reader's language - no year, because none is kept.
String dayMonthLabel(BuildContext context, int month, int day) {
  final locale = Localizations.localeOf(context);
  final tag = locale.scriptCode == 'Latn' ? 'en' : locale.toLanguageTag();
  try {
    return DateFormat.MMMMd(tag).format(DateTime(2000, month, day));
  } catch (_) {
    return DateFormat.MMMMd().format(DateTime(2000, month, day));
  }
}

Future<void> editBirthday(
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
