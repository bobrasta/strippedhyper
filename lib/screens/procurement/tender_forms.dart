import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/tender.dart';
import '../../services/tender_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/proc_widgets.dart';

// Dialogs for Section 19: tender create/edit, procuring entities, the board
// resolution register, company details and status changes.

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Material-backed dialog shell (TextFields need a Material ancestor).
class ProcDialog extends StatelessWidget {
  const ProcDialog({super.key, required this.title, required this.icon, required this.body, this.actions = const [], this.width = 560});
  final String title;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final double width;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Dialog(
      backgroundColor: pal.surface1,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: pal.borderStrong)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 6),
            child: Row(children: [
              Icon(icon, size: 18, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.bodyStrong)),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Symbols.close, size: 18, color: pal.textDim)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 16), child: body)),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ),
        ]),
      ),
    );
  }
}

Widget formHeading(String t) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 10), child: Text(t, style: AppTheme.bodyStrong));

Widget formRow(List<Widget> children) => LayoutBuilder(builder: (_, box) {
  if (box.maxWidth < 460) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
    ]);
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: children[i])],
    ]),
  );
});

/// Date field with a clear button (dates are optional on tenders).
class OptionalDateField extends StatelessWidget {
  const OptionalDateField({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? hint;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: LabeledDateField(
        label: label, date: value, placeholder: 'Not set',
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(context: context, initialDate: value ?? now,
              firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5));
          if (d != null) onChanged(d);
        },
      )),
      if (value != null) IconButton(tooltip: 'Clear', onPressed: () => onChanged(null),
          icon: Icon(Symbols.close, size: 16, color: context.pal.textDim)),
    ]),
    if (hint != null) Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(hint!, style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim))),
  ]);
}

// ── Tender create / edit ─────────────────────────────────────────────────────

Future<Tender?> showTenderForm(BuildContext context, {Tender? tender}) =>
    showDialog<Tender>(context: context, builder: (_) => _TenderForm(tender: tender));

class _TenderForm extends StatefulWidget {
  const _TenderForm({this.tender});
  final Tender? tender;
  @override
  State<_TenderForm> createState() => _TenderFormState();
}

class _TenderFormState extends State<_TenderForm> {
  late final Tender? t = widget.tender;
  final _c = <String, TextEditingController>{};
  final _d = <String, DateTime?>{};
  late String _type = t?.tenderType ?? 'standard';
  late bool _vatIncl = t?.vatInclusive ?? false;
  late String? _psForm = t?.str('performance_security_form');
  late int? _entityId = t?.entity?.id;
  late int? _resolutionId = t?.boardResolution?['id'] as int?;
  List<ProcuringEntity> _entities = [];
  List<BoardResolution> _resolutions = [];
  bool _saving = false;

  static const _text = ['tender_number', 'contract_number', 'title', 'estimated_value', 'contract_value', 'bid_validity_days',
    'entity_ref', 'our_ref', 'attorney_name', 'attorney_address', 'signatory_name', 'signatory_position', 'notes'];
  static const _dates = ['bid_submission_deadline', 'tender_expiry_date', 'other_tenderer_notified_at', 'award_notified_at',
    'letter_of_acceptance_date', 'contract_signing_deadline', 'delivery_deadline', 'entity_ref_date'];

  @override
  void initState() {
    super.initState();
    for (final k in _text) {
      _c[k] = TextEditingController(text: t?.str(k) ?? '');
    }
    for (final k in _dates) {
      _d[k] = t?.date(k);
    }
    _loadLists();
  }

