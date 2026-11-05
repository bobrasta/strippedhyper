import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasDirectorAuthority;
import '../../services/contract_service.dart';
import '../../services/disciplinary_case_service.dart';
import '../../services/payroll_service.dart';
import '../../services/position_change_service.dart';
import '../../services/position_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../theme/hr_category_colors.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/hr_empty_state.dart';
import '../../widgets/common/labeled_field.dart';

// ── Shared shell ─────────────────────────────────────────────────────────────

class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.title, required this.icon, required this.onAdd, required this.child});
  final String title;
  final IconData icon;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pal.surface1,
    child: Container(
      width: 520,
      constraints: const BoxConstraints(maxHeight: 560),
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.teal),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Symbols.add, size: 16), label: const Text('New')),
          GestureDetector(onTap: () => Navigator.of(context).pop(),
              child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
        ]),
        const Divider(height: 24),
        Flexible(child: child),
      ]),
    ),
  );
}

Widget _emptyState(BuildContext context, String title, {IconData icon = Symbols.inbox, String message = ''}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: HrEmptyState(icon: icon, title: title, message: message),
);

// ── Edit HR (personal) Details ──────────────────────────────────────────────

void showEditHrDetailsDialog(
  BuildContext context, StaffMember member, List<StaffMember> staffList, VoidCallback onSaved,
) {
  showDialog(context: context, builder: (_) => _EditHrDetailsDialog(
    member: member,
    staffList: staffList,
    onSaved: onSaved,
  ));
}

class _EditHrDetailsDialog extends StatefulWidget {
  const _EditHrDetailsDialog({required this.member, required this.staffList, required this.onSaved});
  final StaffMember member;
  final List<StaffMember> staffList;
  final VoidCallback onSaved;

  @override
  State<_EditHrDetailsDialog> createState() => _EditHrDetailsDialogState();
}

class _EditHrDetailsDialogState extends State<_EditHrDetailsDialog> {
  late final _nameCtrl  = TextEditingController(text: widget.member.name);
  late final _emailCtrl = TextEditingController(text: widget.member.email ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.member.phone ?? '');
  final _kinNameCtrl   = TextEditingController();
  final _kinPhoneCtrl  = TextEditingController();
  final _kinRelCtrl    = TextEditingController();
  final _nssfCtrl      = TextEditingController();
  final _tinCtrl       = TextEditingController();
  final _nidaCtrl      = TextEditingController();
  final _biometricCtrl = TextEditingController();

  DateTime? _hireDate;
  String? _gender;
  int? _managerId;
  int? _positionId;
  List<Position> _positions = [];
  bool _loadingPositions = true;
  bool _saving = false;
  String? _error;

  // Salary lives on the staff member's active Contract, not on the plain
  // HR-details fields above — shown here read-only, since changing it must
  // go through the Director-approval Salary Adjustment flow, never a
  // direct edit (see SalaryAdjustmentController on the backend).
  Contract? _activeContract;
  bool _loadingContract = true;

  bool get _canEditPosition => hasDirectorAuthority(userRoleNotifier.value);

  @override
  void initState() {
    super.initState();
    _hireDate   = widget.member.hireDate;
    _gender     = widget.member.gender;
    _managerId  = widget.member.managerId;
    _positionId = widget.member.positionId;
    _kinNameCtrl.text    = widget.member.nextOfKinName ?? '';
    _kinPhoneCtrl.text   = widget.member.nextOfKinPhone ?? '';
    _kinRelCtrl.text     = widget.member.nextOfKinRelationship ?? '';
    _nssfCtrl.text       = widget.member.nssfNumber ?? '';
    _tinCtrl.text        = widget.member.tinNumber ?? '';
    _nidaCtrl.text       = widget.member.nidaNumber ?? '';
    _biometricCtrl.text  = widget.member.biometricId ?? '';
    // Stale-while-revalidate — see _ContractsDialogState's own comment for
    // the full reasoning.
    final cachedPositions = PositionService.cachedList;
    if (cachedPositions != null) { _positions = cachedPositions; _loadingPositions = false; }
    final cachedContracts = ContractService.cachedByUserId[widget.member.id];
    if (cachedContracts != null) {
      final active = cachedContracts.where((c) => c.isActive).toList();
      _activeContract = active.isNotEmpty ? active.first : null;
      _loadingContract = false;
    }
    _loadPositions();
    _loadContract();
  }

