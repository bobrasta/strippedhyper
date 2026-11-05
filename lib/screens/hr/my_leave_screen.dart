import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/leave_request.dart';
import '../../services/late_arrival_service.dart';
import '../../services/leave_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

class MyLeaveScreen extends StatefulWidget {
  const MyLeaveScreen({super.key});

  @override
  State<MyLeaveScreen> createState() => _MyLeaveScreenState();
}

class _MyLeaveScreenState extends State<MyLeaveScreen> {
  List<LeaveRequest> _requests = [];
  List<LeaveBalanceEntry> _balances = [];
  bool    _loading = true;
  String? _error;
  bool    _showRequestDialog = false;
  bool    _showLateDialog = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning.
    final cachedMine = LeaveService.cachedMineList;
    final cachedBalances = LeaveService.cachedDefaultBalances;
    if (cachedMine != null) _requests = cachedMine;
    if (cachedBalances != null) _balances = cachedBalances;
    if (cachedMine != null || cachedBalances != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_requests.isEmpty && _balances.isEmpty) _loading = true;
      _error = null;
    });
    try {
      // Always scope to the logged-in user's own requests — mine:true forces
      // this server-side even for HR/admin callers, regardless of whether
      // userIdNotifier happens to be populated (hr_approval_screen.dart is
      // the intentional company-wide view for those roles).
      final results = await Future.wait([
        LeaveService.instance.list(mine: true),
        LeaveService.instance.balances(),
      ]);
      if (mounted) setState(() {
        _requests = results[0] as List<LeaveRequest>;
        _balances = results[1] as List<LeaveBalanceEntry>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _cancel(LeaveRequest r) async {
    try {
      await LeaveService.instance.cancel(r.id);
      if (mounted) { showSuccessToast(context, 'Leave request cancelled.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 28.0;
        return RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(pad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (ctx, cst) {
                final narrow = cst.maxWidth < 560;
                final titleBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('My Leave', style: AppTheme.pageTitle),
                  const SizedBox(height: 4),
                  Text('Request time off or let HR know you\'re running late', style: AppTheme.bodySub),
                ]);
                final actions = Wrap(spacing: 8, runSpacing: 8, children: [
                  AppButton(label: 'Running Late', icon: Symbols.schedule, variant: BtnVariant.ghost,
                      onPressed: () => setState(() => _showLateDialog = true)),
                  AppButton(label: 'Request Leave', icon: Symbols.add, variant: BtnVariant.primary,
                      onPressed: () => setState(() => _showRequestDialog = true)),
                ]);
                if (narrow) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [titleBlock, const SizedBox(height: 12), actions]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [titleBlock, const Spacer(), actions]);
              }),
              const SizedBox(height: 24),
              if (!_loading && _error == null && _balances.isNotEmpty) ...[
                _BalanceSummaryRow(balances: _balances),
                const SizedBox(height: 20),
              ],
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 48), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_error != null && _requests.isEmpty)
                ErrorView(message: _error!, onRetry: _load)
              else if (_requests.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No leave requests yet', style: TextStyle(color: context.pal.textMute))))
              else
                Column(children: _requests.map((r) => _LeaveCard(request: r, onCancel: () => _cancel(r))).toList()),
            ]),
          ),
        );
      }),
      if (_showRequestDialog)
        _RequestLeaveDialog(
          onClose: () => setState(() => _showRequestDialog = false),
          onSaved: () { setState(() => _showRequestDialog = false); _load(); },
        ),
      if (_showLateDialog)
        _RunningLateDialog(
          onClose: () => setState(() => _showLateDialog = false),
        ),
    ]);
  }
}

