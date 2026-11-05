import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/late_arrival.dart';
import '../../models/leave_request.dart';
import '../../services/late_arrival_service.dart';
import '../../services/leave_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../theme/hr_category_colors.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/hr_empty_state.dart';
import '../../widgets/common/labeled_field.dart';

/// HR approvals queue — ported from HR Redesign spec 1h. Card-based leave
/// queue with facts/overlap detection, a tab strip, and a coverage +
/// late-arrivals right rail.
class HrApprovalScreen extends StatefulWidget {
  const HrApprovalScreen({super.key, this.initialTabIndex});
  final int? initialTabIndex;

  @override
  State<HrApprovalScreen> createState() => _HrApprovalScreenState();
}

class _HrApprovalScreenState extends State<HrApprovalScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 4, vsync: this,
    initialIndex: (widget.initialTabIndex ?? 0).clamp(0, 3),
  );

  List<LeaveRequest> _all = [];
  List<LateArrival>  _lateArrivals = [];
  List<StaffMember>  _staff = [];
  List<LeaveBalanceEntry> _balances = [];
  bool    _loading = true;
  String? _error;

  List<LeaveRequest> get _pending => _all.where((r) => r.status == LeaveStatus.pending).toList()
    ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
  List<LeaveRequest> get _onLeaveNow {
    final today = DateTime.now();
    return _all.where((r) {
      if (r.status != LeaveStatus.approved) return false;
      final start = DateTime.tryParse(r.startDate);
      final end = DateTime.tryParse(r.endDate);
      if (start == null || end == null) return false;
      return !today.isBefore(start) && !today.isAfter(end);
    }).toList();
  }
  List<LeaveRequest> get _decided =>
      _all.where((r) => r.status == LeaveStatus.approved || r.status == LeaveStatus.rejected).toList()
        ..sort((a, b) => (b.reviewedAt ?? '').compareTo(a.reviewedAt ?? ''));

  StaffMember? _staffFor(int userId) {
    for (final s in _staff) { if (s.id == userId) return s; }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning. This screen combines 4 independent pieces, so "loading" is
    // only true when NONE of them have anything cached yet.
    final cachedAll = LeaveService.cachedDefaultList;
    final cachedLate = LateArrivalService.cachedDefaultList;
    final cachedStaff = StaffService.instance.staffNotifier.value;
    final cachedBalances = LeaveService.cachedBalancesByYear[DateTime.now().year];
    if (cachedAll != null) _all = cachedAll;
    if (cachedLate != null) _lateArrivals = cachedLate;
    if (cachedStaff.isNotEmpty) _staff = cachedStaff;
    if (cachedBalances != null) _balances = cachedBalances;
    if (cachedAll != null || cachedLate != null || cachedStaff.isNotEmpty || cachedBalances != null) {
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() {
      if (_all.isEmpty && _lateArrivals.isEmpty && _staff.isEmpty && _balances.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        LeaveService.instance.list(),
        LateArrivalService.instance.list(),
        StaffService.instance.list(),
        LeaveService.instance.balances(year: DateTime.now().year),
      ]);
      if (!mounted) return;
      setState(() {
        _all = results[0] as List<LeaveRequest>;
        _lateArrivals = results[1] as List<LateArrival>;
        _staff = results[2] as List<StaffMember>;
        _balances = results[3] as List<LeaveBalanceEntry>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _approve(LeaveRequest r) async {
    int? daysOverride;
    if (r.requiresManualDays) {
      daysOverride = await showDialog<int>(
        context: context,
        builder: (_) => _ManualDaysDialog(request: r),
      );
      if (daysOverride == null) return; // cancelled
    }
    try {
      await LeaveService.instance.approve(r.id, daysCountOverride: daysOverride);
      if (mounted) { showSuccessToast(context, 'Approved.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _reject(LeaveRequest r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectReasonDialog(),
    );
    if (reason == null) return;
    try {
      await LeaveService.instance.reject(r.id, reason: reason.isEmpty ? null : reason);
      if (mounted) { showSuccessToast(context, 'Rejected.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 980;
      final oldestDays = _pending.isEmpty ? 0 : _oldestAgeDays();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 2, height: 32, decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Leave & Attendance approvals', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
              const SizedBox(height: 3),
              Text(
                _pending.isEmpty
                    ? 'Nothing waiting on you right now'
                    : '${_pending.length} request${_pending.length == 1 ? '' : 's'} waiting'
                        '${oldestDays > 0 ? ' · oldest $oldestDays day${oldestDays == 1 ? '' : 's'}' : ''}',
                style: AppTheme.bodySub.copyWith(fontSize: 12),
              ),
            ])),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Symbols.refresh, size: 15), label: const Text('Refresh')),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          margin: EdgeInsets.symmetric(horizontal: pad),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: TabBar(
            controller: _tab,
            labelColor: AppColors.amber,
            unselectedLabelColor: context.pal.textMute,
            indicatorColor: AppColors.amber,
            indicatorWeight: 2,
            labelStyle: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
            unselectedLabelStyle: AppTheme.bodySm,
            tabs: [
              Tab(text: 'Pending (${_pending.length})'),
              Tab(text: 'On leave (${_onLeaveNow.length})'),
              Tab(text: 'Late arrivals (${_lateArrivals.length})'),
              Tab(text: 'Decided'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (_error != null && _all.isEmpty && _lateArrivals.isEmpty && _staff.isEmpty && _balances.isEmpty)
                  ? ErrorView(message: _error!, onRetry: _load)
                  : TabBarView(controller: _tab, children: [
                      _buildPendingWithRail(pad, wide),
                      _OnLeaveTab(requests: _onLeaveNow, pad: pad),
                      _LateArrivalsTab(arrivals: _lateArrivals, pad: pad),
                      _DecidedTab(requests: _decided, pad: pad),
                    ]),
        ),
      ]);
    });
  }

  int _oldestAgeDays() {
    DateTime? oldest;
    for (final r in _pending) {
      final c = DateTime.tryParse(r.createdAt ?? '');
      if (c != null && (oldest == null || c.isBefore(oldest))) oldest = c;
    }
    if (oldest == null) return 0;
    return DateTime.now().difference(oldest).inDays;
  }

  Widget _buildPendingWithRail(double pad, bool wide) {
    final queue = _PendingQueue(
      requests: _pending, pad: pad,
      staffFor: _staffFor, balances: _balances,
      allRequests: _all,
      onApprove: _approve, onReject: _reject,
    );
    final rail = _ApprovalsRail(staff: _staff, allRequests: _all, lateArrivals: _lateArrivals, pad: pad);
    if (!wide) {
      return SingleChildScrollView(padding: EdgeInsets.all(pad), child: Column(children: [queue, const SizedBox(height: 16), rail]));
    }
    return Padding(
      padding: EdgeInsets.all(pad),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 7, child: SingleChildScrollView(child: queue)),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: SingleChildScrollView(child: rail)),
      ]),
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Reject Leave Request', style: AppTheme.bodyStrong),
    content: LabeledTextField(label: 'Reason (optional)', controller: _ctrl, maxLines: 3),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()), child: Text('Reject', style: TextStyle(color: AppColors.coral))),
    ],
  );
}

