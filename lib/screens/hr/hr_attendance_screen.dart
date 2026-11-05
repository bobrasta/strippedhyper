import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/attendance_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../main.dart' show roleDisplayName;

/// Attendance — ported from HR Redesign spec 1f: KPI row, inline per-person
/// state pills ("click a state to set it" — no dialog for the common case),
/// and a month heat grid with totals. Manual marking is the primary path
/// (always works, no external dependency); bulk Excel import from a
/// biometric terminal export is a best-effort bonus layered on the same
/// records table.
class HrAttendanceScreen extends StatefulWidget {
  const HrAttendanceScreen({super.key});

  @override
  State<HrAttendanceScreen> createState() => _HrAttendanceScreenState();
}

class _HrAttendanceScreenState extends State<HrAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  List<StaffMember> _staff = [];
  List<AttendanceRecord> _dayRecords = [];
  List<AttendanceRecord> _monthRecords = [];
  Map<String, List<AttendanceRecord>> _monthByUser = {};
  bool _loading = true;
  String? _error;
  AttendanceImportResult? _lastImport;

  static const _statuses = ['present', 'late', 'absent', 'half_day', 'leave'];
  static const _statusLabels = {'present': 'Present', 'late': 'Late', 'absent': 'Absent', 'half_day': 'Half day', 'leave': 'Leave'};

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: seed from whatever's already cached for the
    // current month (the default landing view) so this screen doesn't
    // blank to a spinner on every navigation — see MachineService's own
    // doc comment for the full reasoning. Scoped to the current month's
    // exact query key, same as AttendanceService.cachedByQuery elsewhere;
    // paging to a different month still shows the normal loading state.
    final cachedStaff = StaffService.instance.staffNotifier.value;
    final monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final cachedMonth = AttendanceService.cachedByQuery['${_fmt(monthStart)}|${_fmt(monthEnd)}|'];
    if (cachedStaff.isNotEmpty) _staff = cachedStaff;
    if (cachedMonth != null) {
      _monthRecords = cachedMonth;
      final byUser = <String, List<AttendanceRecord>>{};
      for (final r in cachedMonth) { byUser.putIfAbsent('${r.userId}', () => []).add(r); }
      _monthByUser = byUser;
      _dayRecords = cachedMonth.where((r) => r.date == _fmt(_selectedDate)).toList();
    }
    if (cachedStaff.isNotEmpty || cachedMonth != null) _loading = false;
    _load();
  }

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      if (_staff.isEmpty && _monthRecords.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
      final results = await Future.wait([
        StaffService.instance.list(),
        AttendanceService.instance.list(start: _fmt(monthStart), end: _fmt(monthEnd)),
      ]);
      final staff = results[0] as List<StaffMember>;
      final monthRecords = results[1] as List<AttendanceRecord>;
      final byUser = <String, List<AttendanceRecord>>{};
      for (final r in monthRecords) {
        byUser.putIfAbsent('${r.userId}', () => []).add(r);
      }
      if (mounted) setState(() {
        _staff = staff;
        _monthRecords = monthRecords;
        _monthByUser = byUser;
        _dayRecords = monthRecords.where((r) => r.date == _fmt(_selectedDate)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) { setState(() => _selectedDate = picked); _load(); }
  }

  Future<void> _setStatus(StaffMember s, String status) async {
    try {
      await AttendanceService.instance.mark({'user_id': s.id, 'date': _fmt(_selectedDate), 'status': status});
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _markAllPresent() async {
    final unmarked = _staff.where((s) => !_dayRecords.any((r) => r.userId == s.id)).map((s) => s.id).toList();
    if (unmarked.isEmpty) { showSuccessToast(context, 'Everyone is already marked.'); return; }
    try {
      await AttendanceService.instance.bulkMark(userIds: unmarked, date: _fmt(_selectedDate), status: 'present');
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.single.path == null) return;
    try {
      final res = await AttendanceService.instance.import(result.files.single.path!, result.files.single.name);
      if (mounted) {
        setState(() => _lastImport = res);
        showSuccessToast(context, '${res.matchedCount}/${res.rowCount} row(s) matched.');
      }
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Color _statusColor(String s) => switch (s) {
    'present' => AppColors.green, 'late' => AppColors.amber, 'absent' => AppColors.coral,
    'half_day' => AppColors.info, 'leave' => AppColors.amber, _ => AppColors.textMute,
  };

  @override
  Widget build(BuildContext context) {
    final unmarkedCount = _staff.length - _dayRecords.length;
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 900;
      return Padding(
        padding: EdgeInsets.all(pad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(unmarkedCount, phone: cst.maxWidth < 600),
          const SizedBox(height: 4),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_error != null && _staff.isEmpty && _monthRecords.isEmpty)
                    ? ErrorView(message: _error!, onRetry: _load)
                    : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _kpiRow(),
                        const SizedBox(height: 16),
                        if (_lastImport != null) ...[_importSummary(_lastImport!), const SizedBox(height: 14)],
                        wide
                            ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(flex: 6, child: _markCard()),
                                const SizedBox(width: 16),
                                Expanded(flex: 5, child: _monthHeatmap()),
                              ]))
                            : Column(children: [_markCard(), const SizedBox(height: 16), _monthHeatmap()]),
                      ])),
          ),
        ]),
      );
    });
  }

  Widget _header(int unmarked, {bool phone = false}) => phone
      // Phones: title, then date + the import icon + "All present" on one row.
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Attendance', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
          const SizedBox(height: 3),
          Text('${_weekday(_selectedDate)} · $unmarked of ${_staff.length} still unmarked',
              style: AppTheme.bodySub.copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _DatePill(date: _selectedDate, onTap: _pickDate),
            IconButton(tooltip: 'Import biometric', onPressed: _importFile,
                icon: const Icon(Symbols.upload_file, size: 20)),
            FilledButton.icon(onPressed: _markAllPresent, icon: const Icon(Symbols.check_circle, size: 16),
                label: const Text('All present')),
          ]),
        ])
      : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Container(width: 2, height: 32, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Attendance', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
      const SizedBox(height: 3),
      Text('${_weekday(_selectedDate)} · $unmarked of ${_staff.length} still unmarked', style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ])),
    OutlinedButton.icon(onPressed: _importFile, icon: const Icon(Symbols.upload_file, size: 15), label: const Text('Import biometric')),
    const SizedBox(width: 8),
    _DatePill(date: _selectedDate, onTap: _pickDate),
    const SizedBox(width: 8),
    FilledButton.icon(onPressed: _markAllPresent, icon: const Icon(Symbols.check_circle, size: 16), label: const Text('Mark all present')),
  ]);

  static const _weekdays = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _monthNames = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static String _weekday(DateTime d) => '${_weekdays[d.weekday]} ${d.day} ${_monthNames[d.month]} ${d.year}';

  Widget _kpiRow() {
    final present = _monthRecords.where((r) => r.status == 'present').length;
    final presentRate = _monthRecords.isNotEmpty ? (present / _monthRecords.length * 100).round() : 0;
    final late = _monthRecords.where((r) => r.status == 'late').length;
    final absent = _monthRecords.where((r) => r.status == 'absent').length;
    final overtime = _monthRecords.fold<double>(0, (a, r) => a + (r.overtimeHours ?? 0));

    final tiles = [
      (label: 'Present rate', value: '$presentRate', unit: '%', icon: Symbols.check_circle, color: AppColors.green),
      (label: 'Late arrivals', value: '$late', unit: 'this month', icon: Symbols.schedule, color: AppColors.amber),
      (label: 'Absences', value: '$absent', unit: 'this month', icon: Symbols.cancel, color: AppColors.coral),
      (label: 'Overtime', value: overtime.toStringAsFixed(1), unit: 'hours', icon: Symbols.hourglass_top, color: AppColors.cyan),
    ];
    return GridView.count(
      crossAxisCount: 4, shrinkWrap: true, mainAxisSpacing: 12, crossAxisSpacing: 12,
      childAspectRatio: 3.6, physics: const NeverScrollableScrollPhysics(),
      children: tiles.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(left: -14, top: -12, bottom: -12, width: 2, child: Container(color: t.color)),
          Row(children: [
            Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: t.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)), child: Icon(t.icon, size: 15, color: t.color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t.label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
              const SizedBox(height: 2),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(t.value, style: AppTheme.kpiValue.copyWith(fontSize: 19)),
                const SizedBox(width: 5),
                Text(t.unit, style: AppTheme.monoXs.copyWith(fontSize: 10)),
              ]),
            ])),
          ]),
        ]),
      )).toList(),
    );
  }

  Widget _importSummary(AttendanceImportResult r) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.pal.border)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Symbols.fact_check, size: 18, color: r.unmatchedRows.isEmpty ? AppColors.green : AppColors.amber),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r.filename}: ${r.matchedCount}/${r.rowCount} rows matched', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
        if (r.unmatchedRows.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${r.unmatchedRows.length} row(s) need manual marking — no matching staff member or unreadable date:', style: AppTheme.bodySub.copyWith(fontSize: 11)),
          ...r.unmatchedRows.take(5).map((row) => Text('· ${row['name'] ?? row['id'] ?? '—'} (row ${row['row']}) — ${row['reason']}', style: AppTheme.monoXs)),
        ],
      ])),
      GestureDetector(onTap: () => setState(() => _lastImport = null), child: Icon(Symbols.close, size: 16, color: context.pal.textDim)),
    ]),
  );

  Widget _markCard() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(Symbols.fingerprint, size: 13, color: AppColors.cyan),
      const SizedBox(width: 8),
      Text('MARK TODAY', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
      const SizedBox(width: 8),
      Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      Flexible(child: Text('Click a state to set it', style: AppTheme.monoXs.copyWith(fontSize: 10.5),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
    const SizedBox(height: 9),
    Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: Column(children: _staff.map((s) {
        final rec = _dayRecords.where((r) => r.userId == s.id).toList();
        final current = rec.isNotEmpty ? rec.first.status : null;
        final clock = rec.isNotEmpty && rec.first.clockIn != null
            ? '${rec.first.clockIn} → ${rec.first.clockOut ?? '—'}'
            : (current == 'absent' ? 'no clock-in' : '—');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            _avatar(s),
            const SizedBox(width: 11),
            SizedBox(width: 118, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(s.positionTitle ?? roleDisplayName(s.role), style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            SizedBox(width: 90, child: Text(clock, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: current == 'absent' ? AppColors.coral : context.pal.textDim))),
            const SizedBox(width: 10),
            Expanded(child: Row(children: [
              for (var i = 0; i < _statuses.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _statusButton(s, _statuses[i], current)),
              ],
            ])),
          ]),
        );
      }).toList()),
    ),
  ]);

  Widget _statusButton(StaffMember s, String status, String? current) {
    final on = status == current;
    final c = _statusColor(status);
    return GestureDetector(
      onTap: () => _setStatus(s, status),
      child: Container(
        height: 32, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? c : context.pal.border),
        ),
        child: Text(_statusLabels[status]!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: on ? const Color(0xFF08090B) : context.pal.textDim)),
      ),
    );
  }

  Widget _avatar(StaffMember s) {
    final palette = [AppColors.cyan, AppColors.amber, AppColors.violet, AppColors.coral, AppColors.info, AppColors.green];
    return Container(
      width: 28, height: 28, alignment: Alignment.center,
      decoration: BoxDecoration(color: palette[s.id % palette.length], shape: BoxShape.circle),
      child: Text(s.initials, style: AppTheme.monoXs.copyWith(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF08090B))),
    );
  }

  Widget _monthHeatmap() {
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final markedDays = _monthRecords.map((r) => r.date).toSet().length;
    final present = _monthRecords.where((r) => r.status == 'present').length;
    final late = _monthRecords.where((r) => r.status == 'late').length;
    final absent = _monthRecords.where((r) => r.status == 'absent').length;
    final leave = _monthRecords.where((r) => r.status == 'leave').length;
    final total = _monthRecords.length;
    final totals = [
      (label: 'Present', n: present, color: AppColors.green),
      (label: 'Late', n: late, color: AppColors.amber),
      (label: 'Absent', n: absent, color: AppColors.coral),
      (label: 'Leave', n: leave, color: AppColors.amber),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.grid_view, size: 13, color: AppColors.cyan),
        const SizedBox(width: 8),
        Text('${_monthNames[_selectedDate.month].toUpperCase()} ${_selectedDate.year}', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 8),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        Text('$markedDays marked days', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
      ]),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ..._staff.take(8).map((s) {
            final records = {for (final r in _monthByUser['${s.id}'] ?? <AttendanceRecord>[]) r.date: r};
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                SizedBox(width: 82, child: Text(s.name, style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 10),
                Expanded(child: Row(children: List.generate(daysInMonth, (i) {
                  final date = DateTime(_selectedDate.year, _selectedDate.month, i + 1);
                  final rec = records[_fmt(date)];
                  final color = rec != null ? _statusColor(rec.status) : context.pal.surface3;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  ));
                }))),
              ]),
            );
          }),
          const SizedBox(height: 5),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _legendDot(AppColors.green, 'Present'), _legendDot(AppColors.amber, 'Late'),
            _legendDot(AppColors.coral, 'Absent'), _legendDot(AppColors.amber, 'Leave'),
          ]),
          const SizedBox(height: 14),
          Text('MONTH TOTALS', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
          const SizedBox(height: 9),
          ...totals.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 60, child: Text(t.label, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
                value: total > 0 ? t.n / total : 0, minHeight: 7, backgroundColor: context.pal.surface3,
                valueColor: AlwaysStoppedAnimation(t.color),
              ))),
              const SizedBox(width: 8),
              SizedBox(width: 24, child: Text('${t.n}', textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text))),
            ]),
          )),
        ]),
      ),
    ]);
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: AppTheme.monoXs.copyWith(fontSize: 11)),
  ]);
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(9), border: Border.all(color: context.pal.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Symbols.calendar_month, size: 14, color: context.pal.textDim),
        const SizedBox(width: 6),
        Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}', style: AppTheme.monoXs.copyWith(fontSize: 12, color: context.pal.text)),
      ]),
    ),
  );
}
