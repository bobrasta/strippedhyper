import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/sales_dashboard_service.dart';
import '../../services/sales_overview_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import 'log_activity_dialog.dart';
import 'sales_targets_dialog.dart';

// Sales Dashboard v3 — "Will we land the quarter?". The top shows revenue
// against target and whether committed deals cover the gap; the bottom shows
// what moves that number: deals committed to close, the day's activity, and
// warranties about to lapse. Same layout for the manager (whole team) and a
// rep (own book, figures rounded server-side) — see SalesOverviewController
// for every definition behind these numbers.

const _periods = {'month': 'Month', 'quarter': 'Quarter', 'year': 'Year'};

class SalesDashboardScreen extends StatefulWidget {
  const SalesDashboardScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen> {
  // App-wide rule: this year unless the user picks otherwise.
  String _period = 'year';
  SalesOverview? _data;
  SalesDashboardData? _kpi;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — see MachineService.
    _data = SalesOverviewService.cached[_period];
    _kpi = SalesDashboardService.cachedData;
    _loading = _data == null;
    _load();
  }

  Future<void> _load() async {
    setState(() { if (_data == null) _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        SalesOverviewService.instance.load(period: _period),
        SalesDashboardService.instance.load(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as SalesOverview;
        _kpi = results[1] as SalesDashboardData;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _setPeriod(String p) {
    if (p == _period) return;
    setState(() { _period = p; _data = SalesOverviewService.cached[p] ?? _data; });
    _load();
  }

  Future<void> _logActivity() async {
    if (await showLogActivityDialog(context) == true) _load();
  }

  Future<void> _setTargets() async {
    if (await showSalesTargetsDialog(context) == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_data == null) return ErrorView(message: _error ?? 'Failed to load dashboard.', onRetry: _load);
    final d = _data!;

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 24.0;
      final wide = cst.maxWidth >= 1100;
      final trend = _TrendCard(d: d, onSetTargets: d.canSetTargets ? _setTargets : null);
      final forecast = _ForecastCard(d: d);
      final left = d.isTeam ? _RepsCard(d: d) : _DealsCard(d: d);
      final feed = _FeedCard(d: d);
      final warranties = _WarrantyCard(d: d);

      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context, d, wide),
            const SizedBox(height: 14),
            if (wide) ...[
              SizedBox(height: 370, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 175, child: trend),
                const SizedBox(width: 13),
                Expanded(flex: 100, child: forecast),
              ])),
              const SizedBox(height: 13),
              SizedBox(height: 400, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 115, child: left),
                const SizedBox(width: 13),
                Expanded(flex: 100, child: feed),
                const SizedBox(width: 13),
                Expanded(flex: 100, child: warranties),
              ])),
            ] else ...[
              SizedBox(height: 340, child: trend),
              const SizedBox(height: 13),
              SizedBox(height: 370, child: forecast),
              const SizedBox(height: 13),
              SizedBox(height: 360, child: left),
              const SizedBox(height: 13),
              SizedBox(height: 380, child: feed),
              const SizedBox(height: 13),
              SizedBox(height: 360, child: warranties),
            ],
          ]),
        ),
      );
    });
  }

  Widget _header(BuildContext context, SalesOverview d, bool wide) {
    final openDeals = _kpi?.openLeads;
    final approvals = _kpi?.quotationsPendingApproval ?? 0;
    final sub = [
      formatDate(DateTime.now()),
      '${d.period.label} closes in ${d.period.daysLeft} day${d.period.daysLeft == 1 ? '' : 's'}',
      if (d.isTeam && d.reps.isNotEmpty) '${d.reps.length} rep${d.reps.length == 1 ? '' : 's'}',
      if (openDeals != null) '$openDeals open deal${openDeals == 1 ? '' : 's'}',
      if (d.isMasked) 'figures rounded to the nearest 100K',
    ].join(' · ');

    final actions = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      _Segmented(value: _period, options: _periods, onChanged: _setPeriod, labelFor: (k) => k == 'quarter' && _period == 'quarter' ? d.period.label : _periods[k]!),
      if (d.canSetTargets) OutlinedButton.icon(onPressed: _setTargets, icon: const Icon(Symbols.target, size: 15), label: const Text('Targets')),
      if (d.isTeam && approvals > 0)
        OutlinedButton.icon(onPressed: () => widget.onNavigateTo?.call('sales_quotations'), icon: const Icon(Symbols.fact_check, size: 15),
            label: Text('Review $approvals approval${approvals == 1 ? '' : 's'}')),
      OutlinedButton.icon(onPressed: _logActivity, icon: const Icon(Symbols.edit_note, size: 15), label: const Text('Log activity')),
      FilledButton.icon(onPressed: () => widget.onNavigateTo?.call('sales_quotations'), icon: const Icon(Symbols.add, size: 16), label: const Text('New quotation')),
    ]);

    final title = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(width: 2, height: 40, decoration: BoxDecoration(color: d.isTeam ? AppColors.violet : AppColors.cyan, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.isTeam ? 'Sales Dashboard' : 'My Sales Dashboard', style: AppTheme.pageTitle.copyWith(fontSize: 22)),
        const SizedBox(height: 3),
        Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      ])),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (wide) Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: title), const SizedBox(width: 12), actions])
      else ...[title, const SizedBox(height: 12), actions],
      const SizedBox(height: 13),
      Container(height: 1, color: context.pal.divider),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Shared bits

