import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/performance_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';

class TeamPerformanceScreen extends StatefulWidget {
  const TeamPerformanceScreen({super.key});

  @override
  State<TeamPerformanceScreen> createState() => _TeamPerformanceScreenState();
}

class _TeamPerformanceScreenState extends State<TeamPerformanceScreen> {
  TeamPerformance? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known figures instantly if
    // cached, then quietly refresh — same reasoning as MachineListScreen.
    final cached = PerformanceService.cachedTeam;
    if (cached != null) { _data = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_data == null) _loading = true;
      _error = null;
    });
    try {
      final data = await PerformanceService.instance.team();
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
                    final wide = cst.maxWidth >= 1000;
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(pad),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 13),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Team Performance', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                              const SizedBox(height: 3),
                              Text('${d.period} · ${d.repsCount} rep${d.repsCount == 1 ? '' : 's'} · exact figures', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                            ])),
                          ]),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
                            child: Row(children: [
                              Expanded(child: _kpiTile(context, Symbols.payments, AppColors.teal, 'Revenue MTD', tshFromDouble(d.revenueMtd.toDouble()), 'across the team')),
                              Expanded(child: _kpiTile(context, Symbols.filter_alt, AppColors.cyan, 'Team pipeline', tshFromDouble(d.teamPipeline.toDouble()), 'open deals', border: true)),
                              Expanded(child: _kpiTile(context, Symbols.fact_check, AppColors.amber, 'Awaiting my approval', '${d.awaitingMyApproval}', 'quotes', border: true)),
                              Expanded(child: _kpiTile(context, Symbols.handshake, AppColors.green, 'Commission owed', tshFromDouble(d.commissionOwed.toDouble()), 'across reps', border: true)),
                              Expanded(child: _kpiTile(context, Symbols.report, AppColors.coral, 'Receivable overdue', tshFromDouble(d.receivableOverdue.toDouble()), 'past due date', border: true, warn: d.receivableOverdue > 0)),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          wide
                              ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Expanded(flex: 13, child: Column(children: [
                                    _revenueChart(context, d),
                                    const SizedBox(height: 16),
                                    _hospitalCard(context, d),
                                  ])),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 10, child: _leaderboard(context, d)),
                                ]))
                              : Column(children: [
                                  _revenueChart(context, d),
                                  const SizedBox(height: 16),
                                  _hospitalCard(context, d),
                                  const SizedBox(height: 16),
                                  _leaderboard(context, d),
                                ]),
                        ]),
                      ),
                    );
                  });
  }

  Widget _kpiTile(BuildContext context, IconData icon, Color color, String label, String value, String note, {bool border = false, bool warn = false}) => Container(
    padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
    decoration: border ? BoxDecoration(border: Border(left: BorderSide(color: context.pal.border.withValues(alpha: context.pal.border.a * 0.4)))) : null,
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 7),
        Expanded(child: Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 7),
      Text(value, style: AppTheme.kpiValue.copyWith(fontSize: 20, color: warn ? color : null), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 5),
      Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _revenueChart(BuildContext context, TeamPerformance d) {
    final maxV = d.revenueByMonth.fold<int>(1, (a, m) => m.actual > a ? m.actual : a);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.bar_chart, size: 13, color: AppColors.teal),
          const SizedBox(width: 8),
          Text('REVENUE — ACTUAL', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
          const SizedBox(width: 8),
          Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 130, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: d.revenueByMonth.map((m) => Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(m.actual > 0 ? tshFromDouble(m.actual.toDouble()) : '', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute)),
            const SizedBox(height: 4),
            Container(
              width: 22, height: 90 * (m.actual / maxV).clamp(0.02, 1.0),
              decoration: BoxDecoration(color: AppColors.teal, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
            ),
            const SizedBox(height: 6),
            Text(m.name, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
          ]),
        )).toList())),
        const SizedBox(height: 10),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 9),
        Row(children: [
          Text('YTD ${tshFromDouble(d.ytdActual.toDouble())}', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textMute)),
        ]),
      ]),
    );
  }

  Widget _hospitalCard(BuildContext context, TeamPerformance d) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.medical_services, size: 13, color: AppColors.green),
        const SizedBox(width: 8),
        Text('REVENUE BY HOSPITAL', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 8),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        Text('top ${d.revenueByHospital.length}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
      ]),
      const SizedBox(height: 12),
      if (d.revenueByHospital.isEmpty)
        Text('No confirmed revenue by hospital this month yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else
        ...d.revenueByHospital.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(children: [
            Expanded(child: Text(h.name, style: AppTheme.bodySub.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 11),
            SizedBox(width: 100, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
              value: h.pct / 100, minHeight: 7, backgroundColor: context.pal.surface2,
              valueColor: AlwaysStoppedAnimation(AppColors.green),
            ))),
            const SizedBox(width: 11),
            SizedBox(width: 78, child: Text(tshFromDouble(h.value.toDouble()), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 11.5))),
          ]),
        )),
    ]),
  );

  Widget _leaderboard(BuildContext context, TeamPerformance d) => Container(
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.violet.withValues(alpha: 0.28))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
        child: Row(children: [
          Icon(Symbols.emoji_events, size: 14, color: AppColors.violet),
          const SizedBox(width: 9),
          Expanded(child: Text('Rep leaderboard', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
          Text('commission owed ${tshFromDouble(d.commissionOwed.toDouble())}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: AppColors.violet)),
        ]),
      ),
      Container(width: double.infinity, height: 1, color: context.pal.divider),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Expanded(child: Text('REP', style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
          SizedBox(width: 36, child: Text('WON', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
          SizedBox(width: 86, child: Text('REVENUE', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
          SizedBox(width: 82, child: Text('COMM. OWED', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute))),
        ]),
      ),
      if (d.leaderboard.isEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Text('No reps on your team yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
      else
        ...d.leaderboard.map((r) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Expanded(child: Row(children: [
              Container(width: 22, height: 22, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.7), shape: BoxShape.circle),
                  child: Text(r.initials, style: AppTheme.monoXs.copyWith(fontSize: 8.5, color: Colors.white))),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(r.name, style: AppTheme.bodySm.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (r.zone != null) Text(r.zone!, style: AppTheme.bodySub.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ])),
            SizedBox(width: 36, child: Text('${r.won}', textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 11.5))),
            SizedBox(width: 86, child: Text(tshFromDouble(r.revenue.toDouble()), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 11.5))),
            SizedBox(width: 82, child: Text(tshFromDouble(r.commissionOwed.toDouble()), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 11.5, color: AppColors.green))),
          ]),
        )),
    ]),
  );
}