class _BalanceSummaryRow extends StatelessWidget {
  const _BalanceSummaryRow({required this.balances});
  final List<LeaveBalanceEntry> balances;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: balances.map((b) => Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(b.leaveTypeLabel, style: AppTheme.bodySub.copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Text('${b.remainingDays.toStringAsFixed(b.remainingDays.truncateToDouble() == b.remainingDays ? 0 : 1)} left',
            style: AppTheme.bodyStrong.copyWith(fontSize: 14)),
        Text('of ${b.allocatedDays.toStringAsFixed(0)} days', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
      ]),
    )).toList()),
  );
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.request, required this.onCancel});
  final LeaveRequest request;
  final VoidCallback onCancel;

  Color get _statusColor => switch (request.status) {
    LeaveStatus.pending   => AppColors.amber,
    LeaveStatus.approved  => AppColors.teal,
    LeaveStatus.rejected  => AppColors.coral,
    LeaveStatus.cancelled => AppColors.textMute,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.event, size: 16, color: _statusColor),
        const SizedBox(width: 8),
        Expanded(child: Text(request.displayLabel, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text(request.status.label, style: AppTheme.bodySub.copyWith(color: _statusColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      Text('${request.startDate} — ${request.endDate}  ·  ${request.daysCount} day(s)', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
      if (request.reason != null && request.reason!.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(request.reason!, style: AppTheme.bodySub.copyWith(fontSize: 12)),
      ],
      if (request.status == LeaveStatus.rejected && request.rejectionReason != null) ...[
        const SizedBox(height: 6),
        Text('Reason: ${request.rejectionReason}', style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12)),
      ],
      if (request.canCancel) ...[
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: GestureDetector(
          onTap: onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(6)),
            child: Text('Cancel', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          ),
        )),
      ],
    ]),
  );
}

// ── Request Leave dialog ─────────────────────────────────────────────────────

class _RequestLeaveDialog extends StatefulWidget {
  const _RequestLeaveDialog({required this.onClose, required this.onSaved});
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_RequestLeaveDialog> createState() => _RequestLeaveDialogState();
}

class _RequestLeaveDialogState extends State<_RequestLeaveDialog> {
  List<LeaveTypeCatalogEntry> _types = [];
  LeaveTypeCatalogEntry? _type;
  bool _loadingTypes = true;
  DateTime  _start = DateTime.now();
  DateTime  _end   = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool    _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      // Public Holiday populates itself from the calendar — not requestable.
      final list = (await LeaveService.instance.types(activeOnly: true))
          .where((t) => !t.autoFromCalendar).toList();
      if (mounted) setState(() {
        _types = list;
        _type = list.isNotEmpty ? list.first : null;
        _loadingTypes = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loadingTypes = false; });
    }
  }

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context, initialDate: isStart ? _start : _end,
      firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) { _start = picked; if (_end.isBefore(_start)) _end = picked; }
        else { _end = picked; }
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _type == null) return;
    if (_end.isBefore(_start)) { setState(() => _error = 'End date must be on or after start date.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await LeaveService.instance.create({
        'leave_type_id': _type!.id, 'start_date': _iso(_start), 'end_date': _iso(_end),
        'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 460,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.event, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Request Leave', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Leave type', style: AppTheme.fieldLabel),
                  const SizedBox(height: 6),
                  DropdownFieldBox<LeaveTypeCatalogEntry>(
                    value: _loadingTypes ? null : _type,
                    enabled: !_loadingTypes,
                    hint: _loadingTypes ? 'Loading…' : null,
                    items: _loadingTypes ? const [] : _types.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  if (_type?.requiresManualDays == true) ...[
                    const SizedBox(height: 6),
                    Text('The final day count for ${_type!.label} leave is set by the approver, not the date range below.',
                        style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim)),
                  ],
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _DateField(label: 'Start Date', date: _start, onTap: () => _pickDate(true))),
                  const SizedBox(width: 14),
                  Expanded(child: _DateField(label: 'End Date', date: _end, onTap: () => _pickDate(false))),
                ]),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${_end.difference(_start).inDays + 1} day(s)', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                )),
                const SizedBox(height: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl, maxLines: 3, hint: 'Any details HR should know—'),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Submit Request', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LabeledDateField(label: label, date: date, onTap: onTap);
}

// ── Running Late dialog ──────────────────────────────────────────────────────

class _RunningLateDialog extends StatefulWidget {
  const _RunningLateDialog({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_RunningLateDialog> createState() => _RunningLateDialogState();
}

class _RunningLateDialogState extends State<_RunningLateDialog> {
  final _timeCtrl   = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _timeCtrl.dispose(); _reasonCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await LateArrivalService.instance.report(
        expectedTime: _timeCtrl.text.trim().isEmpty ? null : _timeCtrl.text.trim(),
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      if (mounted) { showSuccessToast(context, 'HR has been notified.'); widget.onClose(); }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.schedule, size: 18, color: AppColors.amber),
                const SizedBox(width: 10),
                Expanded(child: Text('Running Late', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabeledTextField(label: 'Expected arrival (optional)', controller: _timeCtrl, hint: 'e.g. 9:30am'),
                ]),
                const SizedBox(height: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl, maxLines: 3, hint: 'e.g. Traffic, appointment—'),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Notify HR', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}