  Future<void> _loadPositions() async {
    try {
      final list = await PositionService.instance.list();
      if (mounted) setState(() { _positions = list; _loadingPositions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPositions = false);
    }
  }

  Future<void> _loadContract() async {
    try {
      final list = await ContractService.instance.list(widget.member.id);
      final active = list.where((c) => c.isActive).toList();
      if (mounted) setState(() { _activeContract = active.isNotEmpty ? active.first : null; _loadingContract = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingContract = false);
    }
  }

  Future<void> _setInitialSalary() async {
    final salaryCtrl = TextEditingController();
    final salary = await showDialog<int>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Set Initial Salary'),
      content: SizedBox(width: 300, child: LabeledTextField(
        label: 'Base salary (TZS)', controller: salaryCtrl, keyboardType: TextInputType.number,
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(int.tryParse(salaryCtrl.text.trim())),
          child: const Text('Save'),
        ),
      ],
    ));
    if (salary == null) return;
    try {
      await ContractService.instance.create(widget.member.id, {
        'contract_type': 'permanent',
        'start_date': (widget.member.hireDate ?? DateTime.now()).toIso8601String().split('T').first,
        'base_salary': salary,
      });
      _loadContract();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _kinNameCtrl.dispose(); _kinPhoneCtrl.dispose();
    _kinRelCtrl.dispose(); _nssfCtrl.dispose(); _tinCtrl.dispose();
    _nidaCtrl.dispose(); _biometricCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(1990), lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _hireDate = picked);
  }