String _m(int v) {
  final m = v / 1e6;
  if (m >= 10) return m.toStringAsFixed(0);
  return m.toStringAsFixed(1);
}

String _shortDate(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

Color _pctColor(int p) => p >= 100 ? AppColors.green : p >= 90 ? AppColors.amber : AppColors.coral;

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.iconColor, required this.title, this.trailing, required this.child, this.footer, this.footerIcon, this.footerColor});
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final Widget child;
  final String? footer;
  final IconData? footerIcon;
  final Color? footerColor;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
        child: Row(children: [
          Icon(icon, size: 14, color: iconColor, fill: 1),
          const SizedBox(width: 9),
          Flexible(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.labelCaps.copyWith(fontSize: 10.5))),
          const SizedBox(width: 8),
          const Spacer(),
          ?trailing,
        ]),
      ),
      Flexible(fit: FlexFit.loose, child: child),
      if (footer != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: context.pal.surface2.withValues(alpha: 0.5), border: Border(top: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Icon(footerIcon ?? Symbols.lightbulb, size: 14, color: footerColor ?? AppColors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(footer!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textMute))),
          ]),
        ),
    ]),
  );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged, required this.labelFor});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final String Function(String key) labelFor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(9), border: Border.all(color: context.pal.border)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final k in options.keys)
        GestureDetector(
          onTap: () => onChanged(k),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: k == value ? context.pal.surface3 : null, borderRadius: BorderRadius.circular(7)),
            child: Text(labelFor(k), style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: k == value ? context.pal.text : context.pal.textMute)),
          ),
        ),
    ]),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: AppTheme.bodySm.copyWith(fontSize: 10, color: color)),
  );
}