// Compassionate leave: the requester submits a date range, but the final
// day count is the approver's call — asked for here rather than trusting
// the request's own days_count (see LeaveController::approve()).
class _ManualDaysDialog extends StatefulWidget {
  const _ManualDaysDialog({required this.request});
  final LeaveRequest request;

  @override
  State<_ManualDaysDialog> createState() => _ManualDaysDialogState();
}

class _ManualDaysDialogState extends State<_ManualDaysDialog> {
  late final _ctrl = TextEditingController(text: widget.request.daysCount.toString());

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Set ${widget.request.displayLabel} Days', style: AppTheme.bodyStrong),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.request.userName ?? 'This staff member'} requested ${widget.request.startDate} to ${widget.request.endDate}. '
          'How many days should count against their balance?',
          style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Days', controller: _ctrl, keyboardType: TextInputType.number),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final days = int.tryParse(_ctrl.text.trim());
          if (days != null && days > 0) Navigator.of(context).pop(days);
        },
        child: const Text('Approve'),
      ),
    ],
  );
}

bool _overlaps(LeaveRequest a, LeaveRequest b) {
  final aStart = DateTime.tryParse(a.startDate);
  final aEnd = DateTime.tryParse(a.endDate);
  final bStart = DateTime.tryParse(b.startDate);
  final bEnd = DateTime.tryParse(b.endDate);
  if (aStart == null || aEnd == null || bStart == null || bEnd == null) return false;
  return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
}