  Future<void> _addPosition() async {
    final titleCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final created = await showDialog<Position>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('New Position', style: AppTheme.cardTitle),
      content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [
        LabeledTextField(label: 'Title', controller: titleCtrl),
        const SizedBox(height: 10),
        LabeledTextField(label: 'Department (optional)', controller: deptCtrl),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (titleCtrl.text.trim().isEmpty) return;
          try {
            final p = await PositionService.instance.create({
              'title': titleCtrl.text.trim(),
              'department': deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : null,
            });
            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(p);
          } catch (e) {
            if (dialogCtx.mounted) showErrorToast(dialogCtx, e);
          }
        }, child: const Text('Create')),
      ],
    ));
    if (created != null && mounted) {
      setState(() { _positions = [..._positions, created]; _positionId = created.id; });
    }
  }

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      await StaffService.instance.update(widget.member.id, {
        'name':  _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        if (_canEditPosition) 'position_id': _positionId,
        'manager_id':  _managerId,
        'gender':      _gender,
        'hire_date':   _hireDate?.toIso8601String().split('T').first,
        'next_of_kin_name':         _kinNameCtrl.text.trim().isNotEmpty ? _kinNameCtrl.text.trim() : null,
        'next_of_kin_phone':        _kinPhoneCtrl.text.trim().isNotEmpty ? _kinPhoneCtrl.text.trim() : null,
        'next_of_kin_relationship': _kinRelCtrl.text.trim().isNotEmpty ? _kinRelCtrl.text.trim() : null,
        'nssf_number':  _nssfCtrl.text.trim().isNotEmpty ? _nssfCtrl.text.trim() : null,
        'tin_number':   _tinCtrl.text.trim().isNotEmpty ? _tinCtrl.text.trim() : null,
        'nida_number':  _nidaCtrl.text.trim().isNotEmpty ? _nidaCtrl.text.trim() : null,
        'biometric_id': _biometricCtrl.text.trim().isNotEmpty ? _biometricCtrl.text.trim() : null,
      });
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) { setState(() => _saving = false); _error = friendlyError(e); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final managerOptions = widget.staffList.where((s) => s.id != widget.member.id).toList();
    final positionTitle = _positions.where((p) => p.id == _positionId).map((p) => p.title).firstWhere((_) => true, orElse: () => widget.member.positionTitle ?? '—');

    return AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('Edit Staff — ${widget.member.name}', style: AppTheme.cardTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
            LabeledTextField(label: 'Name', controller: _nameCtrl),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: LabeledTextField(label: 'Email', controller: _emailCtrl, keyboardType: TextInputType.emailAddress)),
              const SizedBox(width: 12),
              Expanded(child: LabeledTextField(label: 'Phone', controller: _phoneCtrl, keyboardType: TextInputType.phone)),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _loadingPositions
                  ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  : _canEditPosition
                      ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(child: LabeledDropdown<int?>(
                            label: 'Position',
                            value: _positionId,
                            items: [null, ..._positions.map((p) => p.id)],
                            displayBuilder: (id) => id == null ? 'None' : _positions.firstWhere((p) => p.id == id).title,
                            onChanged: (v) => setState(() => _positionId = v),
                          )),
                          IconButton(onPressed: _addPosition, icon: const Icon(Symbols.add_circle_outline, size: 18), tooltip: 'New position'),
                        ])
                      : LabeledStaticField(label: 'Position', value: positionTitle, hint: 'Only Director/Admin can change this'),
              ),
              const SizedBox(width: 12),
              Expanded(child: LabeledDropdown<String?>(
                label: 'Gender',
                value: _gender,
                items: const [null, 'male', 'female'],
                displayBuilder: (v) => v == null ? 'None' : (v == 'male' ? 'Male' : 'Female'),
                onChanged: (v) => setState(() => _gender = v),
              )),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: LabeledDropdown<int?>(
                label: 'Manager',
                value: _managerId,
                items: [null, ...managerOptions.map((s) => s.id)],
                displayBuilder: (id) => id == null ? 'None' : managerOptions.firstWhere((s) => s.id == id).name,
                onChanged: (v) => setState(() => _managerId = v),
              )),
              const SizedBox(width: 12),
              Expanded(child: LabeledDateField(label: 'Hire date', date: _hireDate, onTap: _pickHireDate)),
            ]),
            const SizedBox(height: 14),
            Text('NEXT OF KIN', style: AppTheme.labelCaps.copyWith(fontSize: 10, color: context.pal.textDim)),
            const SizedBox(height: 8),
            LabeledTextField(label: '', controller: _kinNameCtrl, hint: 'Full name'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: LabeledTextField(label: '', controller: _kinPhoneCtrl, hint: 'Phone')),
              const SizedBox(width: 12),
              Expanded(child: LabeledTextField(label: '', controller: _kinRelCtrl, hint: 'Relationship')),
            ]),
            const SizedBox(height: 16),
            Text('STATUTORY IDS', style: AppTheme.labelCaps.copyWith(fontSize: 10, color: context.pal.textDim)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: LabeledTextField(label: 'NSSF No.', controller: _nssfCtrl)),
              const SizedBox(width: 12),
              Expanded(child: LabeledTextField(label: 'TIN No.', controller: _tinCtrl)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: LabeledTextField(label: 'NIDA No.', controller: _nidaCtrl)),
              const SizedBox(width: 12),
              Expanded(child: LabeledTextField(label: 'Biometric ID', controller: _biometricCtrl)),
            ]),
            const SizedBox(height: 16),
            Text('SALARY', style: AppTheme.labelCaps.copyWith(fontSize: 10, color: context.pal.textDim)),
            const SizedBox(height: 8),
            if (_loadingContract)
              const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Row(children: [
                Expanded(child: Text(
                  _activeContract?.baseSalary != null
                      ? 'TZS ${_activeContract!.baseSalary!.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}'
                      : 'Not set',
                  style: AppTheme.bodySm,
                )),
                TextButton(
                  onPressed: _activeContract != null
                      ? () => showSalaryAdjustmentsDialog(context, widget.member)
                      : _setInitialSalary,
                  child: Text(_activeContract != null ? 'Adjust Salary' : 'Set Initial Salary'),
                ),
              ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Contracts ────────────────────────────────────────────────────────────────

void showContractsDialog(BuildContext context, StaffMember member) {
  showDialog(context: context, builder: (_) => _ContractsDialog(member: member));
}

class _ContractsDialog extends StatefulWidget {
  const _ContractsDialog({required this.member});
  final StaffMember member;

  @override
  State<_ContractsDialog> createState() => _ContractsDialogState();
}

class _ContractsDialogState extends State<_ContractsDialog> {
  List<Contract> _contracts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: this dialog is often opened right after the
    // Directory tab's own background fetch for the same staff member has
    // already populated this cache — show it immediately instead of
    // blanking to a spinner. See MachineService's own doc comment for the
    // full reasoning.
    final cached = ContractService.cachedByUserId[widget.member.id];
    if (cached != null) { _contracts = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_contracts.isEmpty) _loading = true;
    });
    try {
      final list = await ContractService.instance.list(widget.member.id);
      if (mounted) setState(() { _contracts = list; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showErrorToast(context, e); }
    }
  }

  Future<void> _newContract() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewContractDialog(userId: widget.member.id));
    if (ok == true) _load();
  }

  Future<void> _renew(Contract c) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewContractDialog(userId: widget.member.id, renewingContractId: c.id));
    if (ok == true) _load();
  }

  Future<void> _end(Contract c) async {
    try {
      await ContractService.instance.end(c.id);
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _resign(Contract c) async {
    final reasonCtrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('Mark Resigned', style: AppTheme.cardTitle),
      content: SizedBox(width: 320, child: LabeledTextField(label: 'Reason (optional)', controller: reasonCtrl)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Confirm')),
      ],
    ));
    if (go != true) return;
    try {
      await ContractService.instance.resign(c.id,
          resignationDate: DateTime.now().toIso8601String().split('T').first,
          reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null);
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _addAllowance(Contract c) async {
    final typeCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('Add Allowance', style: AppTheme.cardTitle),
      content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [
        LabeledTextField(label: 'Type (e.g. Housing)', controller: typeCtrl),
        const SizedBox(height: 10),
        LabeledTextField(label: 'Amount (TZS)', controller: amountCtrl, keyboardType: TextInputType.number),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Add')),
      ],
    ));
    if (go != true) return;
    final amount = int.tryParse(amountCtrl.text.trim());
    if (typeCtrl.text.trim().isEmpty || amount == null) return;
    try {
      await ContractService.instance.addAllowance(c.id, {
        'type': typeCtrl.text.trim(), 'amount': amount,
        'effective_date': DateTime.now().toIso8601String().split('T').first,
      });
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Color _statusColor(String s) => switch (s) {
    'active'    => AppColors.teal,
    'ended'     => AppColors.textMute,
    'resigned'  => AppColors.coral,
    _           => AppColors.textMute,
  };

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'Contracts — ${widget.member.name}',
    icon: Symbols.description,
    onAdd: _newContract,
    child: _loading
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _contracts.isEmpty
            ? _emptyState(context, 'No contracts yet', icon: HrCategory.contracts.icon, message: 'Add one to start tracking employment terms.')
            : SingleChildScrollView(
                child: Column(children: _contracts.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(c.contractType == 'permanent' ? 'Permanent' : 'Fixed-term', style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _statusColor(c.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text(c.status, style: AppTheme.monoXs.copyWith(color: _statusColor(c.status), fontSize: 10)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${c.startDate} → ${c.endDate ?? 'ongoing'}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    if (c.probationEndDate != null)
                      Text('Probation until ${c.probationEndDate}', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                    if (c.baseSalary != null)
                      Text('Base salary: ${c.baseSalary}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    if (c.allowances.isNotEmpty)
                      ...c.allowances.map((a) => Text('  + ${a.type}: ${a.amount}', style: AppTheme.bodySub.copyWith(fontSize: 11))),
                    if (c.isActive) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        TextButton(onPressed: () => _addAllowance(c), child: const Text('Add Allowance')),
                        TextButton(onPressed: () => _renew(c), child: const Text('Renew')),
                        TextButton(onPressed: () => _end(c), child: const Text('End')),
                        TextButton(onPressed: () => _resign(c), child: Text('Resign', style: TextStyle(color: AppColors.coral))),
                      ]),
                    ],
                  ]),
                )).toList()),
              ),
  );
}