// ---------------------------------------------------------------------------
// Revenue vs target, 12 months

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.d, this.onSetTargets});
  final SalesOverview d;
  final VoidCallback? onSetTargets;

  @override
  Widget build(BuildContext context) {
    final months = d.months;
    final past = months.where((m) => !m.current).toList();
    final total = months.fold<int>(0, (a, m) => a + m.actual);
    final targetTotal = months.fold<int>(0, (a, m) => a + m.target);
    final vsPct = targetTotal > 0 ? (total / targetTotal * 100).round() : null;
    final withTarget = past.where((m) => m.target > 0).length;
    final hits = past.where((m) => m.hitTarget).length;
    final cur = months.isEmpty ? null : months.last;
    final scale = math.max(1, months.fold<int>(0, (a, m) => math.max(a, math.max(m.actual + m.projected, m.target)))) * 1.12;

    Widget legend(Color c, String t, {bool line = false, bool dashed = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: line ? 12 : 8, height: line ? 2 : 8,
          decoration: BoxDecoration(color: dashed ? null : c, borderRadius: BorderRadius.circular(2), border: dashed ? Border.all(color: c) : null)),
      const SizedBox(width: 5),
      Text(t, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
    ]);

    Widget stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9)),
      const SizedBox(height: 4),
      Text(value, style: AppTheme.kpiValue.copyWith(fontSize: 19, color: color)),
    ]);

    return _Card(
      icon: Symbols.bar_chart,
      iconColor: AppColors.green,
      title: d.isTeam ? 'Team revenue vs target · 12 months' : 'My revenue vs target · 12 months',
      // The legend crowds the title out on a phone — the bar colours are
      // self-explanatory enough there.
      trailing: MediaQuery.sizeOf(context).width < 700 ? null : Wrap(spacing: 12, children: [
        legend(AppColors.green, 'Hit target'),
        legend(AppColors.cyan.withValues(alpha: 0.45), 'Below'),
        legend(context.pal.text.withValues(alpha: 0.6), 'Target', line: true),
        legend(AppColors.cyan, 'Projected', dashed: true),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Wrap(spacing: 28, runSpacing: 10, children: [
            stat('12-month revenue', tshFromDouble(total), context.pal.text),
            stat('Vs target', vsPct == null ? '—' : '$vsPct%', vsPct == null ? context.pal.textDim : _pctColor(vsPct)),
            stat('Months on target', withTarget == 0 ? '—' : '$hits of $withTarget', context.pal.text),
            if (cur != null) stat('${cur.label} projected', '~${tshFromDouble(cur.actual + cur.projected)}', AppColors.cyan),
          ]),
        ),
        Expanded(child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in months) Expanded(child: _MonthBar(m: m, scale: scale.toDouble())),
            ]),
          ),
          if (!d.targetsSet)
            Positioned(right: 18, top: 10, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.info, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(onSetTargets != null ? 'No targets set yet' : 'Your manager hasn\'t set targets yet', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                if (onSetTargets != null) ...[
                  const SizedBox(width: 8),
                  InkWell(onTap: onSetTargets, child: Text('Set targets', style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: AppColors.green))),
                ],
              ]),
            )),
        ])),
      ]),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.m, required this.scale});
  final SalesMonth m;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final totalV = m.actual + m.projected;
    final barColor = m.current ? AppColors.cyan : m.hitTarget ? AppColors.green : AppColors.cyan.withValues(alpha: 0.4);
    final labelColor = m.current ? AppColors.cyan : m.hitTarget ? context.pal.textMute : context.pal.textDim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(children: [
        Expanded(child: LayoutBuilder(builder: (ctx, c) {
          final h = c.maxHeight;
          final barH = totalV / scale * h;
          final projH = m.projected / scale * h;
          final tgtY = m.target / scale * h;
          return Stack(clipBehavior: Clip.none, children: [
            Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: context.pal.divider)),
            Positioned(
              left: c.maxWidth * 0.16, right: c.maxWidth * 0.16, bottom: 0, height: barH,
              child: Column(children: [
                if (projH > 0)
                  Container(
                    height: projH,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.14),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.7)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ),
                Expanded(child: Container(decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: projH > 0 ? null : const BorderRadius.vertical(top: Radius.circular(5)),
                ))),
              ]),
            ),
            if (totalV > 0)
              Positioned(left: -8, right: -8, bottom: barH + 3, child: Text(
                m.current && m.projected > 0 ? '~${_m(totalV)}' : _m(m.actual),
                textAlign: TextAlign.center, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: labelColor),
              )),
            if (m.target > 0)
              Positioned(left: c.maxWidth * 0.04, right: c.maxWidth * 0.04, bottom: tgtY - 1,
                  child: Container(height: 2, decoration: BoxDecoration(color: context.pal.text.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(1)))),
          ]);
        })),
        const SizedBox(height: 7),
        Text(m.label, style: AppTheme.bodySub.copyWith(fontSize: 10, color: m.current ? context.pal.text : context.pal.textDim)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Forecast: closed + commit vs target

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.d});
  final SalesOverview d;

  @override
  Widget build(BuildContext context) {
    final f = d.forecast;
    final period = d.period;
    final segs = [
      ('Closed won', f.closed, AppColors.green, 'booked orders'),
      ('Commit', f.commit, AppColors.cyan, 'rep is confident'),
      ('Best case', f.bestCase, AppColors.amber, 'could close'),
      ('Pipeline', f.pipeline, context.pal.text.withValues(alpha: 0.16), 'not called yet'),
    ];
    final sum = segs.fold<int>(0, (a, s) => a + s.$2);
    final width = math.max(sum, f.target);
    final pct = f.target > 0 ? (f.forecast / f.target * 100).round() : null;

    final (statusText, statusColor, statusIcon) = f.target == 0
        ? ('No target set for ${period.label}', context.pal.textDim, Symbols.info)
        : f.gap <= 0
            ? ('$pct% of target — covered if commit lands', AppColors.green, Symbols.check_circle)
            : ('$pct% of target — ${tshFromDouble(f.gap)} short${f.bestCase >= f.gap ? ', best case would cover it' : ''}', AppColors.amber, Symbols.warning);

    final notes = <String>[
      if (f.openUndated > 0) '${f.openUndated} open deal${f.openUndated == 1 ? ' has' : 's have'} no expected close date',
      if (f.openSlipped > 0) '${f.openSlipped} ${f.openSlipped == 1 ? 'is' : 'are'} past ${f.openSlipped == 1 ? 'its' : 'their'} close date',
    ];

    return _Card(
      icon: Symbols.target,
      iconColor: AppColors.cyan,
      title: d.isTeam ? '${period.label} forecast · team' : 'My ${period.label} forecast',
      trailing: _Chip('${period.daysLeft} day${period.daysLeft == 1 ? '' : 's'} left', period.daysLeft <= 7 ? AppColors.amber : context.pal.textMute),
      footer: notes.isEmpty ? null : '${notes.join('; ')} — not counted above. Update them on the Leads board.',
      footerIcon: Symbols.event_busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FORECAST · CLOSED + COMMIT', style: AppTheme.labelCaps.copyWith(fontSize: 9)),
          const SizedBox(height: 6),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
            Text(tshFromDouble(f.forecast), style: AppTheme.kpiValue.copyWith(fontSize: 30, height: 1)),
            if (f.target > 0) Text('of ${tshFromDouble(f.target)} target', style: AppTheme.bodySub.copyWith(fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(statusIcon, size: 14, color: statusColor, fill: 1),
            const SizedBox(width: 6),
            Expanded(child: Text(statusText, style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: statusColor))),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth;
            return SizedBox(height: 32, child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 0, right: 0, top: 14, height: 14, child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: width == 0
                    ? Container(color: context.pal.surface3)
                    : Row(children: [
                        for (final s in segs)
                          if (s.$2 > 0) Container(width: math.max(0, s.$2 / width * w - 2), margin: const EdgeInsets.only(right: 2), color: s.$3),
                        const Spacer(),
                      ]),
              )),
              if (f.target > 0 && width > 0) ...[
                Positioned(left: (f.target / width * w - 1).clamp(0, w - 2), top: 11, bottom: 0, width: 2, child: Container(color: context.pal.text)),
                Positioned(left: (f.target / width * w - 20).clamp(0, w - 40), top: -2, width: 40,
                    child: Text('target', textAlign: TextAlign.center, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.text))),
              ],
            ]));
          }),
          const SizedBox(height: 10),
          for (final s in segs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 9),
                Expanded(child: Text(s.$1, style: AppTheme.bodySm.copyWith(fontSize: 12, color: context.pal.textMute))),
                Text(s.$4, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
                SizedBox(width: 88, child: Text(tshFromDouble(s.$2), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text))),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manager: commit by rep

