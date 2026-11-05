// Section 19.5 — TMDA device registrations. The Annex V essential
// requirements checklist is stored as rows and regenerated as .docx on
// demand; the Reason for Importation letter is blocked without a live
// registration number (enforced by the API, mirrored here).

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/tender.dart';
import '../../services/tender_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'tender_forms.dart';
import 'tenders_screen.dart' show deadlineColor;

ProcTone _tone(String s) => switch (s) {
  'registered' => ProcTone.green,
  'renewal_due' => ProcTone.amber,
  'expired' => ProcTone.coral,
  'submitted' || 'under_review' => ProcTone.teal,
  _ => ProcTone.neutral,
};

class DeviceRegistrationsScreen extends StatefulWidget {
  const DeviceRegistrationsScreen({super.key, this.initialDeviceId});
  final int? initialDeviceId;
  @override
  State<DeviceRegistrationsScreen> createState() => _DeviceRegistrationsScreenState();
}

class _DeviceRegistrationsScreenState extends State<DeviceRegistrationsScreen> {
  List<DeviceRegistration>? _all;
  bool _canManage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialDeviceId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.initialDeviceId!));
    }
  }

  Future<void> _load() async {
    try {
      final (list, can) = await TenderService.instance.devices();
      if (mounted) setState(() { _all = list; _canManage = can; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceRegistrationDetailScreen(deviceId: id)));
    _load();
  }

  Future<void> _new() async {
    final d = await showDialog<DeviceRegistration>(context: context, builder: (_) => const _DeviceForm());
    if (d != null) _open(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final all = _all;
    if (all == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final importable = all.where((d) => d.allowsImport).toList();
    final renewal = all.where((d) => d.renewal != null && [DeadlineState.soon, DeadlineState.dueToday, DeadlineState.overdue].contains(d.renewal!.state)).toList();
    final review = all.where((d) => d.status == 'submitted' || d.status == 'under_review').toList();
    final blocking = all.where((d) => !d.allowsImport).toList();
    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'Device registrations',
          subtitle: 'TMDA · ${all.length} device${all.length == 1 ? '' : 's'} · ${importable.length} can be imported · ${renewal.length} renewal${renewal.length == 1 ? '' : 's'} due',
          actions: [
            if (_canManage) ProcButton(label: 'New registration', icon: Symbols.add, tone: ProcTone.green, onPressed: _new),
          ],
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
          KpiStrip([
            KpiStripItem(Symbols.verified, ProcTone.green, 'Registered', '${importable.length}', 'import letters allowed'),
            KpiStripItem(Symbols.event_repeat, ProcTone.amber, 'Renewal due', '${renewal.length}',
                renewal.isEmpty ? 'none within 7 days' : renewal.map((d) => d.brandName).take(2).join(' · ')),
            KpiStripItem(Symbols.pending, ProcTone.teal, 'In review', '${review.length}', 'submitted to TMDA'),
            KpiStripItem(Symbols.block, ProcTone.coral, 'Blocking imports', '${blocking.length}', 'no active registration'),
          ]),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
            child: all.isEmpty
                ? Padding(padding: const EdgeInsets.all(28), child: Text('No device registrations yet.', textAlign: TextAlign.center,
                    style: AppTheme.bodySub.copyWith(color: pal.textDim)))
                : Column(children: [
                    for (final d in all) InkWell(
                      onTap: () => _open(d.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                        child: LayoutBuilder(builder: (context, box) {
                          final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(d.brandName, style: AppTheme.bodySm),
                            Text([d.commonName, d.manufacturer].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                                style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), overflow: TextOverflow.ellipsis),
                          ]);
                          final number = Text(d.registrationNumber ?? 'No number · import blocked',
                              style: procMono(context, color: d.registrationNumber == null ? AppColors.coral : pal.textMute), overflow: TextOverflow.ellipsis);
                          final renew = Text(d.renewalDueDate == null ? '—' : formatDate(d.renewalDueDate!),
                              style: AppTheme.bodySub.copyWith(fontSize: 11, color: d.renewal == null ? pal.textDim : deadlineColor(context, d.renewal!.state)));
                          if (box.maxWidth < 700) {
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [Expanded(child: name), ProcTag(d.statusLabel, tone: _tone(d.status))]),
                              const SizedBox(height: 4), number, renew,
                            ]);
                          }
                          return Row(children: [
                            Expanded(flex: 3, child: name),
                            const SizedBox(width: 14),
                            SizedBox(width: 60, child: Text(d.riskClass == null ? '—' : 'Class ${d.riskClass}', style: procMono(context))),
                            const SizedBox(width: 14),
                            Expanded(flex: 2, child: number),
                            const SizedBox(width: 14),
                            SizedBox(width: 70, child: Text('${d.checklistDone}/${d.checklistTotal}', style: procMono(context,
                                color: d.checklistDone < d.checklistTotal ? AppColors.amber : AppColors.green))),
                            SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: ProcTag(d.statusLabel, tone: _tone(d.status)))),
                            const SizedBox(width: 14),
                            SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: renew)),
                          ]);
                        }),
                      ),
                    ),
                  ]),
          ),
        ]))),
      ]),
    );
  }
}