class _NewContractDialog extends StatefulWidget {
  const _NewContractDialog({required this.userId, this.renewingContractId});
  final int userId;
  final int? renewingContractId;

  @override
  State<_NewContractDialog> createState() => _NewContractDialogState();
}

class _NewContractDialogState extends State<_NewContractDialog> {
  String _type = 'permanent';
  DateTime _start = DateTime.now();
  DateTime? _end;
  final _salaryCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(context: context, initialDate: isStart ? _start : (_end ?? _start),
        firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() { if (isStart) _start = picked; else _end = picked; });
  }

  Future<void> _save() async {
    if (_type == 'fixed_term' && _end == null) { setState(() => _error = 'Fixed-term contracts require an end date.'); return; }
    setState(() { _saving = true; _error = null; });
    final payload = {
      'contract_type': _type,
      'start_date': _start.toIso8601String().split('T').first,
      'end_date': _end?.toIso8601String().split('T').first,
      'base_salary': int.tryParse(_salaryCtrl.text.trim()),
    };
    try {
      if (widget.renewingContractId != null) {
        await ContractService.instance.renew(widget.renewingContractId!, payload);
      } else {
        await ContractService.instance.create(widget.userId, payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text(widget.renewingContractId != null ? 'Renew Contract' : 'New Contract', style: AppTheme.cardTitle),
    content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      LabeledDropdown<String>(
        label: 'Type',
        value: _type,
        items: const ['permanent', 'fixed_term'],
        displayBuilder: (v) => v == 'permanent' ? 'Permanent' : 'Fixed-term',
        onChanged: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: LabeledDateField(label: 'Start date', date: _start, onTap: () => _pickDate(true))),
        if (_type == 'fixed_term') ...[
          const SizedBox(width: 12),
          Expanded(child: LabeledDateField(label: 'End date', date: _end, onTap: () => _pickDate(false))),
        ],
      ]),
      const SizedBox(height: 10),
      LabeledTextField(label: 'Base salary (TZS, optional)', controller: _salaryCtrl, keyboardType: TextInputType.number),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
    ],
  );
}