class _RepsCard extends StatelessWidget {
  const _RepsCard({required this.d});
  final SalesOverview d;

  @override
  Widget build(BuildContext context) {
    final reps = d.reps;
    final scale = math.max(1, reps.fold<int>(0, (a, r) => math.max(a, math.max(r.target, r.closed + r.commit)))) * 1.1;

    // The rep furthest below target, and whether one of their own
    // best-case deals would close the gap.
    String? foot;
    final behind = reps.where((r) => r.target > 0 && r.closed + r.commit < r.target).toList()
      ..sort((a, b) => (b.target - b.closed - b.commit).compareTo(a.target - a.closed - a.commit));
    if (behind.isNotEmpty) {
      final r = behind.first;
      final gap = r.target - r.closed - r.commit;
      final rescue = d.deals.where((x) => x.rep == r.name && x.category == 'best_case' && x.value >= gap).toList();
      foot = '${r.name.split(' ').first} is ${tshFromDouble(gap)} short.'
          '${rescue.isNotEmpty ? ' ${rescue.first.client} (${tshFromDouble(rescue.first.value)}, best case) would take them over.' : ''}';
    } else if (reps.isNotEmpty && reps.any((r) => r.target > 0)) {
      foot = 'Every rep with a target is covered if their commit deals land.';
    }

    return _Card(
      icon: Symbols.sports_score,
      iconColor: AppColors.violet,
      title: 'Commit by rep',
      trailing: Text('closed + commit / target', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
      footer: foot,
      child: reps.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text('No rep has a target, booked revenue or committed deals this period.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (final r in reps)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider.withValues(alpha: context.pal.divider.a * 0.5)))),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28, alignment: Alignment.center,
                      decoration: BoxDecoration(color: context.pal.surface3, shape: BoxShape.circle),
                      child: Text(r.initials, style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
                        Text('${_m(r.closed)} + ${_m(r.commit)} / ${r.target > 0 ? '${_m(r.target)}M' : 'no target'}',
                            style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
                      ]),
                      const SizedBox(height: 7),
                      LayoutBuilder(builder: (ctx, c) {
                        final w = c.maxWidth;
                        return SizedBox(height: 12, child: Stack(clipBehavior: Clip.none, children: [
                          Positioned(left: 0, right: 0, top: 3, height: 6, child: Container(decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(3)))),
                          Positioned(left: 0, top: 3, height: 6, width: r.closed / scale * w,
                              child: Container(decoration: BoxDecoration(color: AppColors.green, borderRadius: const BorderRadius.horizontal(left: Radius.circular(3))))),
                          Positioned(left: r.closed / scale * w, top: 3, height: 6, width: r.commit / scale * w,
                              child: Container(color: AppColors.cyan.withValues(alpha: 0.7))),
                          if (r.target > 0)
                            Positioned(left: r.target / scale * w - 1, top: 0, bottom: 0, width: 2, child: Container(color: context.pal.text)),
                        ]));
                      }),
                    ])),
                    SizedBox(width: 50, child: Text(r.target > 0 ? '${r.pct}%' : '—', textAlign: TextAlign.right,
                        style: AppTheme.kpiValue.copyWith(fontSize: 15, color: r.target > 0 ? _pctColor(r.pct) : context.pal.textDim))),
                  ]),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Rep: my deals to close this period

