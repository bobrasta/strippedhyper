// Section 18 · Shipments settings (design 1e). Every default the spec lists
// as unconfirmed (18.7) is visible here, the switchable rules can be turned
// off and status labels relabelled — step ORDER is fixed. Editing is admin
// tier only; everyone who can see shipments can read it.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/shipment.dart';
import '../../services/shipment_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'tender_forms.dart' show ProcDialog;

// Role names are shown in ALL CAPS app-wide.
String _roleLabel(String role) => role.replaceAll('_', ' ').trim().toUpperCase();

class ShipmentSettingsScreen extends StatefulWidget {
  const ShipmentSettingsScreen({super.key, this.embedded = false});
  /// Shown in the shell from the sidebar ("Module Settings") rather than
  /// pushed from the Shipments list — no back button then.
  final bool embedded;
  @override
  State<ShipmentSettingsScreen> createState() => _ShipmentSettingsScreenState();
}

class _ShipmentSettingsScreenState extends State<ShipmentSettingsScreen> {
  ShipmentSettings? _s;
  String? _error;
  bool _permitGate = true;
  bool _docsAtCreation = false;
  Set<int> _confirmed = {};
  List<TextEditingController> _import = [];
  List<TextEditingController> _export = [];
  bool _saving = false;

  // Which import steps carry a rule, shown beside the label.
  static const _ruleFor = {
    1: 'Can\'t move on until all documents are in',
    4: 'Needs the application reference',
    5: 'Needs the issue date',
    6: 'Blocked until the permit is issued (switchable)',
    7: 'Needs the control number',
    8: 'Section 16 fee must be paid',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [..._import, ..._export]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _set(await ShipmentService.instance.settings());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _set(ShipmentSettings s) {
    if (!mounted) return;
    for (final c in [..._import, ..._export]) {
      c.dispose();
    }
    setState(() {
      _s = s;
      _error = null;
      _permitGate = s.permitGate;
      _docsAtCreation = s.docsRequiredAtCreation;
      _confirmed = {...s.confirmed};
      _import = [for (final l in s.importLabels) TextEditingController(text: l)];
      _export = [for (final l in s.exportLabels) TextEditingController(text: l)];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      _set(await ShipmentService.instance.saveSettings({
        'permit_gate': _permitGate,
        'docs_required_at_creation': _docsAtCreation,
        'import_labels': [for (final c in _import) c.text.trim()],
        'export_labels': [for (final c in _export) c.text.trim()],
        'confirmed_assumptions': (_confirmed.toList()..sort()),
      }));
      if (mounted) showSuccessToast(context, 'Shipment settings saved.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _department([Department? d]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _DepartmentDialog(department: d));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = _s;
    Widget body;
    if (s == null) {
      body = _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    } else {
      final edit = s.canEdit;
      final left = Column(children: [_rules(context, edit), const SizedBox(height: 14), _labels(context, edit)]);
      final right = Column(children: [
        _departments(context, s, edit),
        const SizedBox(height: 14),
        _recipients(context, s),
        const SizedBox(height: 14),
        _assumptions(context, s, edit),
      ]);
      body = LayoutBuilder(builder: (context, box) => box.maxWidth < 1000
          ? ListView(padding: const EdgeInsets.all(16), children: [left, const SizedBox(height: 14), right])
          : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 20), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: left), const SizedBox(width: 14), Expanded(child: right)])));
    }

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.embedded)
          Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Shipments')))),
        ProcPageHeader(
          title: 'Shipments settings',
          breadcrumb: const ['Shipments', 'Settings'],
          subtitle: s == null ? null
              : 'Rules, status labels and recipients · ${s.assumptions.length - _confirmed.length} defaults not yet confirmed with Procurement',
          actions: [
            if (s != null && s.canEdit)
              ProcButton(label: _saving ? 'Saving…' : 'Save changes', icon: Symbols.save, tone: ProcTone.green, onPressed: _saving ? null : _save)
            else if (s != null)
              const ProcTag('Read-only · admin edits', tone: ProcTone.violet),
          ],
        ),
        Expanded(child: body),
      ])),
    );
  }

  Widget _rules(BuildContext context, bool edit) {
    final pal = context.pal;
    Widget rule(String name, String note, bool value, ValueChanged<bool>? onChanged, {bool unconfirmed = true}) => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(name, style: AppTheme.bodySm),
            if (unconfirmed) const ProcTag('Unconfirmed', tone: ProcTone.amber, small: true),
          ]),
          const SizedBox(height: 3),
          Text(note, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
    return ProcPanel(title: 'Rules', icon: Symbols.verified_user, iconColor: AppColors.green, child: Column(children: [
      rule('TMDA permit must be issued before documents go to the clearing agent',
          'Blocks step 6 until the permit is issued, with a warning if someone tries to skip.',
          _permitGate, edit ? (v) => setState(() => _permitGate = v) : null),
      rule('All documents required at creation',
          'Off: shipments can be created and flagged Incomplete, documents added as they arrive.',
          _docsAtCreation, edit ? (v) => setState(() => _docsAtCreation = v) : null),
      rule('Going back a status requires a logged reason',
          'Always on, same as corrections elsewhere in the system.', true, null, unconfirmed: false),
      rule('Clearing payment approved by the Director',
          'Always on: the clearing fee is a Section 16 vendor fee, so it follows that chain (receipt → Finance → Director).',
          true, null, unconfirmed: false),
    ]));
  }

  Widget _labels(BuildContext context, bool edit) {
    final pal = context.pal;
    Widget list(List<TextEditingController> cs, Map<int, String> rules) => Column(children: [
      for (var i = 0; i < cs.length; i++) Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Row(children: [
          SizedBox(width: 22, child: Text('${i + 1}', style: procMono(context, size: 10.5))),
          Expanded(child: edit
              ? LabeledTextField(label: '', controller: cs[i])
              : Text(cs[i].text, style: AppTheme.bodySm.copyWith(fontSize: 12))),
          const SizedBox(width: 12),
          SizedBox(width: 170, child: Text(rules[i + 1] ?? '', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim))),
        ]),
      ),
    ]);
    return ProcPanel(
      title: 'Status labels', icon: Symbols.format_list_numbered, iconColor: AppColors.cyan,
      trailing: Text('labels are editable · order is fixed', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 2), child: Text('IMPORT', style: procCaps(context))),
        list(_import, _ruleFor),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 2), child: Text('EXPORT', style: procCaps(context))),
        list(_export, const {2: 'Can\'t move on until all documents are in', 4: 'Needs the signed receipt'}),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _departments(BuildContext context, ShipmentSettings s, bool edit) {
    final pal = context.pal;
    return ProcPanel(
      title: 'Departments', icon: Symbols.apartment, iconColor: AppColors.teal,
      trailing: edit ? TextButton(onPressed: () => _department(), child: const Text('Add', style: TextStyle(fontSize: 11.5))) : null,
      footer: const ProcNote('A shipment tagged to a department notifies its manager, who can also open that department\'s shipments read-only.'),
      child: Column(children: [
        for (final d in s.departments) InkWell(
          onTap: edit ? () => _department(d) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
            child: Row(children: [
              Expanded(child: Text(d.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
              Text(d.managerName ?? 'no head set · fallback list', style: AppTheme.bodySub.copyWith(fontSize: 11,
                  color: d.managerName == null ? AppColors.amber : pal.textMute)),
              if (edit) ...[const SizedBox(width: 6), Icon(Symbols.edit, size: 14, color: pal.textDim)],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _recipients(BuildContext context, ShipmentSettings s) => ProcPanel(
    title: 'Recipients · by role', icon: Symbols.notifications_active, iconColor: AppColors.amber,
    footer: const ProcNote('On creation and every status change: in-app, plus an email copy (sent from the VPS, '
        'from no-reply@hypermed.co.tz). Wording is edited under Notification Wording.'),
    child: Column(children: [
      for (final r in s.leadershipRoles) RecipientRow(initials: _roleLabel(r).substring(0, 2).toUpperCase(), role: _roleLabel(r), tag: 'always'),
      const RecipientRow(initials: 'DM', role: 'Manager of the shipment\'s department', tag: 'per shipment', tagTone: ProcTone.violet),
      RecipientRow(initials: 'FB', role: 'Fallback when no department head',
          name: s.fallbackRoles.map(_roleLabel).join(', '), tag: 'fallback', tagTone: ProcTone.amber),
    ]),
  );

  Widget _assumptions(BuildContext context, ShipmentSettings s, bool edit) {
    final pal = context.pal;
    return ProcPanel(
      title: 'Assumptions to confirm', icon: Symbols.help, iconColor: AppColors.amber,
      trailing: Text('${_confirmed.length} of ${s.assumptions.length} confirmed', style: procMono(context, size: 10.5, color: AppColors.amber)),
      child: Column(children: [
        for (var i = 0; i < s.assumptions.length; i++) Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
          child: Row(children: [
            SizedBox(width: 24, child: Text((i + 1).toString().padLeft(2, '0'), style: procMono(context, size: 10.5))),
            Expanded(child: Text(s.assumptions[i], style: AppTheme.bodySub.copyWith(fontSize: 11.5,
                color: _confirmed.contains(i) ? pal.textDim : pal.textMute))),
            TextButton(
              onPressed: edit ? () => setState(() => _confirmed.contains(i) ? _confirmed.remove(i) : _confirmed.add(i)) : null,
              child: Text(_confirmed.contains(i) ? 'Confirmed' : 'Mark confirmed', style: TextStyle(fontSize: 11,
                  color: _confirmed.contains(i) ? AppColors.green : null)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DepartmentDialog extends StatefulWidget {
  const _DepartmentDialog({this.department});
  final Department? department;
  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  late final _name = TextEditingController(text: widget.department?.name ?? '');
  late int? _manager = widget.department?.managerId;
  List<StaffMember> _staff = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    StaffService.instance.list().then((s) {
      if (mounted) setState(() => _staff = [...s]..sort((a, b) => a.name.compareTo(b.name)));
    }).catchError((Object e) {
      if (mounted) showErrorToast(context, e);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showErrorToast(context, Exception('Enter the department name.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ShipmentService.instance.saveDepartment({'name': _name.text.trim(), 'manager_id': _manager}, id: widget.department?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: widget.department == null ? 'New department' : 'Edit ${widget.department!.name}',
    icon: Symbols.apartment,
    width: 460,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Symbols.save, size: 15), label: Text(_saving ? 'Saving…' : 'Save')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'Department', controller: _name, hint: 'e.g. Microbiology'),
      const SizedBox(height: 12),
      LabeledDropdown<int?>(
        label: 'Manager · notified about this department\'s shipments',
        value: _manager,
        // Keep the saved manager as an option while staff loads (or if
        // they're no longer in the list) — the value must match an item.
        items: [
          null,
          if (_manager != null && !_staff.any((x) => x.id == _manager)) _manager,
          ..._staff.map((x) => x.id),
        ],
        displayBuilder: (id) {
          if (id == null) return 'No head set · use the fallback list';
          final m = _staff.where((x) => x.id == id).firstOrNull;
          return m == null ? (widget.department?.managerName ?? 'Loading…') : m.name;
        },
        onChanged: (v) => setState(() => _manager = v),
      ),
    ]),
  );
}
