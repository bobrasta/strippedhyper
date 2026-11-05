import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/attendance_service.dart';
import '../../services/hr_report_service.dart';
import '../../services/payroll_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../theme/hr_category_colors.dart';
import '../../widgets/common/error_view.dart';

/// HR's landing page — "Domain pulse": six category tiles up top, an
/// activity stream assembled from real cross-module events, attendance and
/// recruitment on the rail. Ported from the HR Redesign spec (1b) — flat
/// sections instead of cards-in-cards, one hue per [HrCategory] throughout,
/// status colors (green/amber/red) reserved for status only.
class HrDashboardScreen extends StatefulWidget {
  const HrDashboardScreen({super.key});

  @override
  State<HrDashboardScreen> createState() => _HrDashboardScreenState();
}

class _ActivityItem {
  const _ActivityItem({required this.color, required this.icon, required this.title, required this.sub, required this.when, this.badge});
  final Color color;
  final IconData icon;
  final String title;
  final String sub;
  final String? badge;
  final DateTime when;
}

class _HrDashboardScreenState extends State<HrDashboardScreen> {
  bool _loading = true;
  String? _error;

  HeadcountBreakdown? _headcount;
  RecruitmentSummary? _recruitment;
  List<ContractExpiringEntry> _expiring = [];
  List<HrLeaveBalanceRow> _leaveBalances = [];
  DisciplinarySummary? _discipline;
  List<CareerProgressionEntry> _career = [];
  List<LeaveCalendarEntry> _leaveCalendar = [];
  List<PayrollRun> _payrollRuns = [];
  List<AttendanceRecord> _attendance = [];
  List<StaffMember> _staff = [];

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning. This dashboard combines 10 independent pieces, so
    // "loading" is only true when NONE of them have anything cached yet.
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 25));
    final calendarKey = '${_fmt(now.subtract(const Duration(days: 30)))}|${_fmt(now)}';
    final attendanceKey = '${_fmt(start)}|${_fmt(now)}|';
    final cachedHeadcount   = HrReportService.cachedHeadcount;
    final cachedRecruitment = HrReportService.cachedRecruitmentSummary;
    final cachedExpiring    = HrReportService.cachedContractsExpiringByDays[90];
    final cachedBalances    = HrReportService.cachedDefaultLeaveBalances;
    final cachedDiscipline  = HrReportService.cachedDisciplinarySummary;
    final cachedCareer      = HrReportService.cachedCareerProgressions;
    final cachedCalendar    = HrReportService.cachedLeaveCalendarByRange[calendarKey];
    final cachedRuns        = PayrollService.cachedRuns;
    final cachedAttendance  = AttendanceService.cachedByQuery[attendanceKey];
    final cachedStaff       = StaffService.instance.staffNotifier.value;
    if (cachedHeadcount != null) _headcount = cachedHeadcount;
    if (cachedRecruitment != null) _recruitment = cachedRecruitment;
    if (cachedExpiring != null) _expiring = cachedExpiring;
    if (cachedBalances != null) _leaveBalances = cachedBalances;
    if (cachedDiscipline != null) _discipline = cachedDiscipline;
    if (cachedCareer != null) _career = cachedCareer;
    if (cachedCalendar != null) _leaveCalendar = cachedCalendar;
    if (cachedRuns != null) _payrollRuns = cachedRuns;
    if (cachedAttendance != null) _attendance = cachedAttendance;
    if (cachedStaff.isNotEmpty) _staff = cachedStaff;
    if (cachedHeadcount != null || cachedRecruitment != null || cachedExpiring != null ||
        cachedBalances != null || cachedDiscipline != null || cachedCareer != null ||
        cachedCalendar != null || cachedRuns != null || cachedAttendance != null || cachedStaff.isNotEmpty) {
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_headcount == null && _recruitment == null && _expiring.isEmpty && _leaveBalances.isEmpty &&
          _discipline == null && _career.isEmpty && _leaveCalendar.isEmpty && _payrollRuns.isEmpty &&
          _attendance.isEmpty && _staff.isEmpty) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 25));
      final results = await Future.wait([
        HrReportService.instance.headcount(),
        HrReportService.instance.recruitmentSummary(),
        HrReportService.instance.contractsExpiring(withinDays: 90),
        HrReportService.instance.leaveBalances(),
        HrReportService.instance.disciplinarySummary(),
        HrReportService.instance.careerProgressions(),
        HrReportService.instance.leaveCalendar(start: _fmt(now.subtract(const Duration(days: 30))), end: _fmt(now)),
        PayrollService.instance.runs(),
        AttendanceService.instance.list(start: _fmt(start), end: _fmt(now)),
        StaffService.instance.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _headcount     = results[0] as HeadcountBreakdown;
        _recruitment   = results[1] as RecruitmentSummary;
        _expiring      = results[2] as List<ContractExpiringEntry>;
        _leaveBalances = results[3] as List<HrLeaveBalanceRow>;
        _discipline    = results[4] as DisciplinarySummary;
        _career        = results[5] as List<CareerProgressionEntry>;
        _leaveCalendar = results[6] as List<LeaveCalendarEntry>;
        _payrollRuns   = results[7] as List<PayrollRun>;
        _attendance    = results[8] as List<AttendanceRecord>;
        _staff         = results[9] as List<StaffMember>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    // A background refresh erroring while stale-but-valid cached data is
    // already showing shouldn't blow that away — only surface the error
    // screen when there's genuinely nothing to show.
    final hasAnyData = _headcount != null || _recruitment != null || _expiring.isNotEmpty ||
        _leaveBalances.isNotEmpty || _discipline != null || _career.isNotEmpty ||
        _leaveCalendar.isNotEmpty || _payrollRuns.isNotEmpty || _attendance.isNotEmpty || _staff.isNotEmpty;
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
            const SizedBox(height: 4),
            Container(width: double.infinity, height: 1, color: context.pal.divider),
            const SizedBox(height: 18),
            _tileGrid(wide),
            const SizedBox(height: 18),
            if (wide)
              IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _activityStream()),
                const SizedBox(width: 18),
                SizedBox(width: 420, child: Column(children: [
                  _attendanceCard(),
                  const SizedBox(height: 14),
                  _funnelCard(),
                ])),
              ]))
            else Column(children: [
              _activityStream(),
              const SizedBox(height: 14),
              _attendanceCard(),
              const SizedBox(height: 14),
              _funnelCard(),
            ]),
          ]),
        ),
      );
    });
  }

  Widget _header(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 13),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('HR Dashboard', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
      const SizedBox(height: 3),
      Text('Six domains, one page', style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ])),
  ]);

  Widget _tileGrid(bool wide) {
    final leaveUsed = _leaveBalances.fold<double>(0, (a, b) => a + b.usedDays);
    final leaveAllocated = _leaveBalances.fold<double>(0, (a, b) => a + b.allocatedDays);
    final leavePct = leaveAllocated == 0 ? 0.0 : leaveUsed / leaveAllocated * 100;
    final latestPaidRun = _payrollRuns.where((r) => r.status == 'paid').isNotEmpty
        ? _payrollRuns.where((r) => r.status == 'paid').first : null;
    final applicantsWaiting = _recruitment?.pipeline.fold<int>(0, (a, p) => a + p.totalApplications) ?? 0;
    final hiredThisYear = _staff.where((s) => s.hireDate != null && s.hireDate!.year == DateTime.now().year).length;
    final nearestExpiry = _expiring.isEmpty ? null : _expiring.first;
    final openVacancies = _recruitment?.openVacancies ?? 0;
    final activeCases = _discipline?.activeCount ?? 0;

    final tiles = <_DomainTileData>[
      _DomainTileData(category: HrCategory.people, n: '${_headcount?.total ?? 0}', unit: 'staff',
          delta: hiredThisYear > 0 ? '+$hiredThisYear this year' : 'no new hires this year', deltaGood: true),
      _DomainTileData(category: HrCategory.leave, n: leaveUsed.toStringAsFixed(0), unit: 'days used',
          delta: '${leavePct.toStringAsFixed(1)}% of pool', deltaGood: leavePct < 70),
      _DomainTileData(category: HrCategory.contracts, n: '${_expiring.length}', unit: 'expiring',
          delta: nearestExpiry == null ? 'none soon' : 'in ${nearestExpiry.daysRemaining}d', deltaGood: nearestExpiry == null),
      _DomainTileData(category: HrCategory.payroll, n: latestPaidRun != null ? _millions(latestPaidRun.netTotal) : '—', unit: 'net TZS',
          delta: latestPaidRun != null ? '${_monthName(latestPaidRun.periodMonth)} ${latestPaidRun.periodYear} paid' : 'no runs paid', deltaGood: latestPaidRun != null),
      _DomainTileData(category: HrCategory.recruitment, n: '$applicantsWaiting', unit: 'applicants',
          delta: '$openVacancies open role${openVacancies == 1 ? '' : 's'}', deltaGood: true),
      _DomainTileData(category: HrCategory.discipline, n: '$activeCases', unit: 'open cases',
          delta: activeCases == 0 ? 'clean' : 'needs review', deltaGood: activeCases == 0),
    ];

    // Phones: two tiles to a row at a fixed height (three columns made
    // each tile ~110 px wide, too short for its figure and note).
    return LayoutBuilder(builder: (context, cst) => cst.maxWidth < 600
        ? GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 112),
            children: tiles.map((t) => _DomainTile(data: t)).toList(),
          )
        : GridView.count(
            crossAxisCount: wide ? 6 : 3,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: wide ? 1.9 : 1.55,
            physics: const NeverScrollableScrollPhysics(),
            children: tiles.map((t) => _DomainTile(data: t)).toList(),
          ));
  }

  static String _millions(int v) => (v / 1000000).toStringAsFixed(1);

  Widget _activityStream() {
    final items = _buildActivity();
    return _RailSection(
      icon: Symbols.timeline, iconColor: AppColors.cyan, title: 'Activity stream', trailingLabel: 'All domains',
      child: items.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Nothing recent.', style: AppTheme.bodySub)))
          : Column(children: items.map((a) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                Container(
                  width: 26, height: 26, alignment: Alignment.center,
                  decoration: BoxDecoration(color: a.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                  child: Icon(a.icon, size: 13, color: a.color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text(a.sub, style: AppTheme.monoXs.copyWith(fontSize: 11)),
                ])),
                if (a.badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: a.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                    child: Text(a.badge!, style: AppTheme.monoXs.copyWith(color: a.color, fontSize: 10.5)),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(width: 62, child: Text(_ago(a.when), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim))),
              ]),
            )).toList()),
    );
  }

  List<_ActivityItem> _buildActivity() {
    final items = <_ActivityItem>[];
    for (final c in _career.take(4)) {
      final d = DateTime.tryParse(c.effectiveDate);
      if (d == null) continue;
      items.add(_ActivityItem(
        color: AppColors.cyan, icon: Symbols.trending_up,
        title: '${c.userName ?? '—'} ${c.changeType}d',
        sub: '${c.fromPosition ?? '—'} → ${c.toPosition ?? '—'}',
        badge: c.changeType, when: d,
      ));
    }
    for (final r in _payrollRuns.where((r) => r.status == 'paid').take(2)) {
      final d = DateTime.tryParse(r.paidAt ?? '');
      if (d == null) continue;
      items.add(_ActivityItem(
        color: AppColors.green, icon: Symbols.payments,
        title: '${_monthName(r.periodMonth)} ${r.periodYear} payroll run marked paid',
        sub: 'net ${_millions(r.netTotal)}M TZS · ${r.itemsCount ?? 0} items',
        badge: 'paid', when: d,
      ));
    }
    for (final e in _leaveCalendar.take(4)) {
      final d = DateTime.tryParse(e.startDate);
      if (d == null) continue;
      items.add(_ActivityItem(
        color: AppColors.amber, icon: Symbols.event_available,
        title: '${e.leaveTypeLabel} approved — ${e.userName}',
        sub: '${e.startDate} → ${e.endDate}',
        badge: 'approved', when: d,
      ));
    }
    for (final c in _expiring.take(2)) {
      items.add(_ActivityItem(
        color: AppColors.coral, icon: Symbols.description,
        title: '${c.userName} — ${c.contractType} contract expiry alert',
        sub: 'ends ${c.endDate}',
        badge: 'action', when: DateTime.now().subtract(Duration(days: 90 - c.daysRemaining)),
      ));
    }
    items.sort((a, b) => b.when.compareTo(a.when));
    return items.take(9).toList();
  }

  static const _months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _monthName(int m) => _months[m];

  static String _ago(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'just now';
  }

  Widget _attendanceCard() {
    final names = _staff.take(7).toList();
    final byUser = <int, Map<String, String>>{};
    for (final r in _attendance) {
      byUser.putIfAbsent(r.userId, () => {})[r.date] = r.status;
    }
    final days = List.generate(26, (i) => DateTime.now().subtract(Duration(days: 25 - i)));

    return _RailSection(
      icon: Symbols.fingerprint, iconColor: AppColors.cyan, title: 'Attendance · last 26 days',
      child: Column(children: [
        ...names.map((s) {
          final rec = byUser[s.id] ?? {};
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.5),
            child: Row(children: [
              SizedBox(width: 84, child: Text(s.name, style: AppTheme.monoXs.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
              Expanded(child: Row(children: days.map((d) {
                final status = rec[_fmt(d)];
                final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
                final color = switch (status) {
                  'absent' => AppColors.coral, 'late' => AppColors.amber, 'leave' => AppColors.amber,
                  'present' || 'half_day' => const Color(0xFF17301F),
                  _ => weekend ? const Color(0xFF14171C) : const Color(0xFF1B1F27),
                };
                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                ));
              }).toList())),
            ]),
          );
        }),
        const SizedBox(height: 13),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 8, children: [
          _legendDot(const Color(0xFF17301F), 'Present'),
          _legendDot(AppColors.amber, 'Late/Leave'),
          _legendDot(AppColors.coral, 'Absent'),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(label, style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
  ]);

  Widget _funnelCard() {
    final totals = <String, int>{};
    for (final p in _recruitment?.pipeline ?? <VacancyPipelineEntry>[]) {
      p.byStage.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v);
    }
    final stages = ['applied', 'shortlisted', 'interviewed', 'offered', 'hired', 'rejected'];
    final labels = {'applied': 'Applied', 'shortlisted': 'Shortlisted', 'interviewed': 'Interviewed', 'offered': 'Offered', 'hired': 'Hired', 'rejected': 'Rejected'};
    final maxN = totals.values.fold(0, (a, b) => a > b ? a : b);

    return _RailSection(
      icon: Symbols.person_search, iconColor: AppColors.violet, title: 'Recruitment funnel',
      child: (_recruitment?.pipeline.isEmpty ?? true)
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No open vacancies.', style: AppTheme.bodySub)))
          : Column(children: stages.map((s) {
              final n = totals[s] ?? 0;
              final pct = maxN > 0 ? (n / maxN).clamp(0.03, 1.0) : 0.03;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  SizedBox(width: 88, child: Text(labels[s]!, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
                  const SizedBox(width: 4),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(children: [
                      Container(width: double.infinity, height: 22, color: context.pal.surface3),
                      FractionallySizedBox(widthFactor: pct, child: Container(width: double.infinity, height: 22, color: AppColors.violet)),
                    ]),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(width: 24, child: Text('$n', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 12, color: context.pal.text))),
                ]),
              );
            }).toList()),
    );
  }
}

