import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasFinalMoneyAuthority;
import '../../models/delegation.dart';
import '../../services/delegation_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';

// Lets a Director temporarily hand their approval authority (finance,
// payroll, credit notes, vendor bills, salary adjustments — everywhere
// hasDirectorAuthority() gates an approval) to someone else for a defined
// window, with a reason and a revoke path — an audit trail for "why did
// someone other than the Director approve this," not a silent permission
// reassignment. See DelegationController on the backend.
class DelegationsScreen extends StatefulWidget {
  const DelegationsScreen({super.key});

  @override
  State<DelegationsScreen> createState() => _DelegationsScreenState();
}

class _DelegationsScreenState extends State<DelegationsScreen> {
  List<Delegation> _delegations = [];
  List<StaffMember> _staff = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known data immediately, then
    // quietly refresh — see MachineService's own doc comment for the full
    // reasoning. Staff seeds from StaffService's own notifier-based cache
    // (a different pattern from the static-field one below, per that
    // service's own doc comment).
    final cachedDelegations = DelegationService.cachedList;
    final cachedStaff = StaffService.instance.staffNotifier.value;
    if (cachedDelegations != null) _delegations = cachedDelegations;
    if (cachedStaff.isNotEmpty) _staff = cachedStaff;
    if (cachedDelegations != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_delegations.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([DelegationService.instance.list(), StaffService.instance.list()]);
      if (!mounted) return;
      setState(() {
        _delegations = results[0] as List<Delegation>;
        _staff = results[1] as List<StaffMember>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _newDelegation() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewDelegationDialog(staff: _staff));
    if (ok == true) _load();
  }

  Future<void> _revoke(Delegation d) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Revoke delegation'),
      content: Text('Revoke ${d.delegateName ?? 'this delegate'}\'s approval authority now?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Revoke')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await DelegationService.instance.revoke(d.id);
      if (mounted) { showSuccessToast(context, 'Delegation revoked.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delegations', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('Temporarily hand your Director approval authority to someone else', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            // Only the Director's own seat — the CTO's admin tier can view
            // delegations but not create or revoke them (DelegationController).
            if (hasFinalMoneyAuthority(userRoleNotifier.value))
              FilledButton.icon(onPressed: _newDelegation, icon: const Icon(Symbols.add, size: 16), label: const Text('New delegation')),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null && _delegations.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _delegations.isEmpty
                      ? Center(child: Text('No delegations yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
                      : SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                          child: Column(children: _delegations.map((d) => _delegationCard(context, d)).toList()),
                        ),
        ),
      ]);
    });
  }

  Widget _delegationCard(BuildContext context, Delegation d) {
    final revoked = d.revokedAt != null;
    final standingBy = !revoked && !d.isActive && d.inPeriod && d.standbyForId != null;
    final status = revoked ? 'Revoked' : (d.isActive ? 'Active' : standingBy ? 'On standby'
        : (d.startsAt != null && d.startsAt!.isAfter(DateTime.now()) ? 'Scheduled' : 'Expired'));
    final statusColor = revoked ? context.pal.textMute : (d.isActive ? AppColors.teal
        : (status == 'Scheduled' || standingBy ? AppColors.amber : context.pal.textMute));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.badge, size: 15, color: statusColor),
          const SizedBox(width: 8),
          Expanded(child: Text(d.delegateName ?? 'Unknown', style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
            child: Text(status, style: AppTheme.monoXs.copyWith(fontSize: 10, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '${d.startsAt != null ? formatDate(d.startsAt!) : '—'} → ${d.endsAt != null ? formatDate(d.endsAt!) : '—'}',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5),
        ),
        if (d.standbyForName != null)
          Text(d.isActive
              ? 'In effect — ${d.standbyForName} is on leave'
              : 'Only while ${d.standbyForName} is not around (on approved leave)',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: d.isActive ? AppColors.teal : AppColors.amber)),
        if (d.delegatorName != null)
          Text('Delegated by ${d.delegatorName}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
        if (d.reason != null && d.reason!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(d.reason!, style: AppTheme.bodySm.copyWith(fontSize: 12)),
        ],
        if (revoked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Revoked${d.revokedByName != null ? ' by ${d.revokedByName}' : ''}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
          ),
        if (!revoked && hasFinalMoneyAuthority(userRoleNotifier.value)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _revoke(d), child: Text('Revoke', style: TextStyle(color: AppColors.coral))),
          ),
        ],
      ]),
    );
  }
}

class _NewDelegationDialog extends StatefulWidget {
  const _NewDelegationDialog({required this.staff});
  final List<StaffMember> staff;

  @override
  State<_NewDelegationDialog> createState() => _NewDelegationDialogState();
}

class _NewDelegationDialogState extends State<_NewDelegationDialog> {
  int? _delegateId;
  /// Only while this person is away; defaults to the CTO when delegating to
  /// anyone else ("Gabriel can only stand as Director if Sharif is not around").
  int? _standbyForId;
  DateTime _startsAt = DateTime.now();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 7));
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context, initialDate: isStart ? _startsAt : _endsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100),
    );
    if (picked != null) setState(() { if (isStart) _startsAt = picked; else _endsAt = picked; });
  }

  Future<void> _save() async {
    if (_delegateId == null) { setState(() => _error = 'Choose who you\'re delegating to.'); return; }
    if (!_endsAt.isAfter(_startsAt)) { setState(() => _error = 'End must be after start.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await DelegationService.instance.create({
        'delegate_id': _delegateId,
        'standby_for_id': _standbyForId,
        'reason': _reasonCtrl.text.trim().isNotEmpty ? _reasonCtrl.text.trim() : null,
        'starts_at': _startsAt.toIso8601String(),
        'ends_at': _endsAt.toIso8601String(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.bg,
    title: Text('New Delegation', style: AppTheme.cardTitle),
    content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      Text('Delegate to', style: AppTheme.fieldLabel),
      const SizedBox(height: 6),
      DropdownFieldBox<int>(
        value: _delegateId,
        hint: 'Select a staff member',
        items: widget.staff.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
        onChanged: (v) => setState(() {
          _delegateId = v;
          final cto = widget.staff.where((s) => s.role == 'cto').firstOrNull;
          _standbyForId = cto != null && cto.id != v ? cto.id : null;
        }),
      ),
      const SizedBox(height: 12),
      Text('Only while this person is not around', style: AppTheme.fieldLabel),
      const SizedBox(height: 6),
      DropdownFieldBox<int?>(
        value: _standbyForId,
        hint: 'Nobody — always in effect',
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Nobody — always in effect')),
          ...widget.staff.where((s) => s.id != _delegateId).map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
        ],
        onChanged: (v) => setState(() => _standbyForId = v),
      ),
      const SizedBox(height: 4),
      Text('"Not around" means on approved leave covering the day.',
          style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _dateField(context, 'Starts', _startsAt, () => _pickDate(true))),
        const SizedBox(width: 12),
        Expanded(child: _dateField(context, 'Ends', _endsAt, () => _pickDate(false))),
      ]),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl, maxLines: 2, hint: 'e.g. Annual leave 12–19 Sep'),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Delegate')),
    ],
  );

  Widget _dateField(BuildContext context, String label, DateTime date, VoidCallback onTap) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
        alignment: Alignment.centerLeft,
        child: Text(formatDate(date), style: AppTheme.bodySm),
      ),
    ),
  ]);
}