class DeviceRegistrationDetailScreen extends StatefulWidget {
  const DeviceRegistrationDetailScreen({super.key, required this.deviceId});
  final int deviceId;
  @override
  State<DeviceRegistrationDetailScreen> createState() => _DeviceRegistrationDetailScreenState();
}

class _DeviceRegistrationDetailScreenState extends State<DeviceRegistrationDetailScreen> {
  DeviceRegistration? _d;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await TenderService.instance.device(widget.deviceId);
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run(String key, Future<DeviceRegistration> Function() action) async {
    setState(() => _busy = key);
    try {
      final d = await action();
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String get _slug => _d!.brandName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');

  Future<void> _edit() async {
    final d = await showDialog<DeviceRegistration>(context: context, builder: (_) => _DeviceForm(device: _d));
    if (d != null) _load();
  }

  Future<void> _editRow(EssentialRequirement r) async {
    final res = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _RequirementForm(r));
    if (res == null) return;
    await _run('row-${r.no}', () => TenderService.instance.updateRequirement(_d!.id, r.no, res));
  }

  Future<void> _setApplicable(EssentialRequirement r, bool v) =>
      _run('row-${r.no}', () => TenderService.instance.updateRequirement(_d!.id, r.no, {
        'applicable': v, if (!v) 'method': null, if (!v) 'supporting_document': null,
      }));

  Future<void> _uploadFile() async {
    if (Platform.isAndroid) {
      showErrorToast(context, Exception('File uploads aren\'t available on Android in this build.'));
      return;
    }
    final r = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (r == null || r.files.isEmpty || r.files.first.path == null || !mounted) return;
    final tags = await showDialog<(List<int>, String)>(context: context,
        builder: (_) => _FileTagForm(fileName: r.files.first.name, principles: _d!.requirements));
    if (tags == null) return;
    await _run('upload', () => TenderService.instance.uploadDeviceFile(_d!.id, r.files.first.path!, r.files.first.name, tags.$1,
        description: tags.$2.isEmpty ? null : tags.$2));
  }

  Future<void> _importLetter() async {
    final input = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _ImportLetterForm());
    if (input == null || !mounted) return;
    setState(() => _busy = 'import');
    await downloadPdf(context, () => TenderService.instance.importLetter(_d!.id,
        office: input['office'] as int, purpose: input['purpose'] as String?, date: input['date'] as String?),
        'reason-for-importation-$_slug.docx');
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _checklistDoc() async {
    setState(() => _busy = 'annex');
    await downloadPdf(context, () => TenderService.instance.checklistDocument(_d!.id), 'annex-v-checklist-$_slug.docx');
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final d = _d;
    if (d == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: AppBar(backgroundColor: pal.bg),
          body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final readOnly = !d.canManage;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Device registrations')))),
        ProcPageHeader(
          title: [d.brandName, d.commonName].whereType<String>().where((s) => s.isNotEmpty).join(' — '),
          breadcrumb: ['Device registrations', d.registrationNumber ?? 'Unregistered'],
          accent: _tone(d.status).fg(context),
          tags: [
            ProcTag(d.statusLabel, tone: _tone(d.status)),
            if (d.riskClass != null) ProcTag('Class ${d.riskClass}'),
            Text([d.manufacturer, if (d.model != null) 'model ${d.model}'].whereType<String>().join(' · '),
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          ],
          actions: [
            ProcButton(label: _busy == 'annex' ? 'Preparing…' : 'Annex V document', icon: Symbols.description, onPressed: _busy == null ? _checklistDoc : null),
            if (!readOnly) ...[
              ProcButton(label: 'Edit', icon: Symbols.edit, onPressed: _edit),
              ProcButton(label: _busy == 'import' ? 'Preparing…' : 'Reason for Importation', icon: Symbols.mail, tone: ProcTone.green,
                  locked: !d.allowsImport, onPressed: _busy == null ? _importLetter : null),
            ],
          ],
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: LayoutBuilder(builder: (context, box) {
          final checklist = _checklistPanel(context, d, readOnly);
          final side = Column(children: [
            _registrationPanel(context, d),
            const SizedBox(height: 14),
            ProcPanel(
              title: 'Supporting documents', icon: Symbols.folder_copy, iconColor: AppColors.green,
              trailing: readOnly ? null : TextButton.icon(onPressed: _busy == null ? _uploadFile : null,
                  icon: const Icon(Symbols.upload, size: 14), label: Text(_busy == 'upload' ? 'Uploading…' : 'Upload')),
              footer: const ProcNote('Files come from the manufacturer. Tag each upload with the principle(s) it supports.'),
              child: d.files.isEmpty
                  ? Padding(padding: const EdgeInsets.all(14), child: Text('No files yet.', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)))
                  : Column(children: [
                      for (final f in d.files) Container(
                        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                        child: Row(children: [
                          Icon(Symbols.draft, size: 15, color: AppColors.green),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.name, style: procMono(context, size: 10.5, color: pal.textMute), overflow: TextOverflow.ellipsis),
                            if ((f.description ?? '').isNotEmpty) Text(f.description!, style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
                          ])),
                          if (f.principles.isNotEmpty) ProcTag('§ ${f.principles.join(', ')}', small: true),
                          IconButton(tooltip: 'Download', onPressed: () => downloadPdf(context,
                              () => TenderService.instance.downloadDeviceFile(d.id, f.id), f.name),
                              icon: Icon(Symbols.download, size: 16, color: pal.textDim)),
                          if (!readOnly) IconButton(tooltip: 'Remove', onPressed: () => _run('del', () => TenderService.instance.deleteDeviceFile(d.id, f.id)),
                              icon: Icon(Symbols.delete, size: 16, color: pal.textDim)),
                        ]),
                      ),
                    ]),
            ),
          ]);
          if (box.maxWidth < 1050) {
            return ListView(padding: const EdgeInsets.all(16), children: [checklist, const SizedBox(height: 14), side]);
          }
          return SingleChildScrollView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: checklist), const SizedBox(width: 14), SizedBox(width: 340, child: side)]));
        }))),
      ])),
    );
  }

  Widget _registrationPanel(BuildContext context, DeviceRegistration d) {
    final pal = context.pal;
    TextStyle v([Color? c]) => AppTheme.bodySub.copyWith(fontSize: 11.5, color: c ?? pal.text);
    return ProcPanel(
      title: 'Registration', icon: Symbols.verified, iconColor: _tone(d.status).fg(context),
      footer: d.allowsImport ? null : const ProcNote(
          'No active registration number. Reason for Importation letters are blocked for this device.',
          icon: Symbols.block, tone: ProcTone.coral),
      child: KvGrid(labelWidth: 100, [
        ('Number', Text(d.registrationNumber ?? '—', style: procMono(context, size: 11.5, color: d.registrationNumber == null ? AppColors.coral : pal.text))),
        ('Status', Text(d.statusLabel, style: v(_tone(d.status).fg(context)))),
        ('Submitted', Text(d.submittedAt == null ? '—' : formatDate(d.submittedAt!), style: v())),
        ('Registered', Text(d.registeredAt == null ? '—' : formatDate(d.registeredAt!), style: v())),
        ('Renewal due', Text(d.renewalDueDate == null ? '—' : '${formatDate(d.renewalDueDate!)} · ${d.renewal?.relative ?? ''}',
            style: v(d.renewal == null ? null : deadlineColor(context, d.renewal!.state)))),
        if ((d.notes ?? '').isNotEmpty) ('Notes', Text(d.notes!, style: v(pal.textMute))),
      ]),
    );
  }

  Widget _checklistPanel(BuildContext context, DeviceRegistration d, bool readOnly) {
    final pal = context.pal;
    final rows = d.requirements;
    return ProcPanel(
      title: 'Essential requirements · Annex V', icon: Symbols.checklist, iconColor: AppColors.cyan,
      trailing: Text('${d.checklistDone} / ${rows.length} complete', style: procMono(context, size: 10.5,
          color: d.checklistDone < rows.length ? AppColors.amber : AppColors.green)),
      footer: const ProcNote('Principle list to be confirmed against TMDA’s current Annex V. Edits here regenerate the filled document — no retyping.',
          icon: Symbols.warning, tone: ProcTone.amber),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows) Builder(builder: (context) {
          final missing = r.applicable == true && !r.complete;
          return InkWell(
            onTap: readOnly || r.applicable == false ? null : () => _editRow(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(color: missing ? AppColors.amber.withValues(alpha: 0.04) : null,
                  border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 26, child: Text('${r.no}', style: procMono(context, size: 10.5))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.principle, style: AppTheme.bodySm.copyWith(fontSize: 12)),
                  const SizedBox(height: 3),
                  if (r.applicable == false)
                    Text('Not applicable', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))
                  else if (r.applicable == null)
                    Text('Not answered', style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.amber))
                  else
                    Text('${r.method ?? 'Add method'} · ${r.supportingDocument ?? 'add supporting document'}',
                        style: AppTheme.bodySub.copyWith(fontSize: 11, color: missing ? AppColors.amber : pal.textMute)),
                ])),
                const SizedBox(width: 10),
                if (_busy == 'row-${r.no}')
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  ProcSegmented(options: const ['Yes', 'No'],
                      selected: r.applicable == false ? 1 : r.applicable == true ? 0 : -1,
                      onChanged: readOnly ? (_) {} : (s) => _setApplicable(r, s == 0)),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}

