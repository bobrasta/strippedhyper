// Import staff pay (2026-10-24): "I have their data and their salary — why
// would I add them manually? What if there are 1000 of them?" Pick the
// spreadsheet, see exactly what each row will set (matched by email, staff
// ID or name), then save. A salary that differs from an existing contract is
// sent to the Director as a Salary Adjustment, never changed directly.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/payroll_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';

/// True when something was saved.
Future<bool?> showStaffPayImport(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _StaffPayImportDialog());

class _StaffPayImportDialog extends StatefulWidget {
  const _StaffPayImportDialog();
  @override
  State<_StaffPayImportDialog> createState() => _StaffPayImportDialogState();
}

class _StaffPayImportDialogState extends State<_StaffPayImportDialog> {
  ({String path, String name})? _file;
  Map<String, dynamic>? _preview;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (Platform.isAndroid) {
      setState(() => _error = 'File uploads aren\'t available on Android in this build — use the desktop app or the web.');
      return;
    }
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'xls', 'csv']);
    final f = r?.files.firstOrNull;
    if (f?.path == null) return;
    setState(() { _file = (path: f!.path!, name: f.name); _preview = null; _error = null; });
    await _run(commit: false);
  }

  Future<void> _run({required bool commit}) async {
    final f = _file;
    if (f == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final r = await PayrollService.instance.importStaffPay(f.path, f.name, commit: commit);
      if (!mounted) return;
      if (commit) {
        showSuccessToast(context, 'Saved pay for ${r['ready']} ${r['ready'] == 1 ? 'person' : 'people'}.');
        Navigator.pop(context, true);
        return;
      }
      setState(() => _preview = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = _preview;
    final rows = [for (final r in (p?['rows'] as List? ?? [])) Map<String, dynamic>.from(r as Map)];
    final ready = (p?['ready'] as num?)?.toInt() ?? 0;
    final unmatched = (p?['unmatched'] as num?)?.toInt() ?? 0;

    return AlertDialog(
      backgroundColor: pal.surface1,
      title: Text('Import staff pay', style: AppTheme.cardTitle),
      content: SizedBox(width: 640, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('One row per person. Columns are recognised by their header: name or email (or staff ID), basic salary, '
            'allowances, health insurance (company-paid, monthly), NSSF / NIDA / TIN numbers, bank and account number.',
            style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.textMute)),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Symbols.upload_file, size: 15),
              label: Text(_file == null ? 'Choose spreadsheet' : 'Choose another')),
          const SizedBox(width: 10),
          if (_file != null) Expanded(child: Text(_file!.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12))),
        if (p != null) ...[
          const SizedBox(height: 12),
          Text('$ready ready to save${unmatched > 0 ? ' · $unmatched not matched to anyone' : ''} · '
              'columns found: ${(p['columns_found'] as Map? ?? {}).values.join(', ')}',
              style: AppTheme.bodySub.copyWith(fontSize: 12, color: unmatched > 0 ? AppColors.amber : pal.textMute)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.border)),
              child: ListView(shrinkWrap: true, children: [
                for (final r in rows) _row(context, r),
              ]),
            ),
          ),
        ],
      ])),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || ready == 0 ? null : () => _run(commit: true),
          child: Text(ready == 0 ? 'Save' : 'Save $ready ${ready == 1 ? 'person' : 'people'}'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final pal = context.pal;
    final user = r['user'] as Map?;
    final actions = [for (final a in (r['actions'] as List? ?? [])) a as String];
    final problems = [for (final a in (r['problems'] as List? ?? [])) a as String];
    final ok = user != null && problems.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? (actions.isEmpty ? Symbols.remove : Symbols.check_circle) : Symbols.error, size: 16,
            color: ok ? (actions.isEmpty ? pal.textDim : AppColors.green) : AppColors.coral),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Line ${r['line']} · ${r['name_in_file'] ?? '—'}${user != null && user['name'] != r['name_in_file'] ? ' → ${user['name']}' : ''}',
              style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          for (final a in actions) Text(a, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
          if (ok && actions.isEmpty) Text('Nothing to change', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
          for (final a in problems) Text(a, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.coral)),
        ])),
      ]),
    );
  }
}