// ── Disciplinary Cases ───────────────────────────────────────────────────────

void showDisciplinaryCasesDialog(BuildContext context, StaffMember member) {
  showDialog(context: context, builder: (_) => _DisciplinaryCasesDialog(member: member));
}

class _DisciplinaryCasesDialog extends StatefulWidget {
  const _DisciplinaryCasesDialog({required this.member});
  final StaffMember member;

  @override
  State<_DisciplinaryCasesDialog> createState() => _DisciplinaryCasesDialogState();
}

class _DisciplinaryCasesDialogState extends State<_DisciplinaryCasesDialog> {
  List<DisciplinaryCase> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — see _ContractsDialogState's own comment for
    // the full reasoning.
    final cached = DisciplinaryCaseService.cachedByUserId[widget.member.id];
    if (cached != null) { _cases = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_cases.isEmpty) _loading = true;
    });
    try {
      final list = await DisciplinaryCaseService.instance.list(widget.member.id);
      if (mounted) setState(() { _cases = list; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showErrorToast(context, e); }
    }
  }

  Future<void> _newCase() async {
    final descCtrl = TextEditingController();
    DateTime date = DateTime.now();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('New Disciplinary Case', style: AppTheme.cardTitle),
        content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, children: [
          LabeledDateField(label: 'Incident date', date: date, onTap: () async {
            final picked = await showDatePicker(context: dialogCtx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) setDialogState(() => date = picked);
          }),
          const SizedBox(height: 10),
          LabeledTextField(label: 'Description', controller: descCtrl, maxLines: 3),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Create')),
        ],
      ),
    ));
    if (go != true || descCtrl.text.trim().isEmpty) return;
    try {
      await DisciplinaryCaseService.instance.create(widget.member.id, {
        'incident_date': date.toIso8601String().split('T').first,
        'description': descCtrl.text.trim(),
      });
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _addNote(DisciplinaryCase c) async {
    final ctrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text('Add Note', style: AppTheme.cardTitle),
      content: SizedBox(width: 320, child: LabeledTextField(label: 'Note', controller: ctrl, maxLines: 3)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Add')),
      ],
    ));
    if (go != true || ctrl.text.trim().isEmpty) return;
    try {
      await DisciplinaryCaseService.instance.addNote(c.id, ctrl.text.trim());
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _advance(DisciplinaryCase c) async {
    String? actionTaken;
    if (c.nextStage == 'action_taken') {
      final ctrl = TextEditingController();
      final go = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('Record Action Taken', style: AppTheme.cardTitle),
        content: SizedBox(width: 320, child: LabeledTextField(label: 'Action', controller: ctrl, hint: 'e.g. Pay deduction, suspension')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Confirm')),
        ],
      ));
      if (go != true) return;
      actionTaken = ctrl.text.trim();
    }
    try {
      await DisciplinaryCaseService.instance.advance(c.id, actionTaken: actionTaken);
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _close(DisciplinaryCase c) async {
    try {
      await DisciplinaryCaseService.instance.close(c.id);
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'Disciplinary Cases — ${widget.member.name}',
    icon: Symbols.gavel,
    onAdd: _newCase,
    child: _loading
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _cases.isEmpty
            ? _emptyState(context, 'No disciplinary cases', icon: HrCategory.discipline.icon, message: 'Nothing on record — that\'s a good thing.')
            : SingleChildScrollView(
                child: Column(children: _cases.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c.stageLabel, style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: (c.status == 'open' ? AppColors.amber : AppColors.textMute).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(c.status, style: AppTheme.monoXs.copyWith(
                            color: c.status == 'open' ? AppColors.amber : AppColors.textMute, fontSize: 10)),
                      ),
                    ]),
                    Text(c.incidentDate, style: AppTheme.bodySub.copyWith(fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(c.description, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                    if (c.actionTaken != null) Text('Action: ${c.actionTaken}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    if (c.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...c.notes.map((n) => Padding(padding: const EdgeInsets.only(bottom: 2),
                          child: Text('• ${n.note} (${n.createdBy ?? '—'})', style: AppTheme.bodySub.copyWith(fontSize: 11)))),
                    ],
                    if (c.status == 'open') ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        TextButton(onPressed: () => _addNote(c), child: const Text('Add Note')),
                        if (c.nextStage != null)
                          TextButton(onPressed: () => _advance(c), child: Text('Advance to ${DisciplinaryCase.stageLabels[c.nextStage] ?? c.nextStage}')),
                        TextButton(onPressed: () => _close(c), child: Text('Close', style: TextStyle(color: AppColors.coral))),
                      ]),
                    ],
                  ]),
                )).toList()),
              ),
  );
}