// ── Dialogs ──────────────────────────────────────────────────────────────────

class _DeviceForm extends StatefulWidget {
  const _DeviceForm({this.device});
  final DeviceRegistration? device;
  @override
  State<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<_DeviceForm> {
  late final d = widget.device;
  late final _brand = TextEditingController(text: d?.brandName);
  late final _common = TextEditingController(text: d?.commonName);
  late final _model = TextEditingController(text: d?.model);
  late final _maker = TextEditingController(text: d?.manufacturer);
  late final _number = TextEditingController(text: d?.registrationNumber);
  late final _notes = TextEditingController(text: d?.notes);
  late String? _risk = d?.riskClass;
  late String _status = d?.status ?? 'preparing_dossier';
  late DateTime? _submitted = d?.submittedAt, _registered = d?.registeredAt, _renewal = d?.renewalDueDate;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_brand, _common, _model, _maker, _number, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_brand.text.trim().isEmpty) {
      showErrorToast(context, Exception('Enter the brand name.'));
      return;
    }
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _saving = true);
    try {
      final saved = await TenderService.instance.saveDevice({
        'brand_name': _brand.text.trim(), 'common_name': t(_common), 'model': t(_model), 'manufacturer': t(_maker),
        'registration_number': t(_number), 'notes': t(_notes), 'risk_class': _risk, 'status': _status,
        'submitted_at': _submitted == null ? null : isoDate(_submitted!),
        'registered_at': _registered == null ? null : isoDate(_registered!),
        'renewal_due_date': _renewal == null ? null : isoDate(_renewal!),
      }, id: d?.id);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: d == null ? 'New device registration' : 'Edit ${d!.brandName}',
    icon: Symbols.verified,
    width: 620,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      formRow([LabeledTextField(label: 'Brand name', controller: _brand, hint: 'Hemochrom Plus'), LabeledTextField(label: 'Common name', controller: _common)]),
      formRow([LabeledTextField(label: 'Model', controller: _model), LabeledTextField(label: 'Manufacturer', controller: _maker)]),
      formRow([
        LabeledDropdown<String?>(label: 'Risk class (TMDA)', value: _risk, items: const [null, 'A', 'B', 'C', 'D'],
            displayBuilder: (v) => v == null ? 'Not set' : 'Class $v', onChanged: (v) => setState(() => _risk = v)),
        LabeledDropdown<String>(label: 'Status', value: _status, items: registrationStatuses,
            displayBuilder: registrationStatusLabel, onChanged: (v) => setState(() => _status = v)),
      ]),
      LabeledTextField(label: 'Registration number (once issued)', controller: _number, hint: 'TAN 19 MDR 0357'),
      const SizedBox(height: 12),
      formRow([
        OptionalDateField(label: 'Submitted', value: _submitted, onChanged: (v) => setState(() => _submitted = v)),
        OptionalDateField(label: 'Registered', value: _registered, onChanged: (v) => setState(() => _registered = v)),
      ]),
      OptionalDateField(label: 'Renewal due', value: _renewal, onChanged: (v) => setState(() => _renewal = v),
          hint: 'Reminders go 7 days, 3 days and on the day. Confirm the renewal interval with TMDA.'),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Notes', controller: _notes, maxLines: 3),
    ]),
  );
}