class _PendingQueue extends StatelessWidget {
  const _PendingQueue({
    required this.requests, required this.pad, required this.staffFor,
    required this.balances, required this.allRequests,
    required this.onApprove, required this.onReject,
  });
  final List<LeaveRequest> requests;
  final double pad;
  final StaffMember? Function(int) staffFor;
  final List<LeaveBalanceEntry> balances;
  final List<LeaveRequest> allRequests;
  final ValueChanged<LeaveRequest> onApprove;
  final ValueChanged<LeaveRequest> onReject;

  List<_Fact> _facts(LeaveRequest r) {
    final facts = <_Fact>[
      _Fact('Dates', '${r.startDate} → ${r.endDate}'),
    ];
    LeaveBalanceEntry? bal;
    for (final b in balances) {
      if (b.leaveTypeId == r.leaveTypeId) { bal = b; break; }
    }
    if (bal != null) {
      final after = (bal.remainingDays - r.daysCount).clamp(0, bal.allocatedDays);
      facts.add(_Fact('Balance after', '${after.toStringAsFixed(0)} / ${bal.allocatedDays.toStringAsFixed(0)} d'));
    }
    facts.add(_Fact('Working days', '${r.daysCount}'));
    final overlapping = allRequests.where((o) =>
        o.id != r.id && o.userId != r.userId &&
        (o.status == LeaveStatus.approved || o.status == LeaveStatus.pending) &&
        _overlaps(r, o)).toList();
    if (overlapping.isNotEmpty) {
      facts.add(_Fact('Overlaps', overlapping.map((o) => o.userName ?? '—').join(', '), warn: true));
    }
    return facts;
  }

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          border: Border.all(color: context.pal.border, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(AppColors.rLg),
        ),
        child: HrEmptyState(
          icon: HrCategory.leave.icon,
          title: 'No pending requests',
          message: 'That is the whole queue — nothing awaiting your review right now.',
        ),
      );
    }
    return Column(children: [
      ...requests.map((r) {
        final staff = staffFor(r.userId);
        final cat = HrCategory.leave;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 17, backgroundColor: cat.color.withValues(alpha: 0.18),
                  child: Text(_initialsOf(r.userName ?? '?'), style: AppTheme.bodyStrong.copyWith(fontSize: 12, color: cat.color))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(r.userName ?? '—', style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                  const SizedBox(width: 8),
                  _chip(context, r.displayLabel, cat.color),
                  const SizedBox(width: 6),
                  _chip(context, '${r.daysCount} day${r.daysCount == 1 ? '' : 's'}', context.pal.textMute, soft: true),
                ]),
                const SizedBox(height: 3),
                Text(
                  [if (staff?.positionTitle != null) staff!.positionTitle!, if (r.createdAt != null) 'requested ${_ago(r.createdAt!)}']
                      .join(' · '),
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5),
                ),
              ])),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, children: _facts(r).map((f) => _factTile(context, f)).toList()),
            if (r.reason != null && r.reason!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Symbols.chat_bubble, size: 14, color: context.pal.textMute),
                  const SizedBox(width: 8),
                  Expanded(child: Text('"${r.reason}"', style: AppTheme.bodySub.copyWith(fontSize: 12, fontStyle: FontStyle.italic))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => onReject(r),
                child: Container(height: 36,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('Reject', style: AppTheme.bodySm.copyWith(color: AppColors.coral)))),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => onApprove(r),
                child: Container(height: 36,
                  decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('Approve', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 12.5)))),
              )),
            ]),
          ]),
        );
      }),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.pal.border),
          borderRadius: BorderRadius.circular(AppColors.rLg),
        ),
        child: Text('That is the whole queue', style: AppTheme.bodySub.copyWith(fontSize: 12)),
      ),
    ]);
  }

  Widget _chip(BuildContext context, String text, Color color, {bool soft = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: soft ? context.pal.surface2 : color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: AppTheme.monoXs.copyWith(color: soft ? context.pal.textMute : color)),
  );

  Widget _factTile(BuildContext context, _Fact f) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(f.k, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
      const SizedBox(height: 2),
      Text(f.v, style: AppTheme.bodySm.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: f.warn ? AppColors.coral : null)),
    ]),
  );
}

