import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/finance_report_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/labeled_field.dart';

/// Export of the annual financial statements (audited-statements template)
/// — FinancialStatementsController on the backend. Every figure comes from
/// the ledger for the chosen calendar year and the one before it; the
/// "Report details" tab edits the narrative around them (directors,
/// auditor, policies…), which isn't ledger data.
///
/// Draft is the default: it leaves out the auditor's report and marks every
/// page unaudited. "Audited" adds the auditor's report pages, so it's only
/// for figures the auditor has actually signed off.
Future<void> showFinancialStatementsDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _FinancialStatementsDialog());

class _FinancialStatementsDialog extends StatefulWidget {
  const _FinancialStatementsDialog();
  @override
  State<_FinancialStatementsDialog> createState() => _FinancialStatementsDialogState();
}

class _FinancialStatementsDialogState extends State<_FinancialStatementsDialog> {
  int _pane = 0; // 0 export, 1 report details

  // Export
  late int _year = DateTime.now().year - 1;
  bool _audited = false;
  DateTime _signDate = DateTime.now();
  bool _exporting = false;

  // Report details
  bool _loadingProfile = false;
  bool _saving = false;
  String? _profileError;
  Map<String, dynamic>? _profile;
  final _text = <String, TextEditingController>{};
  final _auditor = <String, TextEditingController>{};
  final _financeHead = <String, TextEditingController>{};
  late _Rows _coverAddress, _directors, _shareholders, _policies, _depRates, _letterhead;

  static const _textKeys = {
    'company': 'Company name',
    'company_short': 'Short name (cover band)',
    'principal_activities': 'Principal activities',
    'chairman': 'Chairman of the board',
    'md_note_name': 'Managing director (name as written in the note)',
    'md_note': 'Managing director note',
    'employees': 'Employees (leave blank to count active staff)',
    'dep_note': 'Depreciation note',
  };
  static const _auditorKeys = {
    'name': 'Firm name (cover)',
    'firm': 'Firm name (letterhead)',
    'short': 'Short name',
    'cpa_line': 'Footer line',
    'title': 'Title',
    'tagline': 'Tagline',
    'cover_address': 'Cover address',
    'city': 'City',
    'email': 'Email',
    'partner': 'Engagement partner',
    'po_box_text': "Address in directors' report",
  };
  static const _financeHeadKeys = {'name': 'Name', 'title': 'Title', 'reg_no': 'NBAA reg. no.'};

