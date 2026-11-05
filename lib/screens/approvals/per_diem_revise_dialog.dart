import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/per_diem_request.dart';
import '../../services/per_diem_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseIso(String s) => DateTime.tryParse(s) ?? DateTime.now();

/// One editable day — pre-filled from an existing PerDiemLine so editing
/// never silently drops a field the create-time dialog doesn't collect
/// (labor_cost isn't shown on TravelPlanDialog, but an existing line may
/// already carry one — resubmitting the full array must not zero it out).
class _ReviseLineDraft {
  _ReviseLineDraft({required this.date});

  factory _ReviseLineDraft.fromLine(PerDiemLine l) {
    final d = _ReviseLineDraft(date: _parseIso(l.date));
    d.regionCtrl.text = l.region ?? '';
    d.districtCtrl.text = l.district ?? '';
    d.siteCtrl.text = l.siteName ?? '';
    d.activityCtrl.text = l.activity ?? '';
    d.laborCtrl.text = l.laborCost > 0 ? '${l.laborCost}' : '';
    d.perDiemCtrl.text = l.perDiemCost > 0 ? '${l.perDiemCost}' : '';
    d.transportCtrl.text = l.transportFare > 0 ? '${l.transportFare}' : '';
    return d;
  }

  DateTime date;
  final regionCtrl = TextEditingController();
  final districtCtrl = TextEditingController();
  final siteCtrl = TextEditingController();
  final activityCtrl = TextEditingController();
  final laborCtrl = TextEditingController();
  final perDiemCtrl = TextEditingController();
  final transportCtrl = TextEditingController();

  int get labor => int.tryParse(laborCtrl.text.trim()) ?? 0;
  int get perDiem => int.tryParse(perDiemCtrl.text.trim()) ?? 0;
  int get transport => int.tryParse(transportCtrl.text.trim()) ?? 0;
  int get total => labor + perDiem + transport;

  void dispose() {
    regionCtrl.dispose();
    districtCtrl.dispose();
    siteCtrl.dispose();
    activityCtrl.dispose();
    laborCtrl.dispose();
    perDiemCtrl.dispose();
    transportCtrl.dispose();
  }

  PerDiemLine toLine(int seqNo) => PerDiemLine(
    seqNo: seqNo,
    date: _iso(date),
    region: regionCtrl.text.trim().isEmpty ? null : regionCtrl.text.trim(),
    district: districtCtrl.text.trim().isEmpty ? null : districtCtrl.text.trim(),
    siteName: siteCtrl.text.trim().isEmpty ? null : siteCtrl.text.trim(),
    activity: activityCtrl.text.trim().isEmpty ? null : activityCtrl.text.trim(),
    laborCost: labor,
    perDiemCost: perDiem,
    transportFare: transport,
  );
}

/// Section 8 of hypermed_claude_code_prompt.md: CTO day-by-day editing.
/// Sends the full day list on save (no from_seq_no) — the API always
/// recomputes from what's submitted, so a single-day edit or an add/remove
/// both work correctly this way; only the "provably untouched earlier
/// days" optimization is unused, not correctness. "Every CTO edit still
/// requires a reason."
class PerDiemReviseDialog extends StatefulWidget {
  const PerDiemReviseDialog({super.key, required this.request, required this.onClose, this.onSaved, this.isProposal = false});
  final PerDiemRequest request;
  final VoidCallback onClose;
  final VoidCallback? onSaved;
  // Technician mode: "a technician's edit does not take effect on its own —
  // it goes back to the CTO for approval" (Section 8). Same day-by-day
  // editor, different endpoint/copy/outcome.
  final bool isProposal;

  @override
  State<PerDiemReviseDialog> createState() => _PerDiemReviseDialogState();
}

