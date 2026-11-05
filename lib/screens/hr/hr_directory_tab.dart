import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/leave_request.dart';
import '../../services/attendance_service.dart';
import '../../services/contract_service.dart';
import '../../services/disciplinary_case_service.dart';
import '../../services/leave_service.dart';
import '../../services/payroll_service.dart';
import '../../services/position_change_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../theme/hr_category_colors.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import 'staff_hr_dialogs.dart';
import '../../widgets/common/labeled_field.dart';
import '../../main.dart' show roleDisplayName;

/// Directory — ported from HR Redesign spec 1c: a staff rail, a profile
/// centre with a tab strip (only Profile has real content, matching what
/// the design itself specifies), and a contracts/discipline/career rail.
class HrDirectoryTab extends StatefulWidget {
  const HrDirectoryTab({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<HrDirectoryTab> createState() => _HrDirectoryTabState();
}

class _HrDirectoryTabState extends State<HrDirectoryTab> {
  List<StaffMember> _staff = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _filter = 'all'; // all | field | office | admin
  int? _selectedId;

  bool _loadingDetail = false;
  List<Contract> _contracts = [];
  List<DisciplinaryCase> _cases = [];
  List<PositionChange> _careerLog = [];
  List<LeaveBalanceEntry> _balances = [];
  List<AttendanceRecord> _attendance = [];
  List<LeaveRequest> _leaveHistory = [];
  List<PayrollHistoryItem> _payrollHistory = [];

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning. Direct field assignment (no setState) since this runs
    // before the first build.
    final cachedStaff = StaffService.instance.staffNotifier.value;
    if (cachedStaff.isNotEmpty) {
      _staff = cachedStaff;
      _loading = false;
      _selectedId = cachedStaff.first.id;
      _seedDetailFromCache(_selectedId!);
    }
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      if (_staff.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await StaffService.instance.list(force: force);
      if (!mounted) return;
      setState(() {
        _staff = list;
        _loading = false;
        _selectedId ??= list.isNotEmpty ? list.first.id : null;
      });
      if (_selectedId != null) _loadDetail(_selectedId!);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Seeds the per-staff detail panes (contracts/cases/career/balances/
  // attendance/leave/payroll) from each service's own stale-while-
  // revalidate cache for [userId] — resetting every field to that id's
  // cache entry (or empty), never leaving a previously-selected staff
  // member's data showing under a new id. Mutates fields directly; callers
  // wrap this in setState() themselves except the initState seed, which
  // runs before the first build.
  void _seedDetailFromCache(int userId) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 90));
    final cachedAttendance = AttendanceService.cachedByQuery['${_fmt(start)}|${_fmt(now)}|$userId'];
    final cachedContracts  = ContractService.cachedByUserId[userId];
    final cachedCases      = DisciplinaryCaseService.cachedByUserId[userId];
    final cachedCareer     = PositionChangeService.cachedByUserId[userId];
    final cachedBalances   = LeaveService.cachedBalancesByUserId[userId];
    final cachedLeave      = LeaveService.cachedByUserId[userId];
    final cachedPayroll    = PayrollService.cachedHistoryForUser[userId];
    _contracts      = cachedContracts ?? [];
    _cases          = cachedCases ?? [];
    _careerLog      = cachedCareer ?? [];
    _balances       = cachedBalances ?? [];
    _attendance     = cachedAttendance ?? [];
    _leaveHistory   = cachedLeave ?? [];
    _payrollHistory = cachedPayroll ?? [];
    _loadingDetail = cachedContracts == null && cachedCases == null && cachedCareer == null &&
        cachedBalances == null && cachedAttendance == null && cachedLeave == null && cachedPayroll == null;
  }

  Future<void> _loadDetail(int userId) async {
    setState(() => _seedDetailFromCache(userId));
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 90));
      final results = await Future.wait([
        ContractService.instance.list(userId),
        DisciplinaryCaseService.instance.list(userId),
        PositionChangeService.instance.list(userId),
        LeaveService.instance.balances(userId: userId, year: now.year),
        AttendanceService.instance.list(start: _fmt(start), end: _fmt(now), userId: userId),
        LeaveService.instance.list(userId: userId),
        PayrollService.instance.historyForUser(userId),
      ]);
      if (!mounted || _selectedId != userId) return;
      setState(() {
        _contracts   = results[0] as List<Contract>;
        _cases       = results[1] as List<DisciplinaryCase>;
        _careerLog   = results[2] as List<PositionChange>;
        _balances    = results[3] as List<LeaveBalanceEntry>;
        _attendance  = results[4] as List<AttendanceRecord>;
        _leaveHistory   = results[5] as List<LeaveRequest>;
        _payrollHistory = results[6] as List<PayrollHistoryItem>;
        _loadingDetail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _uploadContractDocument(Contract c) async {
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.single.path == null) return;
    try {
      await ContractService.instance.uploadDocument(c.id, result.files.single.path!, result.files.single.name);
      if (mounted) showSuccessToast(context, 'Document uploaded.');
      if (_selectedId != null) _loadDetail(_selectedId!);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _openContractDocument(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  List<StaffMember> get _filtered {
    var list = _staff;
    if (_filter != 'all') list = list.where((s) => s.group == _filter).toList();
    if (_search.isNotEmpty) list = list.where((s) => s.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return list;
  }

  void _select(int id) {
    setState(() => _selectedId = id);
    _loadDetail(id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _staff.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    final selectedMatches = _staff.where((s) => s.id == _selectedId);
    final selected = selectedMatches.isEmpty ? null : selectedMatches.first;
    final incompleteIds = _staff.where((s) => _flagged(s)).length;

    return LayoutBuilder(builder: (ctx, cst) {
      final narrow = cst.maxWidth < 900;

      final rail = _staffRail(context);
      final centre = selected == null
          ? Center(child: Text('Select a staff member', style: AppTheme.bodySub))
          : _ProfileCentre(member: selected, staffList: _staff, onChanged: () => _load(force: true), balances: _balances, attendance: _attendance, loading: _loadingDetail, onNavigateTo: widget.onNavigateTo, leaveHistory: _leaveHistory, payrollHistory: _payrollHistory, contracts: _contracts);
      final sideRail = selected == null ? const SizedBox.shrink() : _detailRail(context, selected);

      if (narrow) {
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _headerRow(context, incompleteIds),
          ),
          Expanded(child: selected != null && _selectedId != null
              ? DefaultTabController(length: 1, child: centre)
              : rail),
        ]);
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 12), child: _headerRow(context, incompleteIds)),
        Container(width: double.infinity, height: 1, color: context.pal.divider),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 260, child: rail),
          Container(width: 1, color: context.pal.border),
          Expanded(flex: selected != null ? 7 : 1, child: centre),
          if (selected != null) ...[
            Container(width: 1, color: context.pal.border),
            Expanded(flex: 5, child: sideRail),
          ],
        ])),
      ]);
    });
  }

  bool _flagged(StaffMember s) => s.nssfNumber == null || s.tinNumber == null || s.nidaNumber == null;

  Widget _headerRow(BuildContext context, int incomplete) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Container(width: 2, height: 32, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Directory', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
      const SizedBox(height: 3),
      Text('${_staff.length} staff · $incomplete with incomplete statutory IDs', style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ])),
  ]);

  Widget _staffRail(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SearchField(hint: 'Search staff…', onChanged: (v) => setState(() => _search = v)),
        const SizedBox(height: 9),
        Wrap(spacing: 5, runSpacing: 5, children: [
          _filterChip('all', 'All ${_staff.length}'),
          _filterChip('field', 'Field'),
          _filterChip('office', 'Office'),
          _filterChip('admin', 'Admin'),
        ]),
      ]),
    ),
    Expanded(child: ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final s = _filtered[i];
        final active = s.id == _selectedId;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _select(s.id),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(color: active ? context.pal.surface2 : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              _avatar(s, 28),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: active ? AppColors.cyan : context.pal.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(s.positionTitle ?? roleDisplayName(s.role), style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (_flagged(s)) Icon(Symbols.warning, size: 14, color: AppColors.amber, fill: 1),
            ]),
          ),
        );
      },
    )),
  ]);

  Widget _filterChip(String key, String label) {
    final active = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active ? null : Border.all(color: Theme.of(context).extension<AppPalette>()!.border),
        ),
        child: Text(label, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: active ? const Color(0xFF08090B) : null)),
      ),
    );
  }

  Widget _avatar(StaffMember s, double size) => Container(
    width: size, height: size, alignment: Alignment.center,
    decoration: BoxDecoration(color: _avatarColor(s), shape: BoxShape.circle),
    child: Text(s.initials, style: AppTheme.monoXs.copyWith(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: const Color(0xFF08090B))),
  );

  static Color _avatarColor(StaffMember s) {
    final palette = [AppColors.cyan, AppColors.amber, AppColors.violet, AppColors.coral, AppColors.info, AppColors.green];
    return palette[s.id % palette.length];
  }

  Widget _detailRail(BuildContext context, StaffMember member) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _railHeader(Symbols.description, HrCategory.contracts.color, 'Contracts', onAdd: () => showContractsDialog(context, member)),
      const SizedBox(height: 9),
      _contractsCard(context),
      const SizedBox(height: 18),
      _railHeader(Symbols.gavel, HrCategory.discipline.color, 'Discipline', onAdd: () => showDisciplinaryCasesDialog(context, member)),
      const SizedBox(height: 9),
      _disciplineCard(context),
      const SizedBox(height: 18),
      _railHeader(Symbols.trending_up, AppColors.cyan, 'Career progression', onAdd: () => showCareerProgressionDialog(context, member)),
      const SizedBox(height: 9),
      _careerCard(context),
      const SizedBox(height: 18),
      _railHeader(Symbols.payments, AppColors.amber, 'Salary', onAdd: () => showSalaryAdjustmentsDialog(context, member)),
      const SizedBox(height: 9),
      _railCard(child: GestureDetector(
        onTap: () => showSalaryAdjustmentsDialog(context, member),
        child: Row(children: [
          Icon(Symbols.history, size: 14, color: context.pal.textDim),
          const SizedBox(width: 7),
          Text('View adjustment history', style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: context.pal.textDim)),
        ]),
      )),
    ]),
  );

  Widget _railHeader(IconData icon, Color color, String title, {required VoidCallback onAdd}) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 8),
    Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
    const SizedBox(width: 8),
    Expanded(child: Container(width: double.infinity, height: 1, color: Theme.of(context).extension<AppPalette>()!.divider)),
    GestureDetector(onTap: onAdd, child: Icon(Symbols.add, size: 15, color: Theme.of(context).extension<AppPalette>()!.textDim)),
  ]);

  Widget _railCard({required Widget child}) => Builder(builder: (context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: child,
  ));

  Widget _contractsCard(BuildContext context) {
    if (_loadingDetail) return _railCard(child: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    if (_contracts.isEmpty) return _railCard(child: Text('No contracts yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)));
    return Column(children: _contracts.take(2).map((c) {
      final active = c.status == 'active';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _railCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (active ? AppColors.green : context.pal.textDim).withValues(alpha: active ? 0.14 : 0.12), borderRadius: BorderRadius.circular(5)),
              child: Text(c.status, style: AppTheme.monoXs.copyWith(fontSize: 10, color: active ? AppColors.green : context.pal.textDim)),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(c.contractType == 'permanent' ? 'Permanent' : 'Fixed term', style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
            Text('since ${c.startDate}', style: AppTheme.monoXs.copyWith(fontSize: 11)),
          ]),
          if (active) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _miniStat('Base salary', c.baseSalary != null ? _money(c.baseSalary!) : '—')),
              Expanded(child: _miniStat('Probation', c.probationEndDate != null && DateTime.tryParse(c.probationEndDate!)?.isBefore(DateTime.now()) == true ? 'passed' : 'active')),
            ]),
          ],
          const SizedBox(height: 10),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 10),
          if (c.hasDocument)
            GestureDetector(
              onTap: () => _openContractDocument(c.documentUrl!),
              child: Row(children: [
                Icon(Symbols.picture_as_pdf, size: 14, color: AppColors.coral),
                const SizedBox(width: 7),
                Expanded(child: Text(c.documentName ?? 'Document', style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: AppColors.coral), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Icon(Symbols.open_in_new, size: 13, color: context.pal.textDim),
              ]),
            )
          else
            GestureDetector(
              onTap: () => _uploadContractDocument(c),
              child: Row(children: [
                Icon(Symbols.upload_file, size: 14, color: context.pal.textDim),
                const SizedBox(width: 7),
                Text('Upload signed document', style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: context.pal.textDim)),
              ]),
            ),
        ])),
      );
    }).toList());
  }

  Widget _miniStat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
    const SizedBox(height: 2),
    Text(value, style: AppTheme.monoXs.copyWith(fontSize: 13, color: Theme.of(context).extension<AppPalette>()?.text)),
  ]);

  static String _money(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  Widget _disciplineCard(BuildContext context) {
    if (_loadingDetail) return _railCard(child: const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    final open = _cases.where((c) => c.status == 'open').toList();
    final clean = open.isEmpty;
    return _railCard(child: Row(children: [
      Container(
        width: 30, height: 30, alignment: Alignment.center,
        decoration: BoxDecoration(color: (clean ? AppColors.info : AppColors.coral).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
        child: Icon(clean ? Symbols.check : Symbols.warning, size: 15, color: clean ? AppColors.info : AppColors.coral),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(clean ? 'Clean record' : '${open.length} open case(s)', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
        Text(clean ? 'No open cases on record' : open.first.stage.replaceAll('_', ' '), style: AppTheme.bodySub.copyWith(fontSize: 11)),
      ])),
    ]));
  }

  Widget _careerCard(BuildContext context) {
    if (_loadingDetail) return _railCard(child: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    if (_careerLog.isEmpty) return _railCard(child: Text('No changes recorded yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)));
    return _railCard(child: Column(children: _careerLog.take(3).toList().asMap().entries.map((e) {
      final i = e.key; final c = e.value;
      final last = i == _careerLog.take(3).length - 1;
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 10, child: Column(children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: i == 0 ? AppColors.cyan : context.pal.textDim, shape: BoxShape.circle)),
          if (!last) Expanded(child: Container(width: 1, color: context.pal.border)),
        ])),
        const SizedBox(width: 11),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.toPositionTitle ?? '—'}${i == 0 ? ' · current' : ''}', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            const SizedBox(height: 3),
            Text(c.effectiveDate, style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
          ]),
        )),
      ]));
    }).toList()));
  }
}

