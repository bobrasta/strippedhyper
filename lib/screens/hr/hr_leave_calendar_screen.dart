import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/hr_report_service.dart';
import '../../services/public_holiday_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';

/// Company-wide leave calendar — ported from HR Redesign spec 1e. Distinct
/// from "My Leave" (personal self-service, stays in Operations).
class HrLeaveCalendarScreen extends StatefulWidget {
  const HrLeaveCalendarScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<HrLeaveCalendarScreen> createState() => _HrLeaveCalendarScreenState();
}

class _HrLeaveCalendarScreenState extends State<HrLeaveCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<LeaveCalendarEntry> _entries = [];
  List<PublicHoliday> _holidays = [];
  List<HrLeaveBalanceRow> _balances = [];
  bool _loading = true;
  String? _error;
  LeaveCalendarEntry? _selected;

  static List<Color> get _lanePalette => [AppColors.amber, AppColors.violet, AppColors.cyan, AppColors.info, AppColors.coral];

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: seed from whatever's already cached for the
    // current month (the default landing view) so this screen doesn't
    // blank to a spinner on every navigation — see MachineService's own
    // doc comment for the full reasoning. Scoped to the current month only;
    // paging to a different month still shows the normal loading state.
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 0);
    final cachedEntries = HrReportService.cachedLeaveCalendarByRange['${_fmt(start)}|${_fmt(end)}'];
    final cachedHolidays = PublicHolidayService.cachedByYear[_month.year];
    final cachedBalances = HrReportService.cachedLeaveBalancesByYear[_month.year];
    if (cachedEntries != null) _entries = cachedEntries;
    if (cachedHolidays != null) {
      _holidays = cachedHolidays.where((h) {
        final d = DateTime.tryParse(h.date);
        return d != null && !d.isBefore(DateTime.now());
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
    }
    if (cachedBalances != null) _balances = cachedBalances;
    if (cachedEntries != null || cachedHolidays != null || cachedBalances != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_entries.isEmpty && _holidays.isEmpty && _balances.isEmpty) _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0);
      final results = await Future.wait([
        HrReportService.instance.leaveCalendar(start: _fmt(start), end: _fmt(end)),
        PublicHolidayService.instance.list(year: _month.year),
        HrReportService.instance.leaveBalances(year: _month.year),
      ]);
      if (mounted) setState(() {
        _entries = results[0] as List<LeaveCalendarEntry>;
        _holidays = (results[1] as List<PublicHoliday>).where((h) {
          final d = DateTime.tryParse(h.date);
          return d != null && !d.isBefore(DateTime.now());
        }).toList()..sort((a, b) => a.date.compareTo(b.date));
        _balances = results[2] as List<HrLeaveBalanceRow>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Map<LeaveCalendarEntry, int> _assignLanes(List<_ParsedEntry> parsed) {
    final sorted = [...parsed]..sort((a, b) => a.start.compareTo(b.start));
    final laneEnds = <DateTime>[];
    final lanes = <LeaveCalendarEntry, int>{};
    for (final p in sorted) {
      var lane = laneEnds.indexWhere((end) => end.isBefore(p.start));
      if (lane == -1) { lane = laneEnds.length; laneEnds.add(p.end); } else { laneEnds[lane] = p.end; }
      lanes[p.entry] = lane;
    }
    return lanes;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 900;
      return Padding(
        padding: EdgeInsets.all(pad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context),
          const SizedBox(height: 4),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_error != null && _entries.isEmpty && _holidays.isEmpty && _balances.isEmpty)
                    ? ErrorView(message: _error!, onRetry: _load)
                    : SingleChildScrollView(child: wide
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 7, child: _calendarGrid(context)),
                            const SizedBox(width: 18),
                            Expanded(flex: 5, child: _rail(context)),
                          ])
                        : Column(children: [_calendarGrid(context), const SizedBox(height: 16), _rail(context)])),
          ),
        ]),
      );
    });
  }

  Widget _header(BuildContext context) {
    final outThisMonth = _entries.length;
    return TitleWithActions(
      leading: Container(width: 2, height: 32, decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2))),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Leave Calendar', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
        const SizedBox(height: 3),
        Text('Approved leave across the team · $outThisMonth ${outThisMonth == 1 ? 'person' : 'people'} out this month', style: AppTheme.bodySub.copyWith(fontSize: 12)),
      ]),
      actions: [
        _MonthSwitcher(month: _month, onPrev: () => _changeMonth(-1), onNext: () => _changeMonth(1)),
        OutlinedButton.icon(
          onPressed: () => widget.onNavigateTo != null
              ? widget.onNavigateTo!('my_leave')
              : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use My Leave (Operations) to submit a request.'))),
          icon: const Icon(Symbols.add, size: 15), label: const Text('Request leave'),
        ),
      ],
    );
  }

  Widget _calendarGrid(BuildContext context) {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leadingOffset = (firstOfMonth.weekday - DateTime.monday) % 7;
    final gridStart = firstOfMonth.subtract(Duration(days: leadingOffset));
    final days = List.generate(42, (i) => gridStart.add(Duration(days: i)));
    final holidayDates = _holidays.map((h) => h.date).toSet();

    final parsed = _entries.map((e) {
      final s = DateTime.tryParse(e.startDate) ?? firstOfMonth;
      final en = DateTime.tryParse(e.endDate) ?? s;
      return _ParsedEntry(entry: e, start: s, end: en);
    }).toList();
    final lanes = _assignLanes(parsed);

    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.pal.border)),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .map((d) => Expanded(child: Padding(padding: EdgeInsets.only(left: 3), child: Text(d, style: AppTheme.labelCaps))))
            .toList()),
        const SizedBox(height: 8),
        for (var w = 0; w < 6; w++) ...[
          _weekRow(context, days.sublist(w * 7, w * 7 + 7), parsed, lanes, holidayDates),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  Widget _weekRow(BuildContext context, List<DateTime> weekDays, List<_ParsedEntry> parsed, Map<LeaveCalendarEntry, int> lanes, Set<String> holidayDates) {
    final weekStart = weekDays.first;
    final weekEnd = weekDays.last;
    final overlapping = parsed.where((p) => !p.end.isBefore(weekStart) && !p.start.isAfter(weekEnd)).toList();
    final maxLane = overlapping.isEmpty ? 0 : overlapping.map((p) => lanes[p.entry]!).reduce((a, b) => a > b ? a : b);
    final barsHeight = (maxLane + 1) * 20.0;

    return LayoutBuilder(builder: (ctx, cst) {
      final colW = cst.maxWidth / 7;
      return SizedBox(
        height: 30 + barsHeight + 6,
        child: Stack(children: [
          Row(children: weekDays.map((d) {
            final inMonth = d.month == _month.month;
            final isWeekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
            final isToday = _sameDay(d, DateTime.now());
            final isHoliday = holidayDates.contains(_fmt(d));
            return Expanded(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.only(top: 4, left: 6),
              decoration: BoxDecoration(
                color: inMonth ? (isWeekend ? context.pal.surface3.withValues(alpha: 0.4) : context.pal.surface2) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: isToday ? Border.all(color: AppColors.cyan.withValues(alpha: 0.6)) : null,
              ),
              child: Row(children: [
                Text('${d.day}', style: AppTheme.monoXs.copyWith(
                  fontSize: 11.5,
                  color: !inMonth ? context.pal.textDim.withValues(alpha: 0.4) : isToday ? AppColors.cyan : isWeekend ? context.pal.textDim : context.pal.text,
                )),
                if (isHoliday) ...[
                  const SizedBox(width: 4),
                  Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle)),
                ],
              ]),
            ));
          }).toList()),
          for (final p in overlapping)
            Positioned(
              top: 26 + lanes[p.entry]! * 20.0,
              left: (p.start.isBefore(weekStart) ? 0 : weekDays.indexWhere((d) => _sameDay(d, p.start))) * colW + 2,
              width: ((p.end.isAfter(weekEnd) ? 6 : weekDays.indexWhere((d) => _sameDay(d, p.end))) -
                      (p.start.isBefore(weekStart) ? 0 : weekDays.indexWhere((d) => _sameDay(d, p.start))) + 1) * colW - 4,
              height: 17,
              child: GestureDetector(
                onTap: () => setState(() => _selected = p.entry),
                child: Container(
                  decoration: BoxDecoration(
                    color: _lanePalette[lanes[p.entry]! % _lanePalette.length].withValues(alpha: _selected == p.entry ? 1 : 0.85),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  child: Text('${p.entry.userName} · ${p.entry.leaveTypeLabel}',
                      overflow: TextOverflow.ellipsis, maxLines: 1,
                      style: AppTheme.monoXs.copyWith(color: const Color(0xFF08090B), fontSize: 9.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ]),
      );
    });
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _rail(BuildContext context) {
    final byType = <String, double>{};
    for (final b in _balances) { byType[b.leaveTypeLabel] = (byType[b.leaveTypeLabel] ?? 0) + b.usedDays; }
    final typeColors = <String, Color>{'Annual': AppColors.amber, 'Sick': AppColors.coral, 'Maternity': AppColors.violet, 'Compassionate': AppColors.cyan};

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_selected != null) ...[_detailCard(_selected!), const SizedBox(height: 16)],
      _railHeader('Out this month', count: '${_entries.length}', color: AppColors.amber),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: _entries.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Nobody out.', style: AppTheme.bodySub.copyWith(fontSize: 12))))
            : Column(children: _entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(e.userName, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                    Text('${e.startDate} → ${e.endDate}', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
                    child: Text(e.leaveTypeLabel, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: AppColors.amber)),
                  ),
                ]),
              )).toList()),
      ),
      const SizedBox(height: 18),
      _railHeader('Leave types', color: AppColors.violet),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: byType.isEmpty
            ? Text('No leave taken yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
            : Column(children: byType.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: typeColors[e.key] ?? context.pal.textDim, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 9),
                  Expanded(child: Text(e.key, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
                  Text('${e.value.toStringAsFixed(0)} d', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
                ]),
              )).toList()),
      ),
      const SizedBox(height: 18),
      _railHeader('Public holidays', color: AppColors.info),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: _holidays.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('None remaining this year.', style: AppTheme.bodySub.copyWith(fontSize: 12))))
            : Column(children: _holidays.take(6).map((h) => Container(
                height: 34,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
                child: Row(children: [
                  Icon(Symbols.event, size: 13, color: AppColors.info),
                  const SizedBox(width: 9),
                  Expanded(child: Text(h.name, style: AppTheme.bodySm.copyWith(fontSize: 12))),
                  Text(h.date, style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
                ]),
              )).toList()),
      ),
    ]);
  }

  Widget _railHeader(String title, {String? count, required Color color}) => Row(children: [
    Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
    if (count != null) ...[const SizedBox(width: 6), Text(count, style: AppTheme.monoXs.copyWith(fontSize: 11, color: color))],
    const SizedBox(width: 8),
    Expanded(child: Builder(builder: (context) => Container(width: double.infinity, height: 1, color: context.pal.divider))),
  ]);

  Widget _detailCard(LeaveCalendarEntry e) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Theme.of(context).extension<AppPalette>()!.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).extension<AppPalette>()!.border)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Symbols.event_note, size: 18, color: AppColors.amber),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(e.userName, style: AppTheme.cardTitle.copyWith(fontSize: 13)),
        const SizedBox(height: 3),
        Text('${e.leaveTypeLabel} · ${e.startDate} – ${e.endDate}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      ])),
      GestureDetector(onTap: () => setState(() => _selected = null), child: Icon(Symbols.close, size: 16, color: Theme.of(context).extension<AppPalette>()!.textDim)),
    ]),
  );
}

class _ParsedEntry {
  const _ParsedEntry({required this.entry, required this.start, required this.end});
  final LeaveCalendarEntry entry;
  final DateTime start;
  final DateTime end;
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({required this.month, required this.onPrev, required this.onNext});
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _names = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(999), border: Border.all(color: context.pal.border)),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(context, Symbols.chevron_left, onPrev),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('${_names[month.month]} ${month.year}', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
      _btn(context, Symbols.chevron_right, onNext),
    ]),
  );

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 26, height: 26, alignment: Alignment.center,
      decoration: BoxDecoration(color: context.pal.surface3, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: context.pal.textDim),
    ),
  );
}