class _PerDiemReviseDialogState extends State<PerDiemReviseDialog> {
  final _reasonCtrl = TextEditingController();
  late final List<_ReviseLineDraft> _lines = widget.request.lines.isEmpty
      ? [_ReviseLineDraft(date: DateTime.now())]
      : widget.request.lines.map(_ReviseLineDraft.fromLine).toList();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    final lastDate = _lines.isNotEmpty ? _lines.last.date : DateTime.now();
    setState(() => _lines.add(_ReviseLineDraft(date: lastDate.add(const Duration(days: 1)))));
  }

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines[i].dispose();
      _lines.removeAt(i);
    });
  }

  Future<void> _pickDate(int i) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lines[i].date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _lines[i].date = picked);
  }

  int get _grandTotal => _lines.fold(0, (s, l) => s + l.total);

  bool get _canSave => !_saving && _reasonCtrl.text.trim().length >= 10;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() { _saving = true; _error = null; });
    try {
      final lines = _lines.asMap().entries.map((e) => e.value.toLine(e.key + 1)).toList();
      if (widget.isProposal) {
        await PerDiemService.instance.proposeEdit(widget.request.id, reason: _reasonCtrl.text.trim(), lines: lines);
      } else {
        await PerDiemService.instance.revise(widget.request.id, reason: _reasonCtrl.text.trim(), lines: lines);
      }
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  Widget _miniField(String label, TextEditingController ctrl, {bool numeric = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabeledTextField(label: label, controller: ctrl, keyboardType: numeric ? TextInputType.number : TextInputType.text, onChanged: (_) => setState(() {})),
      ]);

  Widget _lineRow(int i) {
    final l = _lines[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.pal.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Day ${i + 1}', style: AppTheme.bodyStrong.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: () => _pickDate(i),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Symbols.calendar_month, size: 14, color: context.pal.textDim),
              const SizedBox(width: 4),
              Text(formatDate(l.date), style: AppTheme.bodySm.copyWith(fontSize: 11.5)),
            ]),
          ),
          const SizedBox(width: 12),
          if (_lines.length > 1)
            GestureDetector(
              onTap: () => _removeLine(i),
              child: Icon(Symbols.delete_outline, size: 16, color: AppColors.coral),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _miniField('Region', l.regionCtrl)),
          const SizedBox(width: 8),
          Expanded(child: _miniField('District', l.districtCtrl)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _miniField('Site', l.siteCtrl)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _miniField('Activity', l.activityCtrl)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _miniField('Labor (TSh)', l.laborCtrl, numeric: true)),
          const SizedBox(width: 8),
          Expanded(child: _miniField('Per Diem (TSh)', l.perDiemCtrl, numeric: true)),
          const SizedBox(width: 8),
          Expanded(child: _miniField('Transport (TSh)', l.transportCtrl, numeric: true)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wasPaid = widget.request.isPaid;
    // Opened via showDialog with a hand-built card, not a Dialog — so
    // nothing above it provides the Material its TextFields require.
    return Material(type: MaterialType.transparency, child: GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: const Color(0xAA06070A),
        alignment: Alignment.center,
        child: PhoneModalBox(scroll: false, child: GestureDetector(
          onTap: () {},
          child: Container(
            width: 640,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
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
                  Icon(Symbols.edit_calendar, size: 18, color: AppColors.teal),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                      '${widget.isProposal ? 'Propose Edit' : 'Edit Travel Plan'} — ${widget.request.destination}',
                      style: AppTheme.bodyStrong, overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: widget.onClose,
                      child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
                ]),
              ),
              Flexible(child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(children: [
                  if (widget.isProposal)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
                      ),
                      child: Row(children: [
                        Icon(Symbols.info, size: 14, color: AppColors.blue),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'This won\'t take effect until the CTO reviews and approves it — the plan keeps its current values until then.',
                          style: AppTheme.bodySm.copyWith(fontSize: 12, color: AppColors.blue),
                        )),
                      ]),
                    ),
                  if (wasPaid)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(Symbols.info, size: 14, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Money is already out for this plan. The original release amount is never rewritten — any change in cost will be recorded as a separate adjustment for finance.',
                          style: AppTheme.bodySm.copyWith(fontSize: 12, color: AppColors.amber),
                        )),
                      ]),
                    ),
                  if (_error != null) ...[
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                    ),
                  ],
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LabeledTextField(label: 'Reason for this edit *', controller: _reasonCtrl, onChanged: (_) => setState(() {}), hint: 'e.g. Re-routed to Iringa (min. 10 characters)'),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text('ITINERARY', style: AppTheme.labelCaps.copyWith(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: _addLine,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.add, size: 14, color: AppColors.teal),
                        const SizedBox(width: 3),
                        Text('Add Day', style: AppTheme.bodySub.copyWith(color: AppColors.teal, fontSize: 12)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ..._lines.asMap().keys.map(_lineRow),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.teal.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Expanded(child: Text('NEW TOTAL', style: AppTheme.labelCaps.copyWith(fontSize: 9), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      Text(tshShort(_grandTotal),
                          style: AppTheme.bodyStrong.copyWith(color: AppColors.teal, fontSize: 15)),
                    ]),
                  ),
                ]),
              )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Expanded(child: AppButton(label: 'Cancel', variant: BtnVariant.ghost, onPressed: widget.onClose)),
                  const SizedBox(width: 12),
                  Expanded(child: AppButton(
                    label: _saving ? 'Saving…' : (widget.isProposal ? 'Submit for Approval' : 'Save Changes'),
                    icon: Symbols.check,
                    variant: BtnVariant.primary,
                    onPressed: _canSave ? _save : null,
                  )),
                ]),
              ),
            ]),
          ),
        )),
      ),
    ));
  }
}
