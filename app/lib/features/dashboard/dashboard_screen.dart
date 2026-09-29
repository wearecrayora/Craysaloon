import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/theme/chart_palette.dart';
import '../../domain/dashboard/dashboard.dart';
import '../../domain/join/cray_api.dart';
import '../../l10n/app_localizations.dart';
import '../join/join_controller.dart';

final dashboardApiProvider = Provider<DashboardApi?>((ref) {
  final api = ref.watch(crayApiProvider);
  return api is DashboardApi ? api as DashboardApi : null;
});

final dashboardProvider = FutureProvider<Dashboard>((ref) async {
  final api = ref.watch(dashboardApiProvider);
  if (api == null) throw const CrayApiException(CrayErrorKind.server);
  return api.dashboard();
});

/// O6 - the owner's dashboard.
///
/// Three rules decide almost every line of it:
///
///   * **A card is a stat tile, not a chart** (DESIGN 6.6). One number's job is
///     to be read, and a chart around it adds nothing.
///   * **Cost is never shown without conversion** (PRD 9.5). What the reminders
///     cost and what they brought in share one card; either alone invites the
///     wrong decision.
///   * **Nothing here can move money.** The outstanding-credit tile says so in
///     words, because an owner looking at a number they cannot change will look
///     for the button that changes it - and it must be absent, not hidden.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dashTitle)),
      body: SafeArea(
        child: switch (dashboard) {
          AsyncData(:final value) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(dashboardProvider),
              child: _Body(value),
            ),
          AsyncError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.joinOffline),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(dashboardProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.d);

  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Drift is SHOWN, not hidden (PRD 9.5). Status colour, with an icon and
        // words - never the colour alone (DESIGN 9.1).
        if (d.driftDays.isNotEmpty) ...[
          _Notice(icon: Icons.warning_amber_rounded, text: l10n.dashDrift),
          const SizedBox(height: 16),
        ],

        Text(l10n.dashToday, style: text.titleMedium),
        const SizedBox(height: 8),
        _TileGrid(tiles: [
          _Tile(label: l10n.dashRevenue, value: rupees(d.revenuePaise)),
          _Tile(label: l10n.dashCompleted, value: '${d.completed}'),
          _Tile(
            label: l10n.dashAvgBill,
            // An average of nothing is not zero.
            value: d.avgBillPaise == null ? l10n.dashNoAverage : rupees(d.avgBillPaise!),
          ),
          _Tile(
            label: l10n.dashBookings,
            value: '${d.bookingsLive}',
            caption: l10n.dashCancelledNoShow(d.cancelled, d.noShow),
          ),
        ]),

        const SizedBox(height: 24),
        Text(l10n.dashThisMonth, style: text.titleMedium),
        const SizedBox(height: 8),
        _TileGrid(tiles: [
          _Tile(
            label: l10n.dashNewRepeat,
            value: '${d.newCustomers} / ${d.repeatCustomers}',
          ),
          _Tile(label: l10n.dashWalletCollected, value: rupees(d.walletCollectedPaise)),
          _Tile(
            label: l10n.dashOutstanding,
            value: rupees(d.outstandingCreditPaise),
            caption: l10n.dashOutstandingNote,
          ),
          _Tile(label: l10n.dashBinds, value: '${d.binds}'),
        ]),

        const SizedBox(height: 24),
        _MessagingCard(d),

        const SizedBox(height: 24),
        _CohortSection(d.cohorts),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// Two columns, two rows at most (DESIGN 6.6): beyond four, the owner is
/// scanning rather than reading.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label above, value below. Never the reverse (DESIGN 6.6).
            Text(label, style: text.labelMedium),
            const SizedBox(height: 4),
            // Tabular figures, and never animated (DESIGN 6.1).
            Text(value, style: text.headlineSmall?.copyWith(fontFeatures: moneyFeatures)),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!, style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: ChartPalette.warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

