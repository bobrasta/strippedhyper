import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/sales_lead.dart';
import '../../services/sales_overview_service.dart';
import '../../services/sales_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/labeled_field.dart';

const activityTypes = <String, (String, IconData)>{
  'call':     ('Call', Symbols.call),
  'visit':    ('Visit', Symbols.location_on),
  'meeting':  ('Meeting', Symbols.groups),
  'demo':     ('Demo', Symbols.co_present),
  'email':    ('Email', Symbols.mail),
  'whatsapp': ('WhatsApp', Symbols.chat),
};

/// Log a call/visit/demo that happened, or plan one — a future date and time
/// shows up under "Up next" on the rep's dashboard. Returns true when saved.
Future<bool?> showLogActivityDialog(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _LogActivityDialog());

class _LogActivityDialog extends StatefulWidget {
  const _LogActivityDialog();

  @override
  State<_LogActivityDialog> createState() => _LogActivityDialogState();
}

class _LogActivityDialogState extends State<_LogActivityDialog> {
  final _subject = TextEditingController();
  final _client = TextEditingController();
  final _note = TextEditingController();
  String _type = 'call';
  int? _leadId;
  late DateTime _at;
  List<SalesLead> _leads = SalesService.cachedDefaultList ?? [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _at = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    SalesService.instance.list().then((l) { if (mounted) setState(() => _leads = l); }).catchError((_) {});
  }

  @override
  void dispose() {
    _subject.dispose(); _client.dispose(); _note.dispose();
    super.dispose();
  }

  List<SalesLead> get _openLeads => _leads.where((l) => l.stage != PipelineStage.won && l.stage != PipelineStage.lost).toList();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _at,
        firstDate: now.subtract(const Duration(days: 60)), lastDate: now.add(const Duration(days: 365)));
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_subject.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Say what the activity was.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await SalesOverviewService.instance.logActivity(
        type: _type, subject: _subject.text.trim(), occursAt: _at,
        leadId: _leadId, client: _client.text.trim(), note: _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  // Same box as LabeledDateField (the Settings field look), for the time.
  Widget _timeField() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Time', style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    GestureDetector(
      onTap: _pickTime,
      child: Container(
        height: fieldHeightOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: fieldBoxDecoration(context),
        child: Row(children: [
          Expanded(child: Text(formatTime(_at), style: AppTheme.fieldText.copyWith(color: context.pal.text))),
          Icon(Symbols.schedule, size: 15, color: context.pal.textDim),
        ]),
      ),
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final future = _at.isAfter(DateTime.now());
    return Dialog(
      backgroundColor: context.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.edit_note, size: 18, color: AppColors.cyan),
            const SizedBox(width: 10),
            Expanded(child: Text('Log activity', style: AppTheme.bodyStrong)),
            GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
          ]),
          const SizedBox(height: 4),
          Text('Record a call or visit, or plan one — a future time shows under "Up next".', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in activityTypes.entries)
              GestureDetector(
                onTap: () => setState(() => _type = e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _type == e.key ? AppColors.cyan.withValues(alpha: 0.14) : context.pal.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _type == e.key ? AppColors.cyan : context.pal.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(e.value.$2, size: 14, color: _type == e.key ? AppColors.cyan : context.pal.textDim),
                    const SizedBox(width: 6),
                    Text(e.value.$1, style: AppTheme.bodySm.copyWith(fontSize: 12, color: _type == e.key ? AppColors.cyan : null)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          LabeledTextField(controller: _subject, label: 'What', hint: 'e.g. Site visit — ultrasound room survey'),
          const SizedBox(height: 14),
          LabeledDropdown<int?>(
            label: 'Deal (optional)',
            value: _leadId,
            items: [null, for (final l in _openLeads) l.id],
            displayBuilder: (id) {
              if (id == null) return 'Not linked to a deal';
              final l = _openLeads.firstWhere((l) => l.id == id);
              return '${l.hospital} · ${l.machineType}';
            },
            onChanged: (v) => setState(() => _leadId = v),
          ),
          if (_leadId == null) ...[
            const SizedBox(height: 14),
            LabeledTextField(controller: _client, label: 'Client (optional)', hint: 'Hospital or clinic name'),
          ],
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: LabeledDateField(label: future ? 'Planned for' : 'When', date: _at, onTap: _pickDate)),
            const SizedBox(width: 12),
            SizedBox(width: 140, child: _timeField()),
          ]),
          const SizedBox(height: 14),
          LabeledTextField(controller: _note, label: 'Note (optional)', maxLines: 3),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(future ? 'Plan it' : 'Log it'),
            ),
          ]),
        ])),
      ),
    );
  }
}