class _DealsCard extends StatelessWidget {
  const _DealsCard({required this.d});
  final SalesOverview d;

  @override
  Widget build(BuildContext context) {
    final f = d.forecast;
    String? foot;
    if (f.target > 0 && f.gap > 0) {
      final best = d.deals.where((x) => x.category == 'best_case').toList()..sort((a, b) => b.value.compareTo(a.value));
      foot = 'You\'re ${tshFromDouble(f.gap)} short.'
          '${best.isNotEmpty ? ' Closing ${best.first.client} takes you to ${((f.forecast + best.first.value) / f.target * 100).round()}%.' : ''}';
    } else if (f.target > 0) {
      foot = 'Covered if your commit deals land.';
    } else if (d.deals.isEmpty) {
      foot = 'Set an expected close date and forecast on your leads to see them here.';
    }

    return _Card(
      icon: Symbols.sports_score,
      iconColor: AppColors.violet,
      title: 'My deals to close · ${d.period.label}',
      trailing: Text('by ${_shortDate(DateTime.now().add(Duration(days: d.period.daysLeft)))}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
      footer: foot,
      child: d.deals.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text('No open deals are dated to close this period.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (final x in d.deals)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider.withValues(alpha: context.pal.divider.a * 0.5)))),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.client, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                      const SizedBox(height: 3),
                      Text('${x.machineType}${x.closeDate != null ? ' · closes ${_shortDate(x.closeDate!)}' : ''}', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                    ])),
                    _Chip(switch (x.category) { 'commit' => 'Commit', 'best_case' => 'Best case', _ => 'Pipeline' },
                        switch (x.category) { 'commit' => AppColors.cyan, 'best_case' => AppColors.amber, _ => context.pal.textMute }),
                    SizedBox(width: 84, child: Text(tshFromDouble(x.value), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text))),
                  ]),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity feed: team activity / my day

