import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/money.dart';
import '../../core/theme/cray_glass.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/load_failed.dart';
import '../../core/ui/service_icon.dart';
import '../../core/ui/skeleton.dart';
import '../../domain/records/records.dart' show Service;
import '../../l10n/app_localizations.dart';
import '../customer/customer_providers.dart';

/// Search the salon's menu (21 Oct 2026): type "hair", "facial", "बाल", see
/// what they do and what it costs, and book it in one tap.
///
/// It searches the salon's own active services - names and categories - on
/// the phone, as you type. Nothing is booked from here: a tap opens booking
/// with that service chosen, and the customer goes on from there.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static List<Service> _match(List<Service> all, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final words = q.split(RegExp(r'\s+'));
    return all.where((s) {
      final hay = '${s.name} ${s.category ?? ''}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final services = ref.watch(bookableServicesProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_query.clear),
                    ),
            ),
          ),
        ),
      ),
      body: switch (services) {
        AsyncValue(:final value?, hasValue: true) => () {
          final found = _match(value, _query.text);
          if (value.isEmpty) {
            return _Empty(text: l10n.bookNoServices);
          }
          if (found.isEmpty) {
            return _Empty(text: l10n.searchNothing(_query.text.trim()));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: found.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => i == 0
                ? Text(
                    _query.text.trim().isEmpty
                        ? l10n.searchAll(value.length)
                        : l10n.searchFound(found.length),
                    style: text.labelMedium,
                  )
                : _ServiceRow(service: found[i - 1]),
          );
        }(),
        AsyncValue(hasError: true) => LoadFailed(
          onRetry: () => ref.invalidate(bookableServicesProvider),
        ),
        _ => const SkeletonList(rows: 5, padding: EdgeInsets.all(16)),
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Icon(Icons.search_off_rounded, size: 48, color: style.bodySmall?.color),
        const SizedBox(height: 16),
        Text(text, style: style.bodyLarge),
      ],
    );
  }
}

/// One service: its picture, name, time and price, and Book.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final g = CrayGlass.of(context);
    void book() => context.go('/book?service=${service.id}');
    return Pressable(
      onTap: book,
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(g.radius),
              ),
              child: Icon(
                serviceIcon(service.name, category: service.category),
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: text.titleMedium),
                  Text(
                    [
                      if ((service.category ?? '').trim().isNotEmpty) service.category!.trim(),
                      l10n.bookMinutes(service.durationMinutes),
                    ].join(' · '),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  rupees(service.pricePaise),
                  style: text.titleMedium?.copyWith(fontFeatures: moneyFeatures),
                ),
                Text(l10n.navBook, style: text.labelMedium?.copyWith(color: g.ink)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