  @override
  void dispose() {
    for (final c in [..._text.values, ..._auditor.values, ..._financeHead.values]) {
      c.dispose();
    }
    if (_profile != null) {
      for (final r in [_coverAddress, _directors, _shareholders, _policies, _depRates, _letterhead]) {
        r.dispose();
      }
    }
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _export() async {
    setState(() => _exporting = true);
    await downloadPdf(
      context,
      () => FinanceReportService.instance.statementsPdf(year: _year, audited: _audited, signDate: _iso(_signDate)),
      'financial_statements_$_year${_audited ? '' : '_draft'}.pdf',
    );
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _openDetails() async {
    setState(() => _pane = 1);
    if (_profile != null || _loadingProfile) return;
    setState(() { _loadingProfile = true; _profileError = null; });
    try {
      final p = await FinanceReportService.instance.statementsProfile();
      if (!mounted) return;
      _bind(p);
      setState(() { _profile = p; _loadingProfile = false; });
    } catch (e) {
      if (mounted) setState(() { _profileError = friendlyError(e); _loadingProfile = false; });
    }
  }

  void _bind(Map<String, dynamic> p) {
    for (final k in _textKeys.keys) {
      _text[k] = TextEditingController(text: p[k]?.toString() ?? '');
    }
    final a = (p['auditor'] as Map?) ?? {};
    for (final k in _auditorKeys.keys) {
      _auditor[k] = TextEditingController(text: a[k]?.toString() ?? '');
    }
    final f = (p['finance_head'] as Map?) ?? {};
    for (final k in _financeHeadKeys.keys) {
      _financeHead[k] = TextEditingController(text: f[k]?.toString() ?? '');
    }
    _coverAddress = _Rows.fromLines(p['cover_address']);
    _letterhead = _Rows.fromLines(a['letterhead']);
    _directors = _Rows.from(p['directors'], 3);
    _shareholders = _Rows.from(p['shareholders'], 3);
    _policies = _Rows.from(p['policies'], 2);
    _depRates = _Rows.from(p['dep_rates'], 2);
  }

  Future<void> _save() async {
    final body = <String, dynamic>{
      for (final k in _textKeys.keys) k: _text[k]!.text.trim(),
      'employees': int.tryParse(_text['employees']!.text.trim()),
      'cover_address': _coverAddress.lines(),
      'directors': _directors.values(),
      'shareholders': _shareholders.values().map((r) => [r[0], r[1], int.tryParse(r[2].replaceAll(',', '')) ?? 0]).toList(),
      'policies': _policies.values(),
      'dep_rates': _depRates.values(),
      'finance_head': {for (final k in _financeHeadKeys.keys) k: _financeHead[k]!.text.trim()},
      'auditor': {
        for (final k in _auditorKeys.keys) k: _auditor[k]!.text.trim(),
        'letterhead': _letterhead.lines(),
      },
    };
    setState(() => _saving = true);
    try {
      _profile = await FinanceReportService.instance.saveStatementsProfile(body);
      if (mounted) showSuccessToast(context, 'Report details saved.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Dialog(
      backgroundColor: pal.surface1,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: pal.borderStrong)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _pane == 0 ? 480 : 720, maxHeight: 720),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 10),
            child: Row(children: [
              Icon(Symbols.description, size: 18, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(child: Text('Financial statements', style: AppTheme.bodyStrong)),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Symbols.close, size: 18, color: pal.textDim)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Export'), icon: Icon(Symbols.download, size: 15)),
                ButtonSegment(value: 1, label: Text('Report details'), icon: Icon(Symbols.edit_note, size: 15)),
              ],
              selected: {_pane},
              onSelectionChanged: (s) => s.first == 1 ? _openDetails() : setState(() => _pane = 0),
            ),
          ),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _pane == 0 ? _exportPane(pal) : _detailsPane(pal),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              if (_pane == 0)
                FilledButton.icon(
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Symbols.picture_as_pdf, size: 15),
                  label: Text(_exporting ? 'Preparing…' : 'Download PDF'),
                )
              else
                FilledButton.icon(
                  onPressed: _saving || _profile == null ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Symbols.save, size: 15),
                  label: Text(_saving ? 'Saving…' : 'Save details'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _exportPane(AppPalette pal) {
    final years = [for (var y = DateTime.now().year; y >= DateTime.now().year - 6; y--) y];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledDropdown<int>(
        label: 'Financial year (1 Jan – 31 Dec)',
        value: _year,
        items: years,
        displayBuilder: (y) => y == DateTime.now().year ? '$y (year to date)' : '$y',
        onChanged: (y) => setState(() => _year = y),
      ),
      const SizedBox(height: 14),
      Text('Status', style: AppTheme.fieldLabel),
      const SizedBox(height: 6),
      _StatusOption(
        selected: !_audited,
        title: 'Draft · unaudited',
        subtitle: "No auditor's report. Every page is marked draft.",
        onTap: () => setState(() => _audited = false),
      ),
      const SizedBox(height: 8),
      _StatusOption(
        selected: _audited,
        title: 'Audited',
        subtitle: "Adds the auditor's report pages. Only for figures the auditor has signed off.",
        onTap: () => setState(() => _audited = true),
      ),
      const SizedBox(height: 14),
      LabeledDateField(
        label: 'Signing date',
        date: _signDate,
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: _signDate, firstDate: DateTime(_year), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (d != null) setState(() => _signDate = d);
        },
      ),
      const SizedBox(height: 14),
      Text(
        'Figures come from the ledger for $_year with ${_year - 1} as the comparative. '
        'Names, directors, auditor and policies come from Report details.',
        style: AppTheme.bodySub.copyWith(fontSize: 12),
      ),
    ]);
  }

  Widget _detailsPane(AppPalette pal) {
    if (_loadingProfile) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (_profileError != null) return Text(_profileError!, style: AppTheme.bodySub.copyWith(color: AppColors.amber));
    if (_profile == null) return const SizedBox.shrink();

    Widget field(String label, TextEditingController c, {int maxLines = 1, TextInputType? keyboard}) =>
        Padding(padding: const EdgeInsets.only(bottom: 12), child: LabeledTextField(label: label, controller: c, maxLines: maxLines, keyboardType: keyboard));
    Widget heading(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 10), child: Text(t, style: AppTheme.bodyStrong));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('Company'),
      field(_textKeys['company']!, _text['company']!),
      field(_textKeys['company_short']!, _text['company_short']!),
      _RowsEditor(label: 'Cover address', rows: _coverAddress, columns: const ['Line'], onChanged: () => setState(() {})),
      field(_textKeys['principal_activities']!, _text['principal_activities']!, maxLines: 3),
      field(_textKeys['employees']!, _text['employees']!, keyboard: TextInputType.number),
      heading('Board & shareholders'),
      _RowsEditor(label: 'Directors', rows: _directors, columns: const ['Name', 'Qualification', 'Nationality'], onChanged: () => setState(() {})),
      field(_textKeys['md_note_name']!, _text['md_note_name']!),
      field(_textKeys['md_note']!, _text['md_note']!, maxLines: 3),
      _RowsEditor(label: 'Shareholders', rows: _shareholders, columns: const ['Name', 'Nationality', 'Shares'], onChanged: () => setState(() {})),
      field(_textKeys['chairman']!, _text['chairman']!),
      heading('Head of finance (declaration)'),
      for (final e in _financeHeadKeys.entries) field(e.value, _financeHead[e.key]!),
      heading('Auditor'),
      for (final e in _auditorKeys.entries) field(e.value, _auditor[e.key]!),
      _RowsEditor(label: 'Letterhead lines', rows: _letterhead, columns: const ['Line'], onChanged: () => setState(() {})),
      heading('Accounting policies'),
      _RowsEditor(label: 'Policies (a policy titled "Depreciation" gets the rates below)', rows: _policies, columns: const ['Title', 'Text'], multilineLast: true, onChanged: () => setState(() {})),
      _RowsEditor(label: 'Depreciation rates', rows: _depRates, columns: const ['Asset class', 'Rate'], onChanged: () => setState(() {})),
      field(_textKeys['dep_note']!, _text['dep_note']!, maxLines: 2),
    ]);
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({required this.selected, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppColors.tealSoft : context.pal.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppColors.teal : context.pal.borderStrong, width: 1.2),
      ),
      child: Row(children: [
        Icon(selected ? Symbols.radio_button_checked : Symbols.radio_button_unchecked, size: 18, color: selected ? AppColors.teal : context.pal.textDim),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTheme.bodyStrong),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTheme.bodySub.copyWith(fontSize: 12)),
        ])),
      ]),
    ),
  );
}