  Future<void> _loadLists() async {
    try {
      final r = await Future.wait([TenderService.instance.entities(), TenderService.instance.resolutions()]);
      if (!mounted) return;
      setState(() {
        _entities = r[0] as List<ProcuringEntity>;
        _resolutions = r[1] as List<BoardResolution>;
      });
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _newEntity() async {
    final e = await showEntityForm(context);
    if (e == null || !mounted) return;
    setState(() { _entities = [..._entities, e]; _entityId = e.id; });
  }

  Future<void> _newResolution() async {
    final r = await showDialog<BoardResolution>(context: context, builder: (_) => const _ResolutionForm());
    if (r == null || !mounted) return;
    setState(() { _resolutions = [r, ..._resolutions]; _resolutionId = r.id; });
  }

  Future<void> _save() async {
    String? txt(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
    int? num(String k) => parseShillings(_c[k]!.text);
    if (txt('tender_number') == null || txt('title') == null || _entityId == null) {
      showErrorToast(context, Exception('Tender number, title and procuring entity are required.'));
      return;
    }
    final data = <String, dynamic>{
      for (final k in ['tender_number', 'contract_number', 'title', 'entity_ref', 'our_ref', 'attorney_name', 'attorney_address',
        'signatory_name', 'signatory_position', 'notes']) k: txt(k),
      'estimated_value': num('estimated_value'),
      'contract_value': num('contract_value'),
      'bid_validity_days': num('bid_validity_days'),
      for (final k in _dates) k: _d[k] == null ? null : isoDate(_d[k]!),
      'tender_type': _type,
      'vat_inclusive': _vatIncl,
      'performance_security_form': _psForm,
      'procuring_entity_id': _entityId,
      'board_resolution_id': _resolutionId,
    };
    setState(() => _saving = true);
    try {
      final saved = t == null ? await TenderService.instance.create(data) : await TenderService.instance.update(t!.id, data);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _f(String key, String label, {int lines = 1, TextInputType? kb, String? hint}) =>
      LabeledTextField(label: label, controller: _c[key]!, maxLines: lines, keyboardType: kb, hint: hint);

  Widget _date(String key, String label, {String? hint}) =>
      OptionalDateField(label: label, value: _d[key], hint: hint, onChanged: (v) => setState(() => _d[key] = v));

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final loa = _d['letter_of_acceptance_date'];
    return ProcDialog(
      title: t == null ? 'New tender' : 'Edit tender ${t!.tenderNumber}',
      icon: Symbols.gavel,
      width: 720,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Symbols.save, size: 15),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        formHeading('Tender'),
        formRow([_f('tender_number', 'Tender number (as issued)'), _f('contract_number', 'Contract number', hint: 'Can be the same as the tender number')]),
        _f('title', 'Title / description', lines: 2),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: LabeledDropdown<int?>(
            label: 'Procuring entity',
            value: _entities.any((e) => e.id == _entityId) ? _entityId : null,
            items: [null, ..._entities.map((e) => e.id)],
            displayBuilder: (id) => id == null ? 'Select…' : _entities.firstWhere((e) => e.id == id).name,
            onChanged: (v) => setState(() => _entityId = v),
          )),
          const SizedBox(width: 8),
          ProcButton(label: 'New', icon: Symbols.add, onPressed: _newEntity),
        ]),
        const SizedBox(height: 12),
        formRow([
          LabeledDropdown<String>(label: 'Type', value: _type, items: const ['standard', 'framework', 'pre_qualification'],
              displayBuilder: tenderTypeLabel, onChanged: (v) => setState(() => _type = v)),
          LabeledDropdown<bool>(label: 'Value is', value: _vatIncl, items: const [false, true],
              displayBuilder: (v) => v ? 'VAT inclusive' : 'VAT exclusive', onChanged: (v) => setState(() => _vatIncl = v)),
        ]),
        formRow([_f('estimated_value', 'Estimated value (TZS)', kb: TextInputType.number), _f('contract_value', 'Contract value (TZS)', kb: TextInputType.number)]),

        formHeading('Bid'),
        formRow([_date('bid_submission_deadline', 'Bid submission deadline'), _f('bid_validity_days', 'Bid validity (days)', kb: TextInputType.number)]),
        formRow([
          _date('tender_expiry_date', 'Tender expiry (if stated)', hint: 'Otherwise submission deadline + validity days'),
          _date('other_tenderer_notified_at', 'Another tenderer notified', hint: 'Ends the bid security early'),
        ]),

        formHeading('Award & contract'),
        formRow([_date('award_notified_at', 'Award notified'), _date('letter_of_acceptance_date', 'Letter of Acceptance date',
            hint: loa == null ? 'Sets the performance security deadline' : 'Performance security due ${formatDate(loa.add(const Duration(days: 14)))}')]),
        formRow([_f('entity_ref', "Buyer's award letter ref"), _date('entity_ref_date', "Award letter date")]),
        formRow([
          LabeledDropdown<String?>(label: 'Performance security form', value: _psForm, items: const [null, 'declaration', 'bank_guarantee'],
              displayBuilder: (v) => switch (v) { 'declaration' => 'Performance Securing Declaration', 'bank_guarantee' => 'Bank guarantee', _ => 'Not decided' },
              onChanged: (v) => setState(() => _psForm = v)),
          _f('our_ref', 'Our acceptance letter ref', hint: 'Proposed automatically when blank'),
        ]),
        formRow([_date('contract_signing_deadline', 'Contract signing deadline'), _date('delivery_deadline', 'Delivery deadline')]),

        formHeading('Power of Attorney & signatory'),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: LabeledDropdown<int?>(
            label: 'Board resolution',
            value: _resolutions.any((r) => r.id == _resolutionId) ? _resolutionId : null,
            items: [null, ..._resolutions.map((r) => r.id)],
            displayBuilder: (id) {
              if (id == null) return 'None';
              final r = _resolutions.firstWhere((r) => r.id == id);
              return 'No. ${r.number} of ${formatDate(r.date)}${r.tenderNumbers.isEmpty ? '' : ' · used by ${r.tenderNumbers.length}'}';
            },
            onChanged: (v) => setState(() => _resolutionId = v),
          )),
          const SizedBox(width: 8),
          ProcButton(label: 'Register', icon: Symbols.add, onPressed: _newResolution),
        ]),
        const SizedBox(height: 12),
        formRow([_f('attorney_name', 'Attorney', hint: 'Blank = Managing Director'), _f('signatory_name', 'Signatory', hint: 'Blank = Managing Director')]),
        formRow([_f('attorney_address', 'Attorney address', hint: "Blank = MD's address in company details"), _f('signatory_position', 'Signatory position')]),
        _f('notes', 'Notes', lines: 3),
        const SizedBox(height: 6),
        Text('Dates and status changes are recorded in the audit log.', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
      ]),
    );
  }
}

