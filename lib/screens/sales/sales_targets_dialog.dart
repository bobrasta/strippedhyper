import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/sales_overview_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/labeled_field.dart';

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Monthly revenue target per rep, entered in TSh millions. The team target
/// is always the sum of these — there's nothing separate to keep in sync.
/// Returns true when saved.
Future<bool?> showSalesTargetsDialog(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _SalesTargetsDialog());

class _SalesTargetsDialog extends StatefulWidget {
  const _SalesTargetsDialog();

  @override
  State<_SalesTargetsDialog> createState() => _SalesTargetsDialogState();
}

class _SalesTargetsDialogState extends State<_SalesTargetsDialog> {
  int _year = DateTime.now().year;
  List<RepTargets> _reps = [];
  // One controller per rep per month, holding millions.
  final Map<int, List<TextEditingController>> _ctrls = {};
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _ctrls.values) { for (final c in l) { c.dispose(); } }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await SalesOverviewService.instance.targets(_year);
      if (!mounted) return;
      for (final l in _ctrls.values) { for (final c in l) { c.dispose(); } }
      _ctrls.clear();
      for (final rep in r.reps) {
        _ctrls[rep.id] = [for (final v in rep.months) TextEditingController(text: v == 0 ? '' : _toM(v))];
      }
      setState(() { _reps = r.reps; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  static String _toM(int v) {
    final m = v / 1e6;
    return m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
  }

  int _cell(int repId, int month) => ((double.tryParse(_ctrls[repId]![month].text.trim()) ?? 0) * 1e6).round();
  int _repTotal(int repId) => [for (var m = 0; m < 12; m++) _cell(repId, m)].fold(0, (a, b) => a + b);

  void _fillRow(int repId) {
    final first = _ctrls[repId]!.firstWhere((c) => c.text.trim().isNotEmpty, orElse: () => _ctrls[repId]![0]).text;
    setState(() { for (final c in _ctrls[repId]!) { c.text = first; } });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final reps = [for (final r in _reps) RepTargets(id: r.id, name: r.name, role: r.role, months: [for (var m = 0; m < 12; m++) _cell(r.id, m)])];
      await SalesOverviewService.instance.saveTargets(_year, reps);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamTotal = _reps.fold<int>(0, (a, r) => a + _repTotal(r.id));
    return Dialog(
      backgroundColor: context.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 1100,
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.target, size: 18, color: AppColors.green),
            const SizedBox(width: 10),
            Text('Sales targets', style: AppTheme.bodyStrong),
            const SizedBox(width: 14),
            IconButton(onPressed: _loading ? null : () { _year--; _load(); }, icon: const Icon(Symbols.chevron_left, size: 18), visualDensity: VisualDensity.compact),
            Text('$_year', style: AppTheme.monoSm.copyWith(fontSize: 13)),
            IconButton(onPressed: _loading ? null : () { _year++; _load(); }, icon: const Icon(Symbols.chevron_right, size: 18), visualDensity: VisualDensity.compact),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
          ]),
          const SizedBox(height: 4),
          Text('Monthly revenue target per rep, in TSh millions. Booked revenue is counted from confirmed sales orders. The team target is the sum of these rows.',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: AppTheme.bodySub))
          else if (_reps.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text('No active sales staff to set targets for.', style: AppTheme.bodySub))
          else
            Flexible(child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _row(context, header: true, name: 'Rep', cells: [for (final m in _monthNames) Text(m, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))],
                    total: Text('YEAR', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
                for (final r in _reps)
                  _row(context,
                    name: r.name,
                    action: Tooltip(message: 'Copy the first filled month across the year',
                        child: InkWell(onTap: () => _fillRow(r.id), child: Icon(Symbols.keyboard_double_arrow_right, size: 15, color: context.pal.textDim))),
                    cells: [for (var m = 0; m < 12; m++) _cellField(context, _ctrls[r.id]![m])],
                    total: Text(tshFromDouble(_repTotal(r.id)), style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
                  ),
                _row(context, name: 'Team', cells: [
                  for (var m = 0; m < 12; m++)
                    Text(_toM(_reps.fold<int>(0, (a, r) => a + _cell(r.id, m))), textAlign: TextAlign.center, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textMute)),
                ], total: Text(tshFromDouble(teamTotal), style: AppTheme.monoXs.copyWith(fontSize: 11, color: AppColors.green))),
              ])),
            )),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving || _loading || _reps.isEmpty ? null : _save,
              child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save targets'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, {bool header = false, required String name, Widget? action, required List<Widget> cells, required Widget total}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 5),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
    child: Row(children: [
      SizedBox(width: 170, child: Row(children: [
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: header ? AppTheme.labelCaps.copyWith(fontSize: 9.5) : AppTheme.bodySm.copyWith(fontSize: 12.5))),
        ?action,
        const SizedBox(width: 6),
      ])),
      for (final c in cells) SizedBox(width: 66, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Center(child: c))),
      SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: total)),
    ]),
  );

  // The Settings field look (FieldFocusBox), sized down for a grid cell.
  Widget _cellField(BuildContext context, TextEditingController c) => FieldFocusBox(
    radius: 8,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    builder: (context, focusNode) => TextField(
      controller: c,
      focusNode: focusNode,
      onChanged: (_) => setState(() {}),
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      cursorColor: context.pal.text,
      cursorWidth: 1.5,
      style: AppTheme.fieldText.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: AppTheme.fieldHint.copyWith(fontSize: 13),
        filled: false,
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
  );
}