class _RequirementForm extends StatefulWidget {
  const _RequirementForm(this.r);
  final EssentialRequirement r;
  @override
  State<_RequirementForm> createState() => _RequirementFormState();
}

class _RequirementFormState extends State<_RequirementForm> {
  late final _method = TextEditingController(text: widget.r.method);
  late final _doc = TextEditingController(text: widget.r.supportingDocument);

  @override
  void dispose() {
    _method.dispose();
    _doc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: '${widget.r.no}. ${widget.r.principle}',
    icon: Symbols.checklist,
    width: 520,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, {
        'applicable': true,
        'method': _method.text.trim().isEmpty ? null : _method.text.trim(),
        'supporting_document': _doc.text.trim().isEmpty ? null : _doc.text.trim(),
      }), child: const Text('Save')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'Method of conformity', controller: _method, hint: 'ISO 13485:2016'),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Identity of the specific supporting document', controller: _doc, hint: 'Technical file ref / certificate no.'),
    ]),
  );
}

class _FileTagForm extends StatefulWidget {
  const _FileTagForm({required this.fileName, required this.principles});
  final String fileName;
  final List<EssentialRequirement> principles;
  @override
  State<_FileTagForm> createState() => _FileTagFormState();
}

class _FileTagFormState extends State<_FileTagForm> {
  final _selected = <int>{};
  final _desc = TextEditingController();

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'Upload ${widget.fileName}',
    icon: Symbols.upload,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, (_selected.toList()..sort(), _desc.text.trim())), child: const Text('Upload')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'Description', controller: _desc, hint: 'ISO 13485 certificate, 2024'),
      const SizedBox(height: 12),
      Text('Supports principles', style: AppTheme.fieldLabel),
      for (final p in widget.principles) CheckboxListTile(
        dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
        value: _selected.contains(p.no),
        title: Text('${p.no}. ${p.principle}', style: AppTheme.bodySm),
        onChanged: (v) => setState(() => v == true ? _selected.add(p.no) : _selected.remove(p.no)),
      ),
    ]),
  );
}

