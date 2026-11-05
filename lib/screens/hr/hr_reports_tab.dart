import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/attendance_service.dart';
import '../../services/hr_report_service.dart';
import '../../services/payroll_service.dart';
import '../../services/recruitment_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';

/// HR Reports — ported from HR Redesign spec 1i: charts instead of stacked
/// number chips. A 6-KPI strip plus a 2×3 grid of chart cards, all built
/// from real HR data (headcount/leave/contracts/attendance/recruitment/
/// discipline), no fabricated figures.
class HrReportsTab extends StatefulWidget {
  const HrReportsTab({super.key});

  @override
  State<HrReportsTab> createState() => _HrReportsTabState();
}

class _HrReportsTabState extends State<HrReportsTab> {
  bool _loading = true;
  bool _exportingPdf = false;
  String? _error;

  HeadcountBreakdown? _headcount;
  HrTurnoverReport? _turnover;
  List<HrLeaveBalanceRow> _leaveBalances = [];
  RecruitmentSummary? _recruitment;
  List<Vacancy> _vacancies = [];
  List<ContractExpiringEntry> _contractsExpiring = [];
  ContractsSummary? _contractsSummary;
  DisciplinarySummary? _discipline;
  List<CareerProgressionEntry> _careerLog = [];
  List<PayrollRun> _payrollRuns = [];
  List<AttendanceRecord> _attendance = [];
  List<StaffMember> _staff = [];

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning. This dashboard combines 12 independent pieces, so
    // "loading" is only true when NONE of them have anything cached yet.
    final now = DateTime.now();
    final attStart = DateTime(now.year, now.month - 5, 1);
    final attendanceKey = '${_fmt(attStart)}|${_fmt(now)}|';
    final cachedHeadcount    = HrReportService.cachedHeadcount;
    final cachedTurnover     = HrReportService.cachedTurnover;
    final cachedBalances     = HrReportService.cachedDefaultLeaveBalances;
    final cachedRecruitment  = HrReportService.cachedRecruitmentSummary;
    final cachedVacancies    = RecruitmentService.cachedDefaultVacancies;
    final cachedExpiring     = HrReportService.cachedContractsExpiringByDays[90];
    final cachedContractsSum = HrReportService.cachedContractsSummary;
    final cachedDiscipline   = HrReportService.cachedDisciplinarySummary;
    final cachedCareer       = HrReportService.cachedCareerProgressions;
    final cachedRuns         = PayrollService.cachedRuns;
    final cachedAttendance   = AttendanceService.cachedByQuery[attendanceKey];
    final cachedStaff        = StaffService.instance.staffNotifier.value;
    if (cachedHeadcount != null) _headcount = cachedHeadcount;
    if (cachedTurnover != null) _turnover = cachedTurnover;
    if (cachedBalances != null) _leaveBalances = cachedBalances;
    if (cachedRecruitment != null) _recruitment = cachedRecruitment;
    if (cachedVacancies != null) _vacancies = cachedVacancies;
    if (cachedExpiring != null) _contractsExpiring = cachedExpiring;
    if (cachedContractsSum != null) _contractsSummary = cachedContractsSum;
    if (cachedDiscipline != null) _discipline = cachedDiscipline;
    if (cachedCareer != null) _careerLog = cachedCareer;
    if (cachedRuns != null) _payrollRuns = cachedRuns;
    if (cachedAttendance != null) _attendance = cachedAttendance;
    if (cachedStaff.isNotEmpty) _staff = cachedStaff;
    if (cachedHeadcount != null || cachedTurnover != null || cachedBalances != null ||
        cachedRecruitment != null || cachedVacancies != null || cachedExpiring != null ||
        cachedContractsSum != null || cachedDiscipline != null || cachedCareer != null ||
        cachedRuns != null || cachedAttendance != null || cachedStaff.isNotEmpty) {
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_headcount == null && _turnover == null && _leaveBalances.isEmpty && _recruitment == null &&
          _vacancies.isEmpty && _contractsExpiring.isEmpty && _contractsSummary == null &&
          _discipline == null && _careerLog.isEmpty && _payrollRuns.isEmpty && _attendance.isEmpty &&
          _staff.isEmpty) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final now = DateTime.now();
      final attStart = DateTime(now.year, now.month - 5, 1);
      final results = await Future.wait([
        HrReportService.instance.headcount(),
        HrReportService.instance.turnover(),
        HrReportService.instance.leaveBalances(),
        HrReportService.instance.recruitmentSummary(),
        RecruitmentService.instance.vacancies(),
        HrReportService.instance.contractsExpiring(),
        HrReportService.instance.contractsSummary(),
        HrReportService.instance.disciplinarySummary(),
        HrReportService.instance.careerProgressions(),
        PayrollService.instance.runs(),
        AttendanceService.instance.list(start: _fmt(attStart), end: _fmt(now)),
        StaffService.instance.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _headcount          = results[0] as HeadcountBreakdown;
        _turnover           = results[1] as HrTurnoverReport;
        _leaveBalances      = results[2] as List<HrLeaveBalanceRow>;
        _recruitment        = results[3] as RecruitmentSummary;
        _vacancies          = results[4] as List<Vacancy>;
        _contractsExpiring  = results[5] as List<ContractExpiringEntry>;
        _contractsSummary   = results[6] as ContractsSummary;
        _discipline         = results[7] as DisciplinarySummary;
        _careerLog          = results[8] as List<CareerProgressionEntry>;
        _payrollRuns        = results[9] as List<PayrollRun>;
        _attendance         = results[10] as List<AttendanceRecord>;
        _staff              = results[11] as List<StaffMember>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _mon(DateTime d) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month - 1];

  String _compactMoney(num v) {
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    // A background refresh erroring while stale-but-valid cached data is
    // already showing shouldn't blow that away — only surface the error
    // screen when there's genuinely nothing to show.
    final hasAnyData = _headcount != null || _turnover != null || _leaveBalances.isNotEmpty ||
        _recruitment != null || _vacancies.isNotEmpty || _contractsExpiring.isNotEmpty ||
        _contractsSummary != null || _discipline != null || _careerLog.isNotEmpty ||
        _payrollRuns.isNotEmpty || _attendance.isNotEmpty || _staff.isNotEmpty;
    if (_error != null && !hasAnyData) return ErrorView(message: _error!, onRetry: _load);

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 1100;
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context),
            const SizedBox(height: 18),
            _kpiRow(context),
            const SizedBox(height: 14),
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 27, child: SizedBox(height: 280, child: _headcountTrendCard(context))),
                    const SizedBox(width: 14),
                    Expanded(flex: 20, child: SizedBox(height: 280, child: _leaveByTypeCard(context))),
                    const SizedBox(width: 14),
                    Expanded(flex: 20, child: SizedBox(height: 280, child: _contractsCard(context))),
                  ])
                : Column(children: [
                    SizedBox(height: 260, child: _headcountTrendCard(context)),
                    const SizedBox(height: 14),
                    SizedBox(height: 260, child: _leaveByTypeCard(context)),
                    const SizedBox(height: 14),
                    SizedBox(height: 260, child: _contractsCard(context)),
                  ]),
            const SizedBox(height: 14),
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 27, child: SizedBox(height: 300, child: _attendanceCard(context))),
                    const SizedBox(width: 14),
                    Expanded(flex: 20, child: SizedBox(height: 300, child: _funnelCard(context))),
                    const SizedBox(width: 14),
                    Expanded(flex: 20, child: SizedBox(height: 300, child: _disciplineCard(context))),
                  ])
                : Column(children: [
                    SizedBox(height: 280, child: _attendanceCard(context)),
                    const SizedBox(height: 14),
                    SizedBox(height: 280, child: _funnelCard(context)),
                    const SizedBox(height: 14),
                    SizedBox(height: 280, child: _disciplineCard(context)),
                  ]),
          ]),
        ),
      );
    });
  }

  Widget _header(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Container(width: 2, height: 32, decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('HR Reports', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
      const SizedBox(height: 3),
      Text('Staff, leave, recruitment, contracts, discipline and career analytics · ${DateTime.now().year}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ])),
    OutlinedButton.icon(
      onPressed: _exportingPdf ? null : _exportPdf,
      icon: _exportingPdf
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Symbols.picture_as_pdf, size: 15),
      label: const Text('Export PDF'),
    ),
  ]);

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    await downloadPdf(context, HrReportService.instance.exportPdfBytes, 'hr-report-${DateTime.now().year}.pdf');
    if (mounted) setState(() => _exportingPdf = false);
  }

  // ── KPI strip ────────────────────────────────────────────────────────────

  Widget _kpiRow(BuildContext context) {
    final currentYear = DateTime.now().year;
    final ytdRuns = _payrollRuns.where((r) => r.periodYear == currentYear).toList();
    final payrollYtd = ytdRuns.fold<int>(0, (a, r) => a + r.netTotal);
    final leaveUsed = _leaveBalances.fold<double>(0, (a, r) => a + r.usedDays);
    final leaveAllocated = _leaveBalances.fold<double>(0, (a, r) => a + r.allocatedDays);
    final leavePct = leaveAllocated == 0 ? 0.0 : leaveUsed / leaveAllocated * 100;
    final nearestExpiry = _contractsExpiring.isEmpty ? null : _contractsExpiring.first;

    final tiles = [
      _Kpi('Headcount', '${_headcount?.total ?? 0}', 'across ${_headcount?.byDepartment.length ?? 0} groups', context.pal.textMute, AppColors.cyan),
      _Kpi('Turnover', '${_turnover?.turnoverRate.toStringAsFixed(1) ?? '0.0'}%', '${_turnover?.year ?? currentYear}', (_turnover?.turnoverRate ?? 0) > 10 ? AppColors.coral : context.pal.textMute, AppColors.cyan),
      _Kpi('Leave used', '${leaveUsed.toStringAsFixed(0)} d', '${leavePct.toStringAsFixed(1)}% of pool', context.pal.textMute, AppColors.amber),
      _Kpi('Expiring', '${_contractsExpiring.length}', nearestExpiry == null ? 'none soon' : 'in ${nearestExpiry.daysRemaining}d', _contractsExpiring.isEmpty ? context.pal.textMute : AppColors.coral, AppColors.coral),
      _Kpi('Payroll YTD', _compactMoney(payrollYtd), '${ytdRuns.length} run${ytdRuns.length == 1 ? '' : 's'}', context.pal.textMute, AppColors.green),
      _Kpi('Open cases', '${_discipline?.activeCount ?? 0}', (_discipline?.activeCount ?? 0) == 0 ? 'clean' : 'active', (_discipline?.activeCount ?? 0) == 0 ? AppColors.green : AppColors.coral, AppColors.info),
    ];

    return LayoutBuilder(builder: (ctx, cst) {
      final perRow = cst.maxWidth >= 900 ? 6 : (cst.maxWidth >= 560 ? 3 : 2);
      final w = (cst.maxWidth - (perRow - 1) * 10) / perRow;
      return Wrap(spacing: 10, runSpacing: 10, children: tiles.map((k) => SizedBox(width: w, child: _kpiTile(context, k))).toList());
    });
  }

  Widget _kpiTile(BuildContext context, _Kpi k) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.pal.border),
    ),
    child: Stack(children: [
      Positioned(left: -14, top: -12, bottom: -12, child: Container(width: 2, color: k.accent)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.label, style: AppTheme.labelCaps.copyWith(fontSize: 10)),
        const SizedBox(height: 5),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(k.value, style: AppTheme.monoXs.copyWith(fontSize: 20, color: context.pal.text)),
          const SizedBox(width: 6),
          Flexible(child: Text(k.delta, style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: k.deltaColor), overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    ]),
  );

  Widget _cardShell(BuildContext context, {required IconData icon, required Color accent, required String title, String? trailing, required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5))),
        if (trailing != null) Text(trailing, style: AppTheme.monoXs.copyWith(color: context.pal.textDim, fontSize: 10)),
      ]),
      const SizedBox(height: 10),
      Expanded(child: child),
    ]),
  );

  // ── Headcount trend ──────────────────────────────────────────────────────

  Widget _headcountTrendCard(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(8, (i) => DateTime(now.year, now.month - 7 + i, 1));
    final points = months.map((m) {
      final end = DateTime(m.year, m.month + 1, 0);
      return _staff.where((s) => s.hireDate == null || !s.hireDate!.isAfter(end)).length;
    }).toList();
    final maxY = (points.isEmpty ? 1 : points.reduce((a, b) => a > b ? a : b)).toDouble();

    return _cardShell(context, icon: Symbols.groups, accent: AppColors.cyan, title: 'Headcount trend',
      trailing: '${_mon(months.first)} → ${_mon(months.last)} ${now.year}',
      child: LineChart(LineChartData(
        minX: 0, maxX: (points.length - 1).toDouble(),
        minY: 0, maxY: maxY + 1,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY + 1) / 3,
            getDrawingHorizontalLine: (_) => FlLine(color: context.pal.divider, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= months.length) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_mon(months[i]), style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim)));
          })),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].toDouble())),
            color: AppColors.cyan, barWidth: 2, isCurved: true, curveSmoothness: 0.2,
            dotData: FlDotData(show: true, getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
              radius: idx == points.length - 1 ? 3.5 : 2, color: AppColors.cyan, strokeColor: context.pal.surface1, strokeWidth: 1.5)),
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [AppColors.cyan.withValues(alpha: 0.16), AppColors.cyan.withValues(alpha: 0)])),
          ),
        ],
        lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => context.pal.surface2,
          getTooltipItems: (spots) => spots.map((s) => LineTooltipItem('${s.y.toInt()}', AppTheme.monoXs.copyWith(color: context.pal.text))).toList(),
        )),
      )),
    );
  }

  // ── Leave taken by type ──────────────────────────────────────────────────

  static Color _leaveColor(String label) => switch (label.toLowerCase()) {
    'sick' => const Color(0xFFD97706),
    'annual' => AppColors.amber,
    'maternity' => AppColors.violet,
    'compassionate' => AppColors.cyan,
    _ when label.toLowerCase().contains('holiday') => AppColors.info,
    _ => AppColors.teal,
  };

  Widget _leaveByTypeCard(BuildContext context) {
    final byType = <String, double>{};
    for (final r in _leaveBalances) { byType[r.leaveTypeLabel] = (byType[r.leaveTypeLabel] ?? 0) + r.usedDays; }
    final entries = byType.entries.toList();
    final maxV = entries.isEmpty ? 1.0 : entries.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);

    return _cardShell(context, icon: Symbols.event, accent: AppColors.amber, title: 'Leave taken by type',
      child: entries.isEmpty
          ? Center(child: Text('No leave taken yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: entries.map((e) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(e.value.toStringAsFixed(0), style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
                  const SizedBox(height: 6),
                  // Expanded is required here: a Column gives a direct
                  // (non-flex) child unbounded max height along the main
                  // axis, and FractionallySizedBox.heightFactor multiplies
                  // that straight through (factor * infinity = infinity),
                  // which crashes downstream in RenderDecoratedBox. Expanded
                  // gives it the Column's actual remaining bounded height.
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (maxV == 0 ? 0.0 : e.value / maxV).clamp(0.04, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(decoration: BoxDecoration(color: _leaveColor(e.key), borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(e.key, style: AppTheme.bodySub.copyWith(fontSize: 9.5), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            )).toList()),
    );
  }

  // ── Contracts ────────────────────────────────────────────────────────────

  Widget _contractsCard(BuildContext context) {
    final byType = _contractsSummary?.byType ?? const {};
    final total = _contractsSummary?.activeCount ?? 0;
    final permanent = byType['permanent'] ?? 0;
    final fixedTerm = byType['fixed_term'] ?? 0;
    final nearest = _contractsExpiring.isEmpty ? null : _contractsExpiring.first;

    final sections = <PieChartSectionData>[
      if (permanent > 0) PieChartSectionData(value: permanent.toDouble(), color: AppColors.green, radius: 13, showTitle: false),
      if (fixedTerm > 0) PieChartSectionData(value: fixedTerm.toDouble(), color: AppColors.coral, radius: 13, showTitle: false),
      if (total > 0 && permanent + fixedTerm < total) PieChartSectionData(value: (total - permanent - fixedTerm).toDouble(), color: context.pal.surface3, radius: 13, showTitle: false),
    ];

    return _cardShell(context, icon: Symbols.description, accent: AppColors.coral, title: 'Contracts',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 72, height: 72, child: Stack(alignment: Alignment.center, children: [
            if (sections.isNotEmpty) PieChart(PieChartData(sections: sections, centerSpaceRadius: 24, sectionsSpace: 2, startDegreeOffset: -90, pieTouchData: PieTouchData(enabled: false))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$total', style: AppTheme.monoXs.copyWith(fontSize: 16, color: context.pal.text)),
              Text('active', style: AppTheme.bodySub.copyWith(fontSize: 8.5)),
            ]),
          ])),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _legendRow(context, 'Permanent', permanent, AppColors.green),
            const SizedBox(height: 6),
            _legendRow(context, 'Fixed term', fixedTerm, AppColors.coral),
          ])),
        ]),
        const SizedBox(height: 12),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 10),
        Text('EXPIRING NEXT 90 DAYS', style: AppTheme.labelCaps.copyWith(fontSize: 9)),
        const SizedBox(height: 8),
        Expanded(child: nearest == null
            ? Center(child: Text('Nothing expiring soon.', style: AppTheme.bodySub.copyWith(fontSize: 11.5)))
            : Row(children: [
                Container(width: 3, height: 22, decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${nearest.userName} — ${nearest.contractType}', style: AppTheme.bodySm.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis),
                  Text(nearest.endDate, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                  child: Text('${nearest.daysRemaining}d', style: AppTheme.monoXs.copyWith(color: AppColors.coral, fontSize: 10)),
                ),
              ])),
      ]),
    );
  }

  Widget _legendRow(BuildContext context, String label, int n, Color color) => Row(children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11))),
    Text('$n', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
  ]);

  // ── Attendance by month ──────────────────────────────────────────────────

  Widget _attendanceCard(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
    final buckets = { for (final m in months) '${m.year}-${m.month}': _AttBucket() };
    for (final r in _attendance) {
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      final key = '${d.year}-${d.month}';
      final b = buckets[key];
      if (b == null) continue;
      switch (r.status) {
        case 'absent': b.absent++; break;
        case 'late': b.late++; break;
        default: b.present++;
      }
    }
    final maxTotal = buckets.values.map((b) => b.total).fold(1, (a, b) => a > b ? a : b);

    return _cardShell(context, icon: Symbols.fingerprint, accent: AppColors.cyan, title: 'Attendance by month',
      child: buckets.values.every((b) => b.total == 0)
          ? Center(child: Text('No attendance marked in this window.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: months.map((m) {
              final b = buckets['${m.year}-${m.month}']!;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (b.absent > 0) Expanded(flex: b.absent, child: Container(width: double.infinity, decoration: const BoxDecoration(color: Color(0xFFF04438), borderRadius: BorderRadius.vertical(top: Radius.circular(3))))),
                    if (b.late > 0) Container(height: (b.late / maxTotal * 130).clamp(3, 130).toDouble(), width: double.infinity, color: AppColors.amber),
                    if (b.present > 0) Expanded(flex: b.present, child: Container(width: double.infinity, decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.85), borderRadius: b.absent == 0 && b.late == 0 ? BorderRadius.circular(3) : const BorderRadius.vertical(bottom: Radius.circular(3))))),
                    if (b.total == 0) Container(height: 3, width: double.infinity, color: context.pal.surface3),
                  ])),
                  const SizedBox(height: 6),
                  Text(_mon(m), style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim)),
                ]),
              ));
            }).toList()),
    );
  }

  // ── Hiring funnel ────────────────────────────────────────────────────────

  Widget _funnelCard(BuildContext context) {
    final agg = <String, int>{};
    for (final p in _recruitment?.pipeline ?? const <VacancyPipelineEntry>[]) {
      p.byStage.forEach((k, v) => agg[k] = (agg[k] ?? 0) + v);
    }
    const stageOrder = ['applied', 'shortlisted', 'interviewed', 'offered', 'hired'];
    final maxV = agg.values.isEmpty ? 1 : agg.values.reduce((a, b) => a > b ? a : b);

    final closedWithDates = _vacancies.where((v) => v.status == 'closed' && v.closedAt != null).toList();
    int? avgDays;
    if (closedWithDates.isNotEmpty) {
      final total = closedWithDates.fold<int>(0, (a, v) {
        final open = DateTime.tryParse(v.openedAt);
        final closed = DateTime.tryParse(v.closedAt!);
        if (open == null || closed == null) return a;
        return a + closed.difference(open).inDays;
      });
      avgDays = (total / closedWithDates.length).round();
    }
    final hires = (_recruitment?.hiresBySource ?? const {}).values.fold<int>(0, (a, b) => a + b);
    String topSource = '—';
    var topN = 0;
    (_recruitment?.hiresBySource ?? const {}).forEach((k, v) { if (v > topN) { topN = v; topSource = k; } });

    return _cardShell(context, icon: Symbols.person_search, accent: AppColors.violet, title: 'Hiring funnel',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: agg.isEmpty
            ? Center(child: Text('No open pipeline right now.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final s in stageOrder) if (agg.containsKey(s)) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 74, child: Text(s[0].toUpperCase() + s.substring(1), style: AppTheme.bodySub.copyWith(fontSize: 10.5))),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(
                      value: (agg[s]! / maxV).clamp(0.03, 1.0), minHeight: 14, backgroundColor: context.pal.surface2,
                      valueColor: AlwaysStoppedAnimation(AppColors.violet.withValues(alpha: 0.5 + 0.5 * (agg[s]! / maxV))),
                    ))),
                    const SizedBox(width: 8),
                    SizedBox(width: 16, child: Text('${agg[s]}', style: AppTheme.monoXs.copyWith(fontSize: 11), textAlign: TextAlign.right)),
                  ]),
                ),
              ])),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 10),
        Row(children: [
          _statBlock(context, 'Hires', '$hires'),
          const SizedBox(width: 18),
          _statBlock(context, 'Avg time to fill', avgDays == null ? '—' : '${avgDays}d'),
          const SizedBox(width: 18),
          Expanded(child: _statBlock(context, 'Top source', topSource)),
        ]),
      ]),
    );
  }

  Widget _statBlock(BuildContext context, String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 8.5)),
    const SizedBox(height: 3),
    Text(value, style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
  ]);

  // ── Discipline & progression ─────────────────────────────────────────────

  Widget _disciplineCard(BuildContext context) {
    final byStage = _discipline?.byStage ?? const {};
    const stageOrder = ['verbal_warning', 'written_warning', 'final_warning', 'action_taken'];
    const stageLabels = {'verbal_warning': 'Verbal warning', 'written_warning': 'Written warning', 'final_warning': 'Final warning', 'action_taken': 'Action taken'};
    final maxV = byStage.values.isEmpty ? 1 : byStage.values.reduce((a, b) => a > b ? a : b);

    final recentChanges = [..._careerLog]..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    final recent = recentChanges.isEmpty ? null : recentChanges.first;

    return _cardShell(context, icon: Symbols.gavel, accent: AppColors.info, title: 'Discipline & progression',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in stageOrder) Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 92, child: Text(stageLabels[s]!, style: AppTheme.bodySub.copyWith(fontSize: 10.5))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
              value: (((byStage[s] ?? 0) / maxV)).clamp(0.02, 1.0), minHeight: 6, backgroundColor: context.pal.surface2,
              valueColor: const AlwaysStoppedAnimation(AppColors.info),
            ))),
            const SizedBox(width: 8),
            SizedBox(width: 14, child: Text('${byStage[s] ?? 0}', style: AppTheme.monoXs.copyWith(fontSize: 10.5), textAlign: TextAlign.right)),
          ]),
        ),
        const Spacer(),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 10),
        Text('PROMOTIONS / DEMOTIONS', style: AppTheme.labelCaps.copyWith(fontSize: 9)),
        const SizedBox(height: 8),
        if (recent == null) Text('None recorded yet.', style: AppTheme.bodySub.copyWith(fontSize: 11.5))
        else Row(children: [
          Icon(recent.changeType == 'promotion' ? Symbols.arrow_upward : recent.changeType == 'demotion' ? Symbols.arrow_downward : Symbols.arrow_forward,
              size: 14, color: recent.changeType == 'promotion' ? AppColors.green : recent.changeType == 'demotion' ? AppColors.coral : AppColors.info),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(recent.userName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 11.5)),
            Text('${recent.fromPosition ?? '—'} → ${recent.toPosition ?? '—'}', style: AppTheme.bodySub.copyWith(fontSize: 10, color: context.pal.textDim)),
          ])),
          Text(recent.effectiveDate, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim)),
        ]),
      ]),
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, this.delta, this.deltaColor, this.accent);
  final String label;
  final String value;
  final String delta;
  final Color deltaColor;
  final Color accent;
}

class _AttBucket {
  int present = 0;
  int late = 0;
  int absent = 0;
  int get total => present + late + absent;
}