// ── Career Progression ───────────────────────────────────────────────────────

void showCareerProgressionDialog(BuildContext context, StaffMember member) {
  showDialog(context: context, builder: (_) => _CareerProgressionDialog(member: member));
}

class _CareerProgressionDialog extends StatefulWidget {
  const _CareerProgressionDialog({required this.member});
  final StaffMember member;

  @override
  State<_CareerProgressionDialog> createState() => _CareerProgressionDialogState();
}

class _CareerProgressionDialogState extends State<_CareerProgressionDialog> {
  List<PositionChange> _changes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — see _ContractsDialogState's own comment for
    // the full reasoning.
    final cached = PositionChangeService.cachedByUserId[widget.member.id];
    if (cached != null) { _changes = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_changes.isEmpty) _loading = true;
    });
    try {
      final list = await PositionChangeService.instance.list(widget.member.id);
      if (mounted) setState(() { _changes = list; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showErrorToast(context, e); }
    }
  }

  Future<void> _newChange() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewPositionChangeDialog(userId: widget.member.id));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'Career Progression — ${widget.member.name}',
    icon: Symbols.trending_up,
    onAdd: _newChange,
    child: _loading
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _changes.isEmpty
            ? _emptyState(context, 'No position changes recorded', icon: Symbols.trending_up, message: 'Promotions, demotions, and lateral moves will show up here.')
            : SingleChildScrollView(
                child: Column(children: _changes.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(switch (c.changeType) {
                      'promotion' => Symbols.arrow_upward,
                      'demotion'  => Symbols.arrow_downward,
                      _           => Symbols.swap_horiz,
                    }, size: 15, color: c.changeType == 'promotion' ? AppColors.teal : c.changeType == 'demotion' ? AppColors.coral : context.pal.textDim),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c.fromPositionTitle ?? '—'} → ${c.toPositionTitle ?? '—'}', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                      Text('${c.effectiveDate} · approved by ${c.approvedByName ?? '—'}', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                      if (c.reason != null) Text(c.reason!, style: AppTheme.bodySub.copyWith(fontSize: 11)),
                    ])),
                  ]),
                )).toList()),
              ),
  );
}