/// Editable list of fixed-width rows (directors, policies, …).
class _Rows {
  _Rows(this.width, List<List<String>> initial) : rows = initial.map((r) => [for (var i = 0; i < width; i++) TextEditingController(text: i < r.length ? r[i] : '')]).toList();

  factory _Rows.from(dynamic raw, int width) =>
      _Rows(width, [for (final r in (raw as List? ?? [])) [for (final c in (r as List)) c?.toString() ?? '']]);

  factory _Rows.fromLines(dynamic raw) => _Rows(1, [for (final l in (raw as List? ?? [])) [l?.toString() ?? '']]);

  final int width;
  final List<List<TextEditingController>> rows;

  void add() => rows.add([for (var i = 0; i < width; i++) TextEditingController()]);

  void removeAt(int i) {
    for (final c in rows.removeAt(i)) {
      c.dispose();
    }
  }

  /// Rows whose first cell is filled in.
  List<List<String>> values() => [
    for (final r in rows)
      if (r.first.text.trim().isNotEmpty) [for (final c in r) c.text.trim()],
  ];

  List<String> lines() => values().map((r) => r.first).toList();

  void dispose() {
    for (final r in rows) {
      for (final c in r) {
        c.dispose();
      }
    }
  }
}

class _RowsEditor extends StatelessWidget {
  const _RowsEditor({required this.label, required this.rows, required this.columns, required this.onChanged, this.multilineLast = false});
  final String label;
  final _Rows rows;
  final List<String> columns;
  final VoidCallback onChanged;
  final bool multilineLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: AppTheme.fieldLabel),
      const SizedBox(height: 6),
      for (var i = 0; i < rows.rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var c = 0; c < columns.length; c++) ...[
              Expanded(
                flex: multilineLast && c == columns.length - 1 ? 3 : 1,
                child: LabeledTextField(
                  label: '',
                  controller: rows.rows[i][c],
                  hint: columns[c],
                  maxLines: multilineLast && c == columns.length - 1 ? 4 : 1,
                ),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Remove',
              onPressed: () { rows.removeAt(i); onChanged(); },
              icon: Icon(Symbols.delete, size: 17, color: context.pal.textDim),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () { rows.add(); onChanged(); },
          icon: const Icon(Symbols.add, size: 15),
          label: const Text('Add'),
        ),
      ),
    ]),
  );
}