class _ImportLetterForm extends StatefulWidget {
  const _ImportLetterForm();
  @override
  State<_ImportLetterForm> createState() => _ImportLetterFormState();
}

class _ImportLetterFormState extends State<_ImportLetterForm> {
  List<Map<String, dynamic>>? _offices;
  int _office = 0;
  DateTime _date = DateTime.now();
  final _purpose = TextEditingController(text: 'These goods are aimed to be sold to our private clinics in Tanzania.');

  @override
  void initState() {
    super.initState();
    TenderService.instance.companyProfile().then((p) {
      if (mounted) setState(() => _offices = [for (final o in (p['tmda_offices'] as List? ?? [])) Map<String, dynamic>.from(o as Map)]);
    }).catchError((Object e) {
      if (mounted) showErrorToast(context, e);
    });
  }

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offices = _offices;
    return ProcDialog(
      title: 'Reason for Importation letter',
      icon: Symbols.mail,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: offices == null || offices.isEmpty ? null : () => Navigator.pop(context, {
          'office': _office, 'purpose': _purpose.text.trim(), 'date': isoDate(_date),
        }), child: const Text('Generate .docx')),
      ],
      body: offices == null
          ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (offices.isEmpty)
                Text('Add a TMDA office address under Tenders › Company details first.', style: AppTheme.bodySub.copyWith(color: AppColors.coral))
              else
                LabeledDropdown<int>(label: 'Addressed to', value: _office, items: [for (var i = 0; i < offices.length; i++) i],
                    displayBuilder: (i) => offices[i]['name']?.toString() ?? 'Office ${i + 1}', onChanged: (v) => setState(() => _office = v)),
              const SizedBox(height: 12),
              LabeledTextField(label: 'Stated purpose / destination', controller: _purpose, maxLines: 2),
              const SizedBox(height: 12),
              OptionalDateField(label: 'Letter date', value: _date, onChanged: (v) => setState(() => _date = v ?? DateTime.now())),
            ]),
    );
  }
}