// ── Procuring entity ─────────────────────────────────────────────────────────

Future<ProcuringEntity?> showEntityForm(BuildContext context, {ProcuringEntity? entity}) =>
    showDialog<ProcuringEntity>(context: context, builder: (_) => _EntityForm(entity: entity));

class _EntityForm extends StatefulWidget {
  const _EntityForm({this.entity});
  final ProcuringEntity? entity;
  @override
  State<_EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends State<_EntityForm> {
  late final _name = TextEditingController(text: widget.entity?.name);
  late final _addressee = TextEditingController(text: widget.entity?.addressee);
  late final _address = TextEditingController(text: widget.entity?.address);
  late final _code = TextEditingController(text: widget.entity?.shortCode);
  late final _contact = TextEditingController(text: widget.entity?.contact);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _addressee, _address, _code, _contact]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final e = await TenderService.instance.saveEntity({
        'name': _name.text.trim(), 'addressee': _addressee.text.trim(), 'address': _address.text.trim(),
        'short_code': _code.text.trim(), 'contact': _contact.text.trim(),
      }, id: widget.entity?.id);
      if (mounted) Navigator.pop(context, e);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: widget.entity == null ? 'New procuring entity' : 'Edit procuring entity',
    icon: Symbols.apartment,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'Name', controller: _name, hint: 'University of Dodoma'),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Addressee (title of the person letters go to)', controller: _addressee, hint: 'Vice Chancellor'),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Postal address (one line per row)', controller: _address, maxLines: 3, hint: 'P.O Box 259,\nDODOMA TANZANIA'),
      const SizedBox(height: 12),
      formRow([
        LabeledTextField(label: 'Short code (for our reference numbers)', controller: _code, hint: 'UDOM'),
        LabeledTextField(label: 'Contact', controller: _contact),
      ]),
    ]),
  );
}