/// Spend and conversion in ONE card, so neither can be read without the other
/// (PRD 9.5).
class _MessagingCard extends StatelessWidget {
  const _MessagingCard(this.d);

  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dashMessagingTitle, style: text.titleSmall),
            const SizedBox(height: 12),
            Text(l10n.dashSpend, style: text.labelMedium),
            Text(rupees(d.totalSpendPaise),
                style: text.headlineSmall?.copyWith(fontFeatures: moneyFeatures)),
            const SizedBox(height: 8),
            Text(l10n.dashRemindersSent(d.remindersSent), style: text.bodyMedium),
            Text(l10n.dashReminderBookings(d.reminderBookings), style: text.bodyMedium),
            const SizedBox(height: 4),
            // Every acked push is money the owner did not spend (ARCH 12.4).
            Text(l10n.dashPushSaved(d.ackedPushes), style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The cohort chart (DESIGN 9.4)
// ---------------------------------------------------------------------------

class _CohortSection extends StatefulWidget {
  const _CohortSection(this.cohorts);

  final List<CohortRow> cohorts;

  @override
  State<_CohortSection> createState() => _CohortSectionState();
}

class _CohortSectionState extends State<_CohortSection> {
  DateTime? _month;

  List<DateTime> get _months {
    final seen = <DateTime>{};
    return [for (final c in widget.cohorts) if (seen.add(c.month)) c.month];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final months = _months;

    if (months.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dashCohortTitle, style: text.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.dashCohortEmpty, style: text.bodyMedium),
        ],
      );
    }

    // The most recent cohort with ANY known rate, by default: the newest cohort
    // is usually unripe and would open on a chart of "not yet".
    final selected = _month ??
        months.lastWhere(
          (m) => widget.cohorts.any((c) => c.month == m && c.d30 != null),
          orElse: () => months.last,
        );

    CohortRow? row(String segment) {
      for (final c in widget.cohorts) {
        if (c.month == selected && c.segment == segment) return c;
      }
      return null;
    }

    final wallet = row('wallet');
    final noWallet = row('no_wallet');
    final brightness = Theme.of(context).brightness;
    final loc = MaterialLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashCohortTitle, style: text.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in months)
              ChoiceChip(
                selected: m == selected,
                onSelected: (_) => setState(() => _month = m),
                label: Text(loc.formatMonthYear(m)),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Legend present AND both series directly labelled (DESIGN 9.3, 9.4).
        Wrap(
          spacing: 16,
          children: [
            _LegendKey(color: ChartPalette.series1(brightness), label: l10n.dashCohortWallet),
            _LegendKey(color: ChartPalette.series2(brightness), label: l10n.dashCohortNoWallet),
          ],
        ),
        const SizedBox(height: 4),
        Text(l10n.dashCohortAxis, style: text.labelSmall),
        const SizedBox(height: 8),

        for (final days in const [30, 60, 90])
          _BarGroup(
            days: days,
            wallet: wallet,
            noWallet: noWallet,
            brightness: brightness,
          ),

        const SizedBox(height: 16),
        // The table view: the accessibility fallback, and what the owner will
        // screenshot (DESIGN 9.4).
        Text(l10n.dashCohortTable, style: text.titleSmall),
        const SizedBox(height: 8),
        _CohortTable(cohorts: widget.cohorts),
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 8),
        // Text wears ink, never the series colour (DESIGN 9.3).
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _BarGroup extends StatelessWidget {
  const _BarGroup({
    required this.days,
    required this.wallet,
    required this.noWallet,
    required this.brightness,
  });

  final int days;
  final CohortRow? wallet;
  final CohortRow? noWallet;
  final Brightness brightness;

  double? _rate(CohortRow? r) => switch (days) {
        30 => r?.d30,
        60 => r?.d60,
        _ => r?.d90,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dashCohortWithin(days), style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          _Bar(
            rate: _rate(wallet),
            n: wallet?.n,
            color: ChartPalette.series1(brightness),
            label: l10n.dashCohortWallet,
            brightness: brightness,
          ),
          const SizedBox(height: 4),
          _Bar(
            rate: _rate(noWallet),
            n: noWallet?.n,
            color: ChartPalette.series2(brightness),
            label: l10n.dashCohortNoWallet,
            brightness: brightness,
          ),
        ],
      ),
    );
  }
}

/// One horizontal bar. Built from widgets rather than painted, so it is
/// tappable, readable by a screen reader, and testable - and a NULL rate is a
/// visible "not yet", never a zero-length bar that reads as 0%.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.rate,
    required this.n,
    required this.color,
    required this.label,
    required this.brightness,
  });

  final double? rate;
  final int? n;
  final Color color;
  final String label;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final text = Theme.of(context).textTheme;
    final pct = rate;
    final summary = pct == null
        ? '$label: ${l10n.dashCohortNotYet}'
        : '$label: ${pct.toStringAsFixed(1)}% · ${l10n.dashCohortN(n ?? 0)}';

    return Tooltip(
      // Tap-to-pin on mobile (DESIGN 9.5): the exact figure AND the n.
      triggerMode: TooltipTriggerMode.tap,
      message: summary,
      child: Semantics(
        label: summary,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (pct == null) {
                    return Container(
                      height: 20,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border.all(color: ChartPalette.gridline(brightness)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(l10n.dashCohortNotYet, style: text.labelSmall),
                    );
                  }
                  return Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: ChartPalette.gridline(brightness),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        height: 20,
                        width: constraints.maxWidth * (pct.clamp(0, 100) / 100),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Direct label, in ink (DESIGN 9.3).
            SizedBox(
              width: 56,
              child: Text(
                pct == null ? '' : '${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(fontFeatures: moneyFeatures),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CohortTable extends StatelessWidget {
  const _CohortTable({required this.cohorts});

  final List<CohortRow> cohorts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final loc = MaterialLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: moneyFeatures);
    String pct(double? v) => v == null ? l10n.dashCohortNotYet : '${v.toStringAsFixed(1)}%';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingTextStyle: Theme.of(context).textTheme.labelSmall,
        columns: [
          DataColumn(label: Text(l10n.dashCohortMonth)),
          DataColumn(label: Text(l10n.dashCohortGroup)),
          const DataColumn(label: Text('n'), numeric: true),
          const DataColumn(label: Text('30'), numeric: true),
          const DataColumn(label: Text('60'), numeric: true),
          const DataColumn(label: Text('90'), numeric: true),
        ],
        rows: [
          for (final c in cohorts)
            DataRow(cells: [
              DataCell(Text(loc.formatMonthYear(c.month), style: style)),
              DataCell(Text(
                c.segment == 'wallet' ? l10n.dashCohortWallet : l10n.dashCohortNoWallet,
                style: style,
              )),
              DataCell(Text('${c.n}', style: style)),
              DataCell(Text(pct(c.d30), style: style)),
              DataCell(Text(pct(c.d60), style: style)),
              DataCell(Text(pct(c.d90), style: style)),
            ]),
        ],
      ),
    );
  }
}