class _DomainTileData {
  const _DomainTileData({required this.category, required this.n, required this.unit, required this.delta, required this.deltaGood});
  final HrCategory category;
  final String n;
  final String unit;
  final String delta;
  final bool deltaGood;
}

class _DomainTile extends StatelessWidget {
  const _DomainTile({required this.data});
  final _DomainTileData data;

  @override
  Widget build(BuildContext context) {
    final color = data.category.color;
    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, width: 2, child: Container(color: color)),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(data.category.icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(data.category.label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(data.n, style: AppTheme.kpiValue.copyWith(fontSize: 24)),
              const SizedBox(width: 5),
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(data.unit, style: AppTheme.monoXs.copyWith(fontSize: 10))),
            ]),
            const SizedBox(height: 6),
            Text(data.delta, style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: data.deltaGood ? AppColors.green : AppColors.amber),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

/// Shared rail-section shell — icon + uppercase title + divider header,
/// bordered flat body below. Used for Activity/Attendance/Funnel cards.
class _RailSection extends StatelessWidget {
  const _RailSection({required this.icon, required this.iconColor, required this.title, required this.child, this.trailingLabel});
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? trailingLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(icon, size: 13, color: iconColor),
      const SizedBox(width: 8),
      Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
      const SizedBox(width: 8),
      Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      if (trailingLabel != null) ...[
        const SizedBox(width: 8),
        Text(trailingLabel!, style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
      ],
    ]),
    const SizedBox(height: 9),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: child,
    ),
  ]);
}