// ── Board resolution register ────────────────────────────────────────────────

Future<void> showResolutionsDialog(BuildContext context, {required bool canManage}) =>
    showDialog(context: context, builder: (_) => _ResolutionsDialog(canManage: canManage));

class _ResolutionsDialog extends StatefulWidget {
  const _ResolutionsDialog({required this.canManage});
  final bool canManage;
  @override
  State<_ResolutionsDialog> createState() => _ResolutionsDialogState();
}

class _ResolutionsDialogState extends State<_ResolutionsDialog> {
  List<BoardResolution>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await TenderService.instance.resolutions();
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return ProcDialog(
      title: 'Board resolutions',
      icon: Symbols.format_list_numbered,
      actions: [
        if (widget.canManage) ProcButton(label: 'Register resolution', icon: Symbols.add, tone: ProcTone.green, onPressed: () async {
          final r = await showDialog<BoardResolution>(context: context, builder: (_) => const _ResolutionForm());
          if (r != null) _load();
        }),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
      body: _error != null
          ? Text(_error!, style: AppTheme.bodySub.copyWith(color: AppColors.coral))
          : _rows == null
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Numbers come from the board and are typed in, never generated. One resolution can authorise several tenders.',
                      style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.textDim)),
                  const SizedBox(height: 10),
                  if (_rows!.isEmpty) Text('No resolutions registered yet.', style: AppTheme.bodySub),
                  for (final r in _rows!) Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 90, child: Text('No. ${r.number}', style: procMono(context, size: 12, color: pal.text))),
                      SizedBox(width: 110, child: Text(formatDate(r.date), style: AppTheme.bodySm)),
                      Expanded(child: Text(r.tenderNumbers.isEmpty ? 'Not used yet' : r.tenderNumbers.join(', '),
                          style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.textMute))),
                    ]),
                  ),
                ]),
    );
  }
}

class _ResolutionForm extends StatefulWidget {
  const _ResolutionForm();
  @override
  State<_ResolutionForm> createState() => _ResolutionFormState();
}

class _ResolutionFormState extends State<_ResolutionForm> {
  final _number = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty || _date == null) {
      showErrorToast(context, Exception('Enter the resolution number and date.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await TenderService.instance.addResolution(_number.text.trim(), isoDate(_date!),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'Register board resolution',
    icon: Symbols.format_list_numbered,
    width: 460,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Register')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      formRow([
        LabeledTextField(label: 'Resolution number', controller: _number, hint: '126'),
        OptionalDateField(label: 'Resolution date', value: _date, onChanged: (d) => setState(() => _date = d)),
      ]),
      LabeledTextField(label: 'Notes', controller: _notes),
    ]),
  );
}

// ── Company details (19.4) ───────────────────────────────────────────────────

Future<void> showCompanyProfileDialog(BuildContext context, {required bool canManage}) =>
    showDialog(context: context, builder: (_) => _CompanyProfileDialog(canManage: canManage));

class _CompanyProfileDialog extends StatefulWidget {
  const _CompanyProfileDialog({required this.canManage});
  final bool canManage;
  @override
  State<_CompanyProfileDialog> createState() => _CompanyProfileDialogState();
}