class _FeedCard extends StatefulWidget {
  const _FeedCard({required this.d});
  final SalesOverview d;

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  String _filter = 'all';

  static const _kindIcons = <String, (IconData, Color?)>{
    'call': (Symbols.call, null), 'visit': (Symbols.location_on, null), 'meeting': (Symbols.groups, null),
    'demo': (Symbols.co_present, AppColors.violet), 'email': (Symbols.mail, null), 'whatsapp': (Symbols.chat, null),
    'quote': (Symbols.description, null), 'won': (Symbols.emoji_events, null), 'follow_up': (Symbols.event_upcoming, null),
  };

  Color _kindColor(String k) => switch (k) {
    'call' => AppColors.cyan, 'visit' => AppColors.amber, 'demo' => AppColors.violet, 'won' => AppColors.green,
    'follow_up' => AppColors.cyan, _ => context.pal.textMute,
  };

  String _group(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    return switch (diff) { 0 => 'Today', -1 => 'Yesterday', 1 => 'Tomorrow', _ => _shortDate(at) };
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final items = d.activity.where((a) => switch (_filter) {
      'calls' => a.kind == 'call',
      'visits' => a.kind == 'visit' || a.kind == 'demo' || a.kind == 'meeting',
      _ => true,
    }).toList();
    final upcoming = items.where((a) => a.upcoming).toList()..sort((a, b) => a.at.compareTo(b.at));
    final done = items.where((a) => !a.upcoming).toList();

    final rows = <Widget>[];
    if (upcoming.isNotEmpty) {
      rows.add(_groupLabel('Up next'));
      rows.addAll(upcoming.map(_item));
    }
    String? lastGroup;
    for (final a in done) {
      final g = upcoming.isNotEmpty && lastGroup == null ? 'Done · ${_group(a.at)}' : _group(a.at);
      if (_group(a.at) != lastGroup) rows.add(_groupLabel(g));
      lastGroup = _group(a.at);
      rows.add(_item(a));
    }

    return _Card(
      icon: Symbols.monitor_heart,
      iconColor: AppColors.cyan,
      title: d.isTeam ? 'Team activity' : 'My day',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final f in const [('all', 'All'), ('calls', 'Calls'), ('visits', 'Visits')])
          GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: _filter == f.$1 ? context.pal.surface3 : null, borderRadius: BorderRadius.circular(5)),
              child: Text(f.$2, style: AppTheme.bodySm.copyWith(fontSize: 10.5, color: _filter == f.$1 ? context.pal.text : context.pal.textDim)),
            ),
          ),
      ]),
      child: rows.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text(
              d.isTeam ? 'Nothing logged by the team in the last 7 days.' : 'Nothing logged or planned. Use "Log activity" to record a call or plan a visit.',
              style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: rows),
    );
  }

  Widget _groupLabel(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(t.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9, color: context.pal.textDim)),
  );

  Widget _item(SalesFeedItem a) {
    final icon = _kindIcons[a.kind]?.$1 ?? Symbols.bolt;
    final color = _kindColor(a.kind);
    final meta = widget.d.isTeam ? [a.by, a.client].whereType<String>().join(' · ') : (a.client ?? '');
    final now = DateTime.now();
    final sameDay = a.at.year == now.year && a.at.month == now.month && a.at.day == now.day;
    final time = a.dateOnly ? (sameDay ? 'today' : _shortDate(a.at)) : sameDay || a.upcoming ? formatTime(a.at) : _shortDate(a.at);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: a.upcoming ? null : context.pal.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: a.upcoming ? AppColors.cyan.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Icon(icon, size: 14, color: color, fill: a.kind == 'won' ? 1 : 0),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12)),
          if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
        ])),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(top: 2), child: Text(time, style: AppTheme.monoXs.copyWith(fontSize: 10, color: a.upcoming ? AppColors.cyan : context.pal.textDim))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Warranties lapsing in 60 days. There's no service-contract model, so this
