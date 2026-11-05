import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasSalesApprovalAuthority;
import '../../models/sales_lead.dart';
import '../../services/sales_service.dart';
import '../../services/sales_team_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import 'quotations_screen.dart';
import '../../widgets/common/labeled_field.dart';

const _stageFlow = [
  PipelineStage.lead, PipelineStage.qualified, PipelineStage.demoScheduled,
  PipelineStage.proposalSent, PipelineStage.negotiation, PipelineStage.won,
];

String _stageApiValue(PipelineStage s) => switch (s) {
  PipelineStage.lead          => 'lead',
  PipelineStage.qualified     => 'qualified',
  PipelineStage.demoScheduled => 'demo_scheduled',
  PipelineStage.proposalSent  => 'proposal_sent',
  PipelineStage.negotiation   => 'negotiation',
  PipelineStage.won           => 'won',
  PipelineStage.lost          => 'lost',
};

class LeadDetailScreen extends StatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});
  final int leadId;

  @override
  State<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends State<LeadDetailScreen> {
  SalesLead? _lead;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineDetailScreen's own
    // fix: show the last-known version of this exact lead instantly if
    // we have one cached, then quietly refresh, instead of blanking to a
    // spinner on every navigation regardless of how fast the underlying
    // fetch resolves.
    final cached = SalesService.cachedById[widget.leadId];
    if (cached != null) { _lead = cached; _loading = false; }
    _load();
  }

  @override
  void didUpdateWidget(LeadDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.leadId != widget.leadId) {
      // A different lead — must not keep showing the previous one's data
      // under the new ID. Seed from that ID's own cache entry (which may
      // be null), then refresh.
      final cached = SalesService.cachedById[widget.leadId];
      setState(() { _lead = cached; _loading = cached == null; _error = null; });
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      if (_lead == null) _loading = true;
      _error = null;
    });
    try {
      final lead = await SalesService.instance.get(widget.leadId);
      if (mounted) setState(() { _lead = lead; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _changeStage(PipelineStage stage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SalesService.instance.moveStage(widget.leadId, _stageApiValue(stage));
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNotes(String notes) async {
    try {
      await SalesService.instance.update(widget.leadId, {'notes': notes});
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _reassign() async {
    final lead = _lead;
    if (lead == null) return;
    List<TeamMember> team;
    try {
      final (t, _) = await SalesTeamService.instance.load();
      team = t;
    } catch (e) {
      if (mounted) showErrorToast(context, e);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<TeamMember>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: const Text('Reassign lead'),
        content: SizedBox(width: 340, child: team.isEmpty
            ? Text('No reps on your team yet.', style: AppTheme.bodySub)
            : Column(mainAxisSize: MainAxisSize.min, children: team.map((m) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.name, style: AppTheme.bodySm),
                subtitle: Text(m.email, style: AppTheme.bodySub.copyWith(fontSize: 11)),
                onTap: () => Navigator.of(dialogCtx).pop(m),
              )).toList())),
        actions: [TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel'))],
      ),
    );
    if (picked == null) return;
    try {
      await SalesService.instance.update(lead.id, {'assigned_to': picked.id});
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _convertToQuotation() async {
    final lead = _lead;
    if (lead == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QuotationBuilderScreen(prefillFromLead: lead)));
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    final isManager = hasSalesApprovalAuthority(userRoleNotifier.value);

    return Scaffold(
      backgroundColor: context.pal.bg,
      appBar: AppBar(
        backgroundColor: context.pal.surface1,
        foregroundColor: context.pal.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: lead == null ? const Text('Lead') : Row(mainAxisSize: MainAxisSize.min, children: [
          Text(lead.hospital, style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
            child: Text('LEAD-${lead.id.toString().padLeft(4, '0')}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: AppColors.violet)),
          ),
        ]),
        actions: lead == null ? null : [
          if (!lead.stage.name.contains('won') && lead.stage != PipelineStage.lost)
            OutlinedButton.icon(
              onPressed: _convertToQuotation,
              icon: const Icon(Symbols.description, size: 15),
              label: const Text('Convert to quotation'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          // A background refresh erroring while stale-but-valid cached data
          // is already showing shouldn't blow that away — only the
          // "genuinely nothing to show" case surfaces the error screen.
          : lead == null
              ? (_error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : const SizedBox.shrink())
              : LayoutBuilder(builder: (ctx, cst) {
                      final wide = cst.maxWidth >= 900;
                      final left = _leftColumn(context, lead);
                      final right = _rightColumn(context, lead, isManager);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: wide
                            ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(flex: 3, child: left),
                                const SizedBox(width: 16),
                                SizedBox(width: 340, child: right),
                              ]))
                            : Column(children: [left, const SizedBox(height: 16), right]),
                      );
                    }),
    );
  }

  Widget _leftColumn(BuildContext context, SalesLead lead) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Stage stepper
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('STAGE', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
            const SizedBox(width: 9),
            Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
            if (lead.isDemoOverdue)
              Text('demo overdue', style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.amber)),
          ]),
          const SizedBox(height: 14),
          if (lead.stage == PipelineStage.lost)
            Text('Lost', style: AppTheme.bodyStrong.copyWith(color: AppColors.coral))
          else
            Row(children: _stageFlow.map((s) {
              final idx = _stageFlow.indexOf(s);
              final currentIdx = _stageFlow.indexOf(lead.stage);
              final reached = lead.stage == PipelineStage.won || currentIdx >= idx;
              final isCurrent = lead.stage == s;
              return Expanded(child: GestureDetector(
                onTap: _busy ? null : () => _changeStage(s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 13, height: 13, decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reached ? AppColors.violet : context.pal.surface2,
                      border: Border.all(color: reached ? AppColors.violet : context.pal.border),
                    )),
                    if (idx < _stageFlow.length - 1)
                      Expanded(child: Container(width: double.infinity, height: 2, color: currentIdx > idx ? AppColors.violet : context.pal.border)),
                  ]),
                  const SizedBox(height: 5),
                  Text(s.label, style: AppTheme.bodySub.copyWith(fontSize: 10, color: isCurrent ? context.pal.text : context.pal.textMute), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ));
            }).toList()),
        ]),
      ),
      const SizedBox(height: 14),
      // Stage history
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.history, size: 14, color: AppColors.violet),
            const SizedBox(width: 8),
            Expanded(child: Text('Stage history', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
            Text('${lead.events.length + 1} events · ${lead.daysOpen} days open', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
          ]),
          const SizedBox(height: 12),
          _eventRow(context, Symbols.add_circle, context.pal.textMute, 'Lead created',
              lead.assigneeName != null ? 'Assigned to ${lead.assigneeName}' : null, lead.createdAt),
          for (final e in lead.events.reversed)
            _eventRow(context, e.type == 'reassigned' ? Symbols.swap_horiz : Symbols.arrow_forward,
                AppColors.violet, e.title, e.note, e.at),
        ]),
      ),
    ],
  );

  Widget _eventRow(BuildContext context, IconData icon, Color color, String title, String? note, DateTime? at) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: AppTheme.bodySm.copyWith(fontSize: 12))),
          if (at != null) Text(formatDate(at), style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textMute)),
        ]),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
        ],
      ])),
    ]),
  );

  Widget _rightColumn(BuildContext context, SalesLead lead, bool isManager) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Deal panel
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DEAL', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
          const SizedBox(height: 11),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DEAL VALUE', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
              const SizedBox(height: 4),
              Text(tshFromDouble(lead.dealValue.toDouble()), style: AppTheme.kpiValue.copyWith(fontSize: 22)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('MACHINE', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
              const SizedBox(height: 4),
              Text(lead.machineType, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            ]),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 10, children: [
            _metaField(context, 'OWNER', lead.assigneeName ?? 'Unassigned'),
            _metaField(context, 'SOURCE', lead.source?.label ?? '—'),
            if (lead.demoDate != null) _metaField(context, 'DEMO DATE', lead.demoDate!, color: lead.isDemoOverdue ? AppColors.amber : null),
            if (lead.followUpDate != null) _metaField(context, 'FOLLOW-UP', lead.followUpDate!, color: lead.isFollowUpDue ? AppColors.amber : null),
            if (lead.expectedCloseDate != null) _metaField(context, 'EXPECTED CLOSE', lead.expectedCloseDate!),
            _metaField(context, 'FORECAST', lead.forecastCategory.label,
                color: lead.forecastCategory == ForecastCategory.commit ? AppColors.teal
                    : lead.forecastCategory == ForecastCategory.bestCase ? AppColors.amber : null),
            _metaField(context, 'DAYS OPEN', '${lead.daysOpen}'),
            if ((lead.sourceNotes ?? '').isNotEmpty) _metaField(context, 'SOURCE NOTES', lead.sourceNotes!),
          ]),
        ]),
      ),
      const SizedBox(height: 14),

      if (lead.isFollowUpDue)
        _warningBanner(context, 'Follow-up date passed',
            'Follow-up was due ${lead.followUpDate} and hasn\'t been re-dated.'),
      if (lead.isFollowUpDue) const SizedBox(height: 14),

      if (isManager) ...[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.violet.withValues(alpha: 0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.groups, size: 14, color: AppColors.violet),
              const SizedBox(width: 8),
              Text('Manager actions', style: AppTheme.bodySm.copyWith(fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _reassign,
              icon: const Icon(Symbols.swap_horiz, size: 14),
              label: const Text('Reassign'),
            )),
          ]),
        ),
        const SizedBox(height: 14),
      ],

      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: _NotesEditor(initial: lead.notes ?? '', onSave: _saveNotes),
      ),
    ],
  );

  Widget _metaField(BuildContext context, String label, String value, {Color? color}) => SizedBox(
    width: 140,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textMute)),
      const SizedBox(height: 3),
      Text(value, style: AppTheme.bodySm.copyWith(fontSize: 12, color: color ?? context.pal.text), maxLines: 2, overflow: TextOverflow.ellipsis),
    ]),
  );

  Widget _warningBanner(BuildContext context, String title, String body) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.amber.withValues(alpha: 0.3))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Symbols.warning, size: 17, color: AppColors.amber),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTheme.bodySm.copyWith(fontSize: 12)),
        const SizedBox(height: 3),
        Text(body, style: AppTheme.bodySub.copyWith(fontSize: 11)),
      ])),
    ]),
  );
}

class _NotesEditor extends StatefulWidget {
  const _NotesEditor({required this.initial, required this.onSave});
  final String initial;
  final Future<void> Function(String) onSave;

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(_ctrl.text.trim());
    if (mounted) setState(() { _saving = false; _editing = false; });
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('NOTES', style: AppTheme.labelCaps.copyWith(fontSize: 11)),
    const SizedBox(height: 10),
    _editing
        ? LabeledTextField(label: '', controller: _ctrl, maxLines: 6, hint: 'Notes on this deal…')
        : Text(widget.initial.isEmpty ? 'No notes yet.' : widget.initial,
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, height: 1.5)),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: _saving ? null : (_editing ? _save : () => setState(() => _editing = true)),
      icon: Icon(_editing ? Symbols.check : Symbols.edit_note, size: 14),
      label: Text(_saving ? 'Saving…' : (_editing ? 'Save note' : 'Edit note')),
    )),
  ]);
}