class _NewPositionChangeDialog extends StatefulWidget {
  const _NewPositionChangeDialog({required this.userId});
  final int userId;

  @override
  State<_NewPositionChangeDialog> createState() => _NewPositionChangeDialogState();
}

class _NewPositionChangeDialogState extends State<_NewPositionChangeDialog> {
  List<Position> _positions = [];
  int? _toPositionId;
  String _changeType = 'promotion';
  DateTime _effectiveDate = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — see _ContractsDialogState's own comment for
    // the full reasoning.
    final cached = PositionService.cachedList;
    if (cached != null) { _positions = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_positions.isEmpty) _loading = true;
    });
    try {
      final list = await PositionService.instance.list();
      if (mounted) setState(() { _positions = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_toPositionId == null) { setState(() => _error = 'Select a position.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await PositionChangeService.instance.create(widget.userId, {
        'to_position_id': _toPositionId,
        'change_type': _changeType,
        'effective_date': _effectiveDate.toIso8601String().split('T').first,
        'reason': _reasonCtrl.text.trim().isNotEmpty ? _reasonCtrl.text.trim() : null,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('New Position Change', style: AppTheme.cardTitle),
    content: SizedBox(width: 340, child: _loading
        ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
            LabeledDropdown<int?>(
              label: 'New position',
              value: _toPositionId,
              items: [null, ..._positions.map((p) => p.id)],
              displayBuilder: (id) => id == null ? 'Select…' : _positions.firstWhere((p) => p.id == id).title,
              onChanged: (v) => setState(() => _toPositionId = v),
            ),
            const SizedBox(height: 12),
            LabeledDropdown<String>(
              label: 'Type',
              value: _changeType,
              items: const ['promotion', 'demotion', 'lateral'],
              displayBuilder: (v) => switch (v) { 'promotion' => 'Promotion', 'demotion' => 'Demotion', _ => 'Lateral move' },
              onChanged: (v) => setState(() => _changeType = v),
            ),
            const SizedBox(height: 12),
            LabeledDateField(
              label: 'Effective date',
              date: _effectiveDate,
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _effectiveDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (picked != null) setState(() => _effectiveDate = picked);
              },
            ),
            const SizedBox(height: 12),
            LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl),
          ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
    ],
  );
}

// ── Salary Adjustments ───────────────────────────────────────────────────────
//
// Accountant proposes a raise/reduction (status: pending) — it does NOT
// touch the contract's base_salary until a Director approves it. Mirrors
// the finance-approval segregation-of-duty pattern (initiate ≠ approve),
// see SalaryAdjustmentController on the backend.

void showSalaryAdjustmentsDialog(BuildContext context, StaffMember member) {
  showDialog(context: context, builder: (_) => _SalaryAdjustmentsDialog(member: member));
}

class _SalaryAdjustmentsDialog extends StatefulWidget {
  const _SalaryAdjustmentsDialog({required this.member});
  final StaffMember member;