class _Fact {
  const _Fact(this.k, this.v, {this.warn = false});
  final String k;
  final String v;
  final bool warn;
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
  return '?';
}

String _ago(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final diff = DateTime.now().difference(d);
  if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  return 'moments ago';
}

class _ApprovalsRail extends StatelessWidget {
  const _ApprovalsRail({required this.staff, required this.allRequests, required this.lateArrivals, required this.pad});
  final List<StaffMember> staff;
  final List<LeaveRequest> allRequests;
  final List<LateArrival> lateArrivals;
  final double pad;

  static String _groupLabel(String? g) => switch (g) {
    'field' => 'Field / Operations',
    'admin' => 'Admin / Executive',
    'office' => 'Office',
    _ => 'Unassigned',
  };

  List<_CoverageRow> _coverage() {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 14));
    final byGroup = <String, List<StaffMember>>{};
    for (final s in staff) {
      byGroup.putIfAbsent(_groupLabel(s.group), () => []).add(s);
    }
    final rows = <_CoverageRow>[];
    byGroup.forEach((label, members) {
      final ids = members.map((m) => m.id).toSet();
      final outIds = <int>{};
      for (final r in allRequests) {
        if (r.status != LeaveStatus.approved || !ids.contains(r.userId)) continue;
        final start = DateTime.tryParse(r.startDate);
        final end = DateTime.tryParse(r.endDate);
        if (start == null || end == null) continue;
        if (!start.isAfter(horizon) && !end.isBefore(now)) outIds.add(r.userId);
      }
      final total = members.length;
      final available = total - outIds.length;
      rows.add(_CoverageRow(label, available, total));
    });
    rows.sort((a, b) => a.pct.compareTo(b.pct));
    return rows;
  }

  List<LateArrival> get _thisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return lateArrivals.where((l) {
      final d = DateTime.tryParse(l.date);
      return d == null || !d.isBefore(cutoff);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final coverage = _coverage();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(AppColors.rLg), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Coverage · next 14 days', style: AppTheme.cardTitle.copyWith(fontSize: 13.5)),
          const SizedBox(height: 12),
          if (coverage.isEmpty)
            Text('No staff groups to show.', style: AppTheme.bodySub.copyWith(fontSize: 12))
          else ...coverage.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.label, style: AppTheme.bodySm.copyWith(fontSize: 12))),
                Text('${c.available} of ${c.total} available', style: AppTheme.monoXs.copyWith(color: c.color)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
                value: c.total == 0 ? 0 : c.available / c.total,
                minHeight: 5, backgroundColor: context.pal.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(c.color),
              )),
            ]),
          )),
          if (coverage.any((c) => c.available == 0)) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Symbols.warning, size: 14, color: AppColors.coral),
                const SizedBox(width: 8),
                Expanded(child: Text('At least one group has zero cover if the pending requests above are approved.', style: AppTheme.bodySub.copyWith(fontSize: 11))),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(AppColors.rLg), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Late arrivals this week', style: AppTheme.cardTitle.copyWith(fontSize: 13.5)),
          const SizedBox(height: 10),
          if (_thisWeek.isEmpty)
            Text('None reported this week.', style: AppTheme.bodySub.copyWith(fontSize: 12))
          else ..._thisWeek.map((l) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              CircleAvatar(radius: 13, backgroundColor: AppColors.amber.withValues(alpha: 0.18),
                  child: Text(_initialsOf(l.userName ?? '?'), style: AppTheme.bodyStrong.copyWith(fontSize: 10.5, color: AppColors.amber))),
              const SizedBox(width: 10),
              Expanded(child: Text(l.userName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
              Text('${l.date}${l.expectedTime != null ? ' · ${l.expectedTime}' : ''}', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
            ]),
          )),
        ]),
      ),
    ]);
  }
}