// shows warranty expiry (the moment to sell a service contract) and whether
// anyone already has an open deal at that hospital — not contract values.

class _WarrantyCard extends StatelessWidget {
  const _WarrantyCard({required this.d});
  final SalesOverview d;

  @override
  Widget build(BuildContext context) {
    final w = d.warranties;
    final urgent = w.where((x) => x.daysLeft <= 14 && !x.openDeal).toList();
    final foot = w.isEmpty
        ? null
        : urgent.isNotEmpty
            ? '${urgent.length} warrant${urgent.length == 1 ? 'y lapses' : 'ies lapse'} within 14 days with no open deal${urgent.length == 1 ? ' — ${urgent.first.client}' : ''}.'
            : 'Every warranty lapsing in the next 14 days already has an open deal.';

    return _Card(
      icon: Symbols.autorenew,
      iconColor: AppColors.amber,
      title: 'Warranties expiring · 60 days',
      trailing: Text('${w.length}', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
      footer: foot,
      footerIcon: Symbols.error,
      footerColor: AppColors.coral,
      child: w.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text(
              d.isTeam ? 'No machine warranties lapse in the next 60 days.' : 'No warranties lapse in the next 60 days at hospitals you work with.',
              style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (final x in w)
                Builder(builder: (context) {
                  final hot = x.daysLeft <= 14 && !x.openDeal;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider.withValues(alpha: context.pal.divider.a * 0.5)))),
                    child: Row(children: [
                      Container(
                        width: 40, padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(color: hot ? AppColors.amber.withValues(alpha: 0.1) : context.pal.surface2, borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          Text('${x.daysLeft}', style: AppTheme.kpiValue.copyWith(fontSize: 15, height: 1.1, color: hot ? AppColors.amber : context.pal.textMute)),
                          Text('DAYS', style: AppTheme.labelCaps.copyWith(fontSize: 8, color: hot ? AppColors.amber : context.pal.textDim)),
                        ]),
                      ),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.client, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12)),
                        const SizedBox(height: 2),
                        Text('${x.type} · ${x.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
                      ])),
                      const SizedBox(width: 8),
                      _Chip(x.openDeal ? 'Open deal' : 'No open deal', x.openDeal ? AppColors.green : AppColors.coral),
                    ]),
                  );
                }),
            ]),
    );
  }
}