  @override
  State<_SalaryAdjustmentsDialog> createState() => _SalaryAdjustmentsDialogState();
}

class _SalaryAdjustmentsDialogState extends State<_SalaryAdjustmentsDialog> {
  List<SalaryAdjustment> _adjustments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — see _ContractsDialogState's own comment for
    // the full reasoning.
    final cached = PayrollService.cachedSalaryAdjustments[widget.member.id];
    if (cached != null) { _adjustments = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_adjustments.isEmpty) _loading = true;
    });
    try {
      final list = await PayrollService.instance.salaryAdjustments(widget.member.id);
      if (mounted) setState(() { _adjustments = list; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showErrorToast(context, e); }
    }
  }

  Future<void> _propose() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NewSalaryAdjustmentDialog(userId: widget.member.id));
    if (ok == true) _load();
  }

  Future<void> _approve(SalaryAdjustment a) async {
    try {
      await PayrollService.instance.approveSalaryAdjustment(widget.member.id, a.id);
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Color _statusColor(String s) => switch (s) {
    'approved' => AppColors.teal,
    'pending'  => AppColors.amber,
    _          => AppColors.textMute,
  };

  String _money(int n) => 'TZS ${n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) => _DialogShell(
    title: 'Salary — ${widget.member.name}',
    icon: Symbols.payments,
    onAdd: _propose,
    child: _loading
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _adjustments.isEmpty
            ? _emptyState(context, 'No salary adjustments yet', icon: Symbols.payments, message: 'Propose a raise to start tracking pay changes.')
            : SingleChildScrollView(
                child: Column(children: _adjustments.map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(_money(a.newSalary), style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                      if (a.previousSalary != null) ...[
                        const SizedBox(width: 6),
                        Text('(from ${_money(a.previousSalary!)})', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _statusColor(a.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text(a.status, style: AppTheme.monoXs.copyWith(color: _statusColor(a.status), fontSize: 10)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('Effective ${a.effectiveDate}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    if (a.reason != null && a.reason!.isNotEmpty)
                      Text(a.reason!, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    if (a.createdByName != null)
                      Text('Proposed by ${a.createdByName}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                    if (a.status == 'approved' && a.approvedByName != null)
                      Text('Approved by ${a.approvedByName}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                    if (a.status == 'pending') ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () => _approve(a), child: const Text('Approve')),
                      ),
                    ],
                  ]),
                )).toList()),
              ),
  );
}

class _NewSalaryAdjustmentDialog extends StatefulWidget {
  const _NewSalaryAdjustmentDialog({required this.userId});
  final int userId;

  @override
  State<_NewSalaryAdjustmentDialog> createState() => _NewSalaryAdjustmentDialogState();
}

class _NewSalaryAdjustmentDialogState extends State<_NewSalaryAdjustmentDialog> {
  DateTime _effectiveDate = DateTime.now();
  final _salaryCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final salary = int.tryParse(_salaryCtrl.text.trim());
    if (salary == null) { setState(() => _error = 'Enter a valid new salary.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await PayrollService.instance.addSalaryAdjustment(widget.userId, {
        'new_salary': salary,
        'reason': _reasonCtrl.text.trim().isNotEmpty ? _reasonCtrl.text.trim() : null,
        'effective_date': _effectiveDate.toIso8601String().split('T').first,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.pal.surface1,
    title: Text('Propose Salary Adjustment', style: AppTheme.cardTitle),
    content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      LabeledTextField(label: 'New salary (TZS)', controller: _salaryCtrl, keyboardType: TextInputType.number),
      const SizedBox(height: 12),
      LabeledDateField(
        label: 'Effective date',
        date: _effectiveDate,
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: _effectiveDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) setState(() => _effectiveDate = picked);
        },
      ),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl),
      const SizedBox(height: 8),
      Text(
        'This needs Director approval before it changes the active contract\'s base salary.',
        style: AppTheme.bodySub.copyWith(fontSize: 11),
      ),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Propose')),
    ],
  );
}