class _CompanyProfileDialogState extends State<_CompanyProfileDialog> {
  static const _fields = {
    'legal_name': 'Registered name (capitals, as on the Power of Attorney)',
    'name': 'Name in sentences',
    'short_name': 'Short name (letter sign-off)',
    'physical_address': 'Registered physical address',
    'po_box': 'P.O. Box',
    'city': 'City',
    'tin': 'TIN',
    'md_name': 'Managing Director (full legal name)',
    'md_title': 'Title',
    'md_address': 'Managing Director address (Power of Attorney)',
    'md_phone': 'Managing Director phone (TMDA letters)',
  };
  final _c = <String, TextEditingController>{};
  final _offices = <(TextEditingController, TextEditingController)>[];
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await TenderService.instance.companyProfile();
      if (!mounted) return;
      setState(() {
        for (final k in _fields.keys) {
          _c[k] = TextEditingController(text: p[k]?.toString() ?? '');
        }
        for (final o in (p['tmda_offices'] as List? ?? [])) {
          _offices.add((TextEditingController(text: (o as Map)['name']?.toString()), TextEditingController(text: o['address']?.toString())));
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) { showErrorToast(context, e); Navigator.pop(context); }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final (a, b) in _offices) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await TenderService.instance.saveCompanyProfile({
        for (final k in _fields.keys) k: _c[k]!.text.trim(),
        'tmda_offices': [
          for (final (n, a) in _offices)
            if (n.text.trim().isNotEmpty) {'name': n.text.trim(), 'address': a.text.trim()},
        ],
      });
      if (mounted) { showSuccessToast(context, 'Company details saved.'); Navigator.pop(context); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'Company details for tender & TMDA documents',
    icon: Symbols.domain,
    width: 640,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      if (widget.canManage) FilledButton(onPressed: _saving || _loading ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
    ],
    body: _loading
        ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Entered once and used on every generated document.', style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim)),
            const SizedBox(height: 10),
            for (final e in _fields.entries) Padding(padding: const EdgeInsets.only(bottom: 12),
                child: LabeledTextField(label: e.value, controller: _c[e.key]!, enabled: widget.canManage)),
            formHeading('TMDA offices (Reason for Importation addressees)'),
            for (var i = 0; i < _offices.length; i++) Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: LabeledTextField(label: '', hint: 'Office name', controller: _offices[i].$1, enabled: widget.canManage)),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: LabeledTextField(label: '', hint: 'Address block', controller: _offices[i].$2, maxLines: 5, enabled: widget.canManage)),
                if (widget.canManage) IconButton(onPressed: () => setState(() => _offices.removeAt(i)),
                    icon: Icon(Symbols.delete, size: 17, color: context.pal.textDim)),
              ]),
            ),
            if (widget.canManage) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: () => setState(() => _offices.add((TextEditingController(), TextEditingController()))),
              icon: const Icon(Symbols.add, size: 15), label: const Text('Add office'))),
          ]),
  );
}

// ── Status change ────────────────────────────────────────────────────────────

/// The reason a tender ended as not submitted / cancelled / lost (required).
Future<String?> askTenderStatusReason(BuildContext context, String status) {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => ProcDialog(
      title: '${tenderStatusLabel(status)} — reason',
      icon: Symbols.edit_note,
      width: 460,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        LabeledTextField(label: 'Reason', hint: 'Why is this tender ${tenderStatusLabel(status).toLowerCase()}?',
            controller: ctrl, maxLines: 4),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: TextStyle(color: AppColors.coral, fontSize: 12))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final r = ctrl.text.trim();
          if (r.isEmpty) { setLocal(() => error = 'Give the reason.'); return; }
          Navigator.pop(ctx, r);
        }, child: const Text('Save')),
      ],
    )),
  );
}


Future<String?> pickTenderStatus(BuildContext context, String current) => showDialog<String>(
  context: context,
  builder: (ctx) => ProcDialog(
    title: 'Change status',
    icon: Symbols.route,
    width: 420,
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in [...tenderFlow, 'lost', 'cancelled', 'not_submitted'])
        ListTile(
          dense: true,
          selected: s == current,
          leading: Icon(s == current ? Symbols.radio_button_checked : Symbols.radio_button_unchecked, size: 18),
          title: Text(tenderStatusLabel(s), style: AppTheme.bodySm),
          onTap: () => Navigator.pop(ctx, s),
        ),
    ]),
  ),
);