class _CoverageRow {
  _CoverageRow(this.label, this.available, this.total);
  final String label;
  final int available;
  final int total;
  double get pct => total == 0 ? 1 : available / total;
  Color get color => available == 0 ? AppColors.coral : (pct < 1 ? AppColors.amber : AppColors.teal);
}

class _OnLeaveTab extends StatelessWidget {
  const _OnLeaveTab({required this.requests, required this.pad});
  final List<LeaveRequest> requests;
  final double pad;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: HrEmptyState(
        icon: HrCategory.leave.icon,
        title: 'Nobody is on leave',
        message: 'No one from the team is currently away.',
      ));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(children: requests.asMap().entries.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: e.key == requests.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Icon(Symbols.event_available, size: 16, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(child: Text(e.value.userName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
            Text('${e.value.displayLabel} · back ${e.value.endDate}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          ]),
        )).toList()),
      ),
    );
  }
}

class _LateArrivalsTab extends StatelessWidget {
  const _LateArrivalsTab({required this.arrivals, required this.pad});
  final List<LateArrival> arrivals;
  final double pad;

  @override
  Widget build(BuildContext context) {
    if (arrivals.isEmpty) {
      return Center(child: HrEmptyState(
        icon: Symbols.schedule,
        title: 'No late-arrival reports',
        message: 'Nothing flagged for review right now.',
      ));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(children: arrivals.asMap().entries.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: e.key == arrivals.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Symbols.schedule, size: 16, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(e.value.userName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(e.value.date, style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
              ]),
              if (e.value.expectedTime != null || e.value.reason != null) ...[
                const SizedBox(height: 3),
                Text(
                  [if (e.value.expectedTime != null) 'ETA ${e.value.expectedTime}', if (e.value.reason != null) e.value.reason!].join(' · '),
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5),
                ),
              ],
            ])),
          ]),
        )).toList()),
      ),
    );
  }
}

class _DecidedTab extends StatelessWidget {
  const _DecidedTab({required this.requests, required this.pad});
  final List<LeaveRequest> requests;
  final double pad;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: HrEmptyState(
        icon: Symbols.fact_check,
        title: 'No decisions yet',
        message: 'Approved and rejected requests will show up here.',
      ));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Column(children: requests.asMap().entries.map((e) {
          final r = e.value;
          final approved = r.status == LeaveStatus.approved;
          final color = approved ? AppColors.teal : AppColors.coral;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: e.key == requests.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(approved ? Symbols.check_circle : Symbols.cancel, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(r.userName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${r.displayLabel} · ${r.startDate} → ${r.endDate}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                ]),
                if (r.rejectionReason != null && r.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(r.rejectionReason!, style: AppTheme.bodySub.copyWith(fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ])),
              Text(approved ? 'Approved' : 'Rejected', style: AppTheme.monoXs.copyWith(color: color)),
              if (r.reviewerName != null) ...[
                const SizedBox(width: 8),
                Text('by ${r.reviewerName}', style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim)),
              ],
            ]),
          );
        }).toList()),
      ),
    );
  }
}