class _ProfileCentre extends StatefulWidget {
  const _ProfileCentre({
    required this.member, required this.staffList, required this.onChanged,
    required this.balances, required this.attendance, required this.loading, this.onNavigateTo,
    required this.leaveHistory, required this.payrollHistory, required this.contracts,
  });
  final StaffMember member;
  final List<StaffMember> staffList;
  final VoidCallback onChanged;
  final List<LeaveBalanceEntry> balances;
  final List<AttendanceRecord> attendance;
  final bool loading;
  final void Function(String key)? onNavigateTo;
  final List<LeaveRequest> leaveHistory;
  final List<PayrollHistoryItem> payrollHistory;
  final List<Contract> contracts;

  @override
  State<_ProfileCentre> createState() => _ProfileCentreState();
}

class _ProfileCentreState extends State<_ProfileCentre> {
  int _tab = 0;
  static const _tabs = ['Profile', 'Leave', 'Attendance', 'Payroll', 'Documents'];

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final tenure = m.hireDate != null ? _tenure(m.hireDate!) : null;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Row(children: [
            Container(
              width: 50, height: 50, alignment: Alignment.center,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.cyan, AppColors.green]), shape: BoxShape.circle),
              child: Text(m.initials, style: AppTheme.bodyStrong.copyWith(fontSize: 15, color: const Color(0xFF08090B))),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(m.name, style: AppTheme.pageTitle.copyWith(fontSize: 19)),
                const SizedBox(width: 8),
                _tinyBadge(AppColors.cyan, m.role),
                const SizedBox(width: 6),
                _tinyBadge(AppColors.green, 'active'),
              ]),
              const SizedBox(height: 3),
              Text(
                [m.positionTitle, m.zone, m.hireDate != null ? 'hired ${formatDate(m.hireDate!)}' : null, tenure]
                    .where((s) => s != null).join(' · '),
                style: AppTheme.bodySub.copyWith(fontSize: 11.5),
              ),
            ])),
            TextButton.icon(
              onPressed: () => showEditHrDetailsDialog(context, m, widget.staffList, widget.onChanged),
              icon: const Icon(Symbols.edit, size: 14), label: const Text('Edit'),
            ),
          ]),
        ),
        Row(children: [
          const SizedBox(width: 22),
          ..._tabs.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(right: 18),
            child: GestureDetector(
              onTap: () => setState(() => _tab = e.key),
              child: Container(
                padding: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == e.key ? AppColors.cyan : Colors.transparent, width: 2))),
                child: Text(e.value, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: _tab == e.key ? context.pal.text : context.pal.textDim)),
              ),
            ),
          )),
        ]),
        Container(width: double.infinity, height: 1, color: context.pal.border),
        Padding(padding: const EdgeInsets.all(22), child: _tabContent(context, m)),
      ]),
    );
  }

  Widget _tinyBadge(Color c, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: AppTheme.monoXs.copyWith(fontSize: 10, color: c)),
  );

  static String _tenure(DateTime hired) {
    final days = DateTime.now().difference(hired).inDays;
    final years = days ~/ 365;
    final months = (days % 365) ~/ 30;
    if (years == 0) return '${months}m';
    return '${years}y ${months}m';
  }

  Widget _tabContent(BuildContext context, StaffMember m) {
    return switch (_tab) {
      1 => _leaveTab(context),
      2 => _attendanceTab(context),
      3 => _payrollTab(context),
      4 => _documentsTab(context),
      _ => _profileTab(context, m),
    };
  }

  Widget _profileTab(BuildContext context, StaffMember m) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _fieldGroup('Personal', [
          ('Gender', m.gender ?? '—'),
          ('Hire date', m.hireDate != null ? formatDate(m.hireDate!) : '—'),
          ('Email', m.email ?? '—'),
          ('Phone', m.phone ?? '—'),
          ('Zone', m.zone ?? '—'),
        ])),
        const SizedBox(width: 34),
        Expanded(child: _fieldGroup('Next of kin', [
          ('Name', m.nextOfKinName ?? '—'),
          ('Phone', m.nextOfKinPhone ?? '—'),
          ('Relationship', m.nextOfKinRelationship ?? '—'),
        ])),
      ]),
      const SizedBox(height: 26),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _idGroup(m)),
        const SizedBox(width: 34),
        Expanded(child: _balanceGroup(context)),
      ]),
      const SizedBox(height: 26),
      _attendanceStrip(context),
    ]);
  }

  Color _leaveStatusColor(LeaveStatus s) => switch (s) {
    LeaveStatus.approved => AppColors.green,
    LeaveStatus.rejected => AppColors.coral,
    LeaveStatus.cancelled => AppColors.textMute,
    LeaveStatus.pending => AppColors.amber,
  };

  Widget _leaveTab(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _balanceGroup(context),
      const SizedBox(height: 26),
      Row(children: [
        Text('REQUEST HISTORY', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      ]),
      const SizedBox(height: 11),
      if (widget.loading) const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (widget.leaveHistory.isEmpty) Text('No leave requests yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else Column(children: widget.leaveHistory.map((r) {
        final color = _leaveStatusColor(r.status);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.displayLabel, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
              const SizedBox(height: 2),
              Text('${r.startDate} → ${r.endDate} · ${r.daysCount} day(s)', style: AppTheme.bodySub.copyWith(fontSize: 11)),
              if (r.status == LeaveStatus.rejected && r.rejectionReason != null) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(r.rejectionReason!, style: AppTheme.bodySub.copyWith(fontSize: 10.5, fontStyle: FontStyle.italic)),
              ),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
              child: Text(r.status.label, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: color)),
            ),
          ]),
        );
      }).toList()),
    ]);
  }

  Color _attendanceStatusColor(String s) => switch (s) {
    'absent' => AppColors.coral, 'late' => AppColors.amber, 'leave' => AppColors.amber,
    'half_day' => AppColors.info, 'present' => AppColors.green, _ => AppColors.textMute,
  };

  Widget _attendanceTab(BuildContext context) {
    final sorted = [...widget.attendance]..sort((a, b) => b.date.compareTo(a.date));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('LAST 90 DAYS', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        Text('${sorted.length} marked', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
      ]),
      const SizedBox(height: 11),
      if (widget.loading) const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (sorted.isEmpty) Text('No attendance marked yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else Column(children: sorted.map((r) {
        final color = _attendanceStatusColor(r.status);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            SizedBox(width: 90, child: Text(r.date, style: AppTheme.monoXs.copyWith(fontSize: 11))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
              child: Text(r.status, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(
              r.clockIn != null ? '${r.clockIn} → ${r.clockOut ?? '—'}' : '—',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5),
            )),
            if ((r.overtimeHours ?? 0) > 0) Text('${r.overtimeHours!.toStringAsFixed(1)}h OT', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: AppColors.cyan)),
          ]),
        );
      }).toList()),
    ]);
  }

  static String _money(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  static const _monthNames = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  Color _payrollStatusColor(String s) => switch (s) {
    'paid' => AppColors.green, 'approved' => AppColors.info, 'reviewed' => AppColors.amber, _ => AppColors.textMute,
  };

  Widget _payrollTab(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('PAY HISTORY', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      ]),
      const SizedBox(height: 11),
      if (widget.loading) const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (widget.payrollHistory.isEmpty) Text('No payroll history yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else Column(children: [
        Row(children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(flex: 2, child: Text('GROSS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
          Expanded(flex: 2, child: Text('NET', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
          const SizedBox(width: 80),
        ]),
        const SizedBox(height: 8),
        Container(width: double.infinity, height: 1, color: context.pal.border),
        ...widget.payrollHistory.map((p) {
          final color = _payrollStatusColor(p.status);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
            child: Row(children: [
              Expanded(flex: 3, child: Text('${_monthNames[p.periodMonth]} ${p.periodYear}', style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
              Expanded(flex: 2, child: Text(_money(p.grossPay), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5))),
              Expanded(flex: 2, child: Text(_money(p.netPay), textAlign: TextAlign.right, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: AppColors.green))),
              SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                child: Text(p.status, style: AppTheme.monoXs.copyWith(fontSize: 10, color: color)),
              ))),
            ]),
          );
        }),
      ]),
    ]);
  }

  Future<void> _uploadDocumentFor(Contract c) async {
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.single.path == null) return;
    try {
      await ContractService.instance.uploadDocument(c.id, result.files.single.path!, result.files.single.name);
      if (mounted) showSuccessToast(context, 'Document uploaded.');
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _openDocument(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Widget _documentsTab(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('CONTRACT DOCUMENTS', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      ]),
      const SizedBox(height: 11),
      if (widget.loading) const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (widget.contracts.isEmpty) Text('No contracts on file yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else Column(children: widget.contracts.map((c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
        child: Row(children: [
          Icon(c.hasDocument ? Symbols.picture_as_pdf : Symbols.description, size: 16, color: c.hasDocument ? AppColors.coral : context.pal.textDim),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.contractType == 'permanent' ? 'Permanent' : 'Fixed term'} · since ${c.startDate}', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(c.hasDocument ? c.documentName ?? 'Document' : 'No document uploaded', style: AppTheme.bodySub.copyWith(fontSize: 11)),
          ])),
          if (c.hasDocument)
            TextButton(onPressed: () => _openDocument(c.documentUrl!), child: const Text('View'))
          else
            TextButton(onPressed: () => _uploadDocumentFor(c), child: const Text('Upload')),
        ]),
      )).toList()),
    ]);
  }

  Widget _fieldGroup(String title, List<(String, String)> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
      const SizedBox(width: 9),
      Expanded(child: Builder(builder: (context) => Container(width: double.infinity, height: 1, color: context.pal.divider))),
    ]),
    const SizedBox(height: 11),
    ...rows.map((r) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        SizedBox(width: 96, child: Text(r.$1, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
        Expanded(child: Text(r.$2, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
      ]),
    )),
  ]);

  Widget _idGroup(StaffMember m) {
    final ids = [
      ('NSSF no.', m.nssfNumber),
      ('TIN no.', m.tinNumber),
      ('NIDA no.', m.nidaNumber),
      ('Biometric ID', m.biometricId),
    ];
    final complete = ids.where((e) => e.$2 != null).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('STATUTORY IDS', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Builder(builder: (context) => Container(width: double.infinity, height: 1, color: context.pal.divider))),
        Builder(builder: (context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: (complete == 4 ? AppColors.green : AppColors.amber).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
          child: Text('$complete / 4', style: AppTheme.monoXs.copyWith(fontSize: 10, color: complete == 4 ? AppColors.green : AppColors.amber)),
        )),
      ]),
      const SizedBox(height: 11),
      ...ids.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          SizedBox(width: 96, child: Text(e.$1, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
          Expanded(child: Text(e.$2 ?? 'not enrolled', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: e.$2 == null ? AppColors.amber : null))),
        ]),
      )),
    ]);
  }

  Widget _balanceGroup(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('LEAVE BALANCE ${DateTime.now().year}', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 9),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      ]),
      const SizedBox(height: 12),
      if (widget.loading) const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (widget.balances.isEmpty) Text('No balances yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else ...widget.balances.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.leaveTypeLabel, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
            Text('${b.usedDays.toStringAsFixed(0)} / ${b.allocatedDays.toStringAsFixed(0)}', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
            value: b.allocatedDays > 0 ? (b.usedDays / b.allocatedDays).clamp(0, 1) : 0,
            minHeight: 5, backgroundColor: context.pal.surface3,
            valueColor: AlwaysStoppedAnimation(AppColors.amber),
          )),
        ]),
      )),
    ]);
  }

  Widget _attendanceStrip(BuildContext context) {
    final present = widget.attendance.where((a) => a.status == 'present').length;
    final leave = widget.attendance.where((a) => a.status == 'leave').length;
    final late = widget.attendance.where((a) => a.status == 'late').length;
    final days = List.generate(21, (i) => DateTime.now().subtract(Duration(days: 20 - i)));
    final byDate = {for (final a in widget.attendance) a.date: a.status};

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.fingerprint, size: 13, color: AppColors.cyan),
        const SizedBox(width: 8),
        Text('ATTENDANCE · LAST 21 DAYS', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 8),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
        Text('$present present · $leave leave · $late late', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
      ]),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(children: [
          Row(children: days.map((d) {
            final status = byDate[_fmt(d)];
            final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
            final color = switch (status) {
              'absent' => AppColors.coral, 'late' => AppColors.amber, 'leave' => AppColors.amber,
              'present' || 'half_day' => const Color(0xFF17301F),
              _ => weekend ? const Color(0xFF14171C) : const Color(0xFF1B1F27),
            };
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(children: [
                Container(height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 5),
                Text('${d.day}', style: AppTheme.monoXs.copyWith(fontSize: 9)),
              ]),
            ));
          }).toList()),
          const SizedBox(height: 10),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 10),
          Row(children: [
            _legendDot(const Color(0xFF17301F), 'Present'),
            const SizedBox(width: 14),
            _legendDot(AppColors.amber, 'Late'),
            const SizedBox(width: 14),
            _legendDot(AppColors.coral, 'Absent'),
            const SizedBox(width: 14),
            _legendDot(AppColors.amber, 'Leave'),
            const Spacer(),
            GestureDetector(
              onTap: () => widget.onNavigateTo != null
                  ? widget.onNavigateTo!('hr_attendance')
                  : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use the Attendance screen for the full record.'))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Full record', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: AppColors.green)),
                const SizedBox(width: 4),
                Icon(Symbols.arrow_forward, size: 12, color: AppColors.green),
              ]),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11)),
  ]);

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
