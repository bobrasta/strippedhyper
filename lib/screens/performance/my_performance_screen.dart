import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/performance_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';

const _stageLabels = {
  'lead': 'Lead', 'qualified': 'Qualified', 'demo_scheduled': 'Demo scheduled',
  'proposal_sent': 'Proposal sent', 'negotiation': 'Negotiation',
};
final _stageColors = {
  'lead': AppColors.textDim, 'qualified': AppColors.green, 'demo_scheduled': AppColors.violet,
  'proposal_sent': AppColors.amber, 'negotiation': AppColors.coral,
};

class MyPerformanceScreen extends StatefulWidget {
  const MyPerformanceScreen({super.key});

  @override
  State<MyPerformanceScreen> createState() => _MyPerformanceScreenState();
}

class _MyPerformanceScreenState extends State<MyPerformanceScreen> {
  MyPerformance? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known figures instantly if
    // cached, then quietly refresh — same reasoning as MachineListScreen.
    final cached = PerformanceService.cachedMine;
    if (cached != null) { _data = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_data == null) _loading = true;
      _error = null;
    });
    try {
      final data = await PerformanceService.instance.mine();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        // A background refresh failing while stale-but-valid cached data
        // is already showing shouldn't blow that away.
        : _error != null && d == null
            ? ErrorView(message: _error!, onRetry: _load)
            : d == null
                ? const SizedBox.shrink()
                : LayoutBuilder(builder: (context, cst) {
                    final pad = cst.maxWidth < 700 ? 16.0 : 24.0;
                    final wide = cst.maxWidth >= 900;
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(pad),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(width: 2, height: 36, decoration: BoxDecoration(color: context.pal.textDim, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 13),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('My Performance', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                              const SizedBox(height: 3),
                              Text(d.period, style: AppTheme.bodySub.copyWith(fontSize: 12)),
                            ])),
                          ]),
                          const SizedBox(height: 16),
                          _kpiRow(context, d),
                          const SizedBox(height: 16),
                          if (d.sales != null)
                            wide
                                ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    Expanded(flex: 6, child: _leadsFunnel(context, d.sales!)),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 5, child: Column(children: [
                                      _quotesChart(context, d.sales!),
                                      const SizedBox(height: 16),
                                      _commissionCard(context, d.sales!),
                                    ])),
                                  ]))
                                : Column(children: [
                                    _leadsFunnel(context, d.sales!),
                                    const SizedBox(height: 16),
                                    _quotesChart(context, d.sales!),
                                    const SizedBox(height: 16),
                                    _commissionCard(context, d.sales!),
                                  ]),
                          if (d.sales == null)
                            _tasksBreakdown(context, d.tasks),
                        ]),
                      ),
                    );
                  });
  }

  Widget _kpiRow(BuildContext context, MyPerformance d) {
    final tiles = <Widget>[];
    if (d.sales != null) {
      final s = d.sales!;
      tiles.addAll([
        _kpi(context, Symbols.filter_alt, AppColors.cyan, 'My open pipeline', tshFromDouble(s.pipelineValue.toDouble()), '${s.openLeads} leads across 5 stages'),
        _kpi(context, Symbols.description, AppColors.amber, 'Quotations sent', '${s.quotationsSentThisMonth}', 'this month'),
        _kpi(context, Symbols.emoji_events, AppColors.green, 'Quotations accepted', '${s.quotationsAcceptedThisMonth}', 'this month'),
        _kpi(context, Symbols.handshake, AppColors.green, 'Commission MTD', tshFromDouble(s.commissionMtd.toDouble()), 'across confirmed orders'),
      ]);
    }
    tiles.addAll([
      _kpi(context, Symbols.task_alt, AppColors.violet, 'Tasks completed', '${d.tasks.completed}', 'this period'),
      _kpi(context, Symbols.pending_actions, AppColors.textDim, 'Tasks pending', '${d.tasks.pending}', d.tasks.overdue > 0 ? '${d.tasks.overdue} overdue' : 'on track'),
    ]);

    return Wrap(spacing: 12, runSpacing: 12, children: tiles.map((t) => SizedBox(width: 220, child: t)).toList());
  }

  Widget _kpi(BuildContext context, IconData icon, Color color, String label, String value, String note) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(13), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 7),
        Expanded(child: Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 7),
      Text(value, style: AppTheme.kpiValue.copyWith(fontSize: 21)),
      const SizedBox(height: 3),
      Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _leadsFunnel(BuildContext context, MySalesPerformance s) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.filter_alt, size: 13, color: AppColors.teal),
        const SizedBox(width: 8),
        Text('MY LEADS BY STAGE', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 8),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        Text(tshFromDouble(s.pipelineValue.toDouble()), style: AppTheme.monoXs.copyWith(fontSize: 11)),
      ]),
      const SizedBox(height: 14),
      for (final stage in s.leadsByStage) Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: _stageColors[stage.stage] ?? AppColors.textDim, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 9),
            Expanded(child: Text(_stageLabels[stage.stage] ?? stage.stage, style: AppTheme.bodySm.copyWith(fontSize: 12))),
            Text('${stage.count}', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
            const SizedBox(width: 8),
            Text(tshFromDouble(stage.value.toDouble()), style: AppTheme.monoSm.copyWith(fontSize: 12)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
            value: stage.pct / 100, minHeight: 7, backgroundColor: context.pal.surface2,
            valueColor: AlwaysStoppedAnimation(_stageColors[stage.stage] ?? AppColors.textDim),
          )),
        ]),
      ),
    ]),
  );

  Widget _quotesChart(BuildContext context, MySalesPerformance s) {
    final maxV = s.monthlyChart.fold<int>(1, (a, m) => [a, m.sent, m.accepted].reduce((x, y) => x > y ? x : y));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.description, size: 13, color: AppColors.amber),
          const SizedBox(width: 8),
          Text('QUOTATIONS SENT VS ACCEPTED', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 90, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: s.monthlyChart.map((m) => Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 70 * (m.sent / maxV).clamp(0.03, 1.0), color: AppColors.amber, margin: const EdgeInsets.symmetric(horizontal: 1.5)),
              Container(width: 8, height: 70 * (m.accepted / maxV).clamp(0.03, 1.0), color: AppColors.green, margin: const EdgeInsets.symmetric(horizontal: 1.5)),
            ]),
            const SizedBox(height: 5),
            Text(m.name, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
          ]),
        )).toList())),
        const SizedBox(height: 10),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 9),
        Row(children: [
          Container(width: 7, height: 7, color: AppColors.amber), const SizedBox(width: 5),
          Text('sent', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
          const SizedBox(width: 12),
          Container(width: 7, height: 7, color: AppColors.green), const SizedBox(width: 5),
          Expanded(child: Text('accepted', style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
          Text('${s.acceptRate}% accept rate', style: AppTheme.monoXs.copyWith(fontSize: 11, color: AppColors.green)),
        ]),
      ]),
    );
  }

  Widget _commissionCard(BuildContext context, MySalesPerformance s) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.green.withValues(alpha: 0.28))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.handshake, size: 15, color: AppColors.green),
        const SizedBox(width: 8),
        Expanded(child: Text('My commission', style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
      ]),
      const SizedBox(height: 9),
      Text(tshFromDouble(s.commissionMtd.toDouble()), style: AppTheme.kpiValue.copyWith(fontSize: 24, color: AppColors.green)),
      const SizedBox(height: 8),
      Text('From confirmed orders this month. Locked at confirmation — not recalculated later.',
          style: AppTheme.bodySub.copyWith(fontSize: 11)),
    ]),
  );

  Widget _tasksBreakdown(BuildContext context, TaskStats t) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TASKS', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
      const SizedBox(height: 4),
      Text('No sales activity on your account this period — showing task completion only.',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
    ]),
  );
}
