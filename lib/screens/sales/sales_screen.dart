import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/sales_lead.dart';
import '../../services/sales_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import 'lead_detail_screen.dart';

Color _stageColor(PipelineStage s) => switch (s) {
  PipelineStage.lead          => AppColors.textMute,
  PipelineStage.qualified     => AppColors.green,
  PipelineStage.demoScheduled => AppColors.violet,
  PipelineStage.proposalSent  => AppColors.amber,
  PipelineStage.negotiation   => AppColors.coral,
  PipelineStage.won           => AppColors.green,
  PipelineStage.lost          => AppColors.textMute,
};

const _boardStages = [
  PipelineStage.lead, PipelineStage.qualified, PipelineStage.demoScheduled,
  PipelineStage.proposalSent, PipelineStage.negotiation, PipelineStage.won,
];

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, this.initialLeadId});
  final int? initialLeadId;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _showNewDeal = false;
  List<SalesLead> _leads  = [];
  bool            _loading = true;
  String?         _error;
  bool            _autoOpenedLead = false;
  String? _repFilter;
  String? _machineFilter;
  // Phone board: each stage takes 86% of the width, the next one peeks in.
  final _phonePager = PageController(viewportFraction: 0.86);

  @override
  void dispose() {
    _phonePager.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known pipeline board
    // immediately on a return visit instead of blanking to a spinner, then
    // quietly refresh in the background — see MachineService for the full
    // reasoning.
    final cached = SalesService.cachedDefaultList;
    if (cached != null) {
      _leads = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_leads.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await SalesService.instance.list();
      if (mounted) {
        setState(() { _leads = data; _loading = false; });
        if (!_autoOpenedLead && widget.initialLeadId != null) {
          _autoOpenedLead = true;
          final matches = data.where((l) => l.id == widget.initialLeadId);
          if (matches.isNotEmpty) {
            final lead = matches.first;
            WidgetsBinding.instance.addPostFrameCallback((_) => _openLead(lead));
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _openLead(SalesLead lead) async {
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id)));
    _load();
  }

  List<String> get _reps => _leads.map((l) => l.assigneeName).whereType<String>().toSet().toList()..sort();
  List<String> get _machines => _leads.map((l) => l.machineType).toSet().toList()..sort();

  List<SalesLead> get _filtered => _leads.where((l) {
    if (_repFilter != null && l.assigneeName != _repFilter) return false;
    if (_machineFilter != null && l.machineType != _machineFilter) return false;
    return true;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final leads = _filtered;

    final grouped = <PipelineStage, List<SalesLead>>{};
    for (final stage in PipelineStage.values) {
      grouped[stage] = leads.where((l) => l.stage == stage).toList();
    }

    final openLeads = leads.where((l) => l.stage != PipelineStage.lost && l.stage != PipelineStage.won).toList();
    final totalPipeline = openLeads.fold<int>(0, (s, l) => s + l.dealValue);
    final weighted = totalPipeline; // no per-stage win-probability data; shown as raw open value
    final stalled = openLeads.where((l) => l.daysInStage >= 90).length;

    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        final phone = isPhoneWidth(cst.maxWidth);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (phone) PhonePageHeader(
            title: 'Sales Pipeline',
            subtitle: '${openLeads.length} deals · ${tshFromDouble(totalPipeline)} open · $stalled stalled',
            primary: PageAction(label: 'New lead', shortLabel: 'New', icon: Symbols.add,
                onPressed: () => setState(() => _showNewDeal = true)),
            filters: [
              _filterDropdown(context, 'Rep', Symbols.person, _repFilter, _reps, (v) => setState(() => _repFilter = v)),
              _filterDropdown(context, 'Machine type', Symbols.medical_services, _machineFilter, _machines, (v) => setState(() => _machineFilter = v)),
            ],
          ) else Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sales Pipeline', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('${openLeads.length} deals · ${tshFromDouble(totalPipeline)} open · weighted ${tshFromDouble(weighted)} · $stalled stalled over 90 days', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              _filterDropdown(context, 'Rep', Symbols.person, _repFilter, _reps, (v) => setState(() => _repFilter = v)),
              const SizedBox(width: 8),
              _filterDropdown(context, 'Machine type', Symbols.medical_services, _machineFilter, _machines, (v) => setState(() => _machineFilter = v)),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => setState(() => _showNewDeal = true), icon: const Icon(Symbols.add, size: 16), label: const Text('New lead')),
            ]),
          ),
          SizedBox(height: phone ? 12 : 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          // A background refresh failing while stale-but-valid cached data
          // is already showing shouldn't blow that away.
          else if (_error != null && _leads.isEmpty)
            Expanded(child: ErrorView(message: _error!, onRetry: _load))
          // Phones: swipe through the stages, one column at a time, with
          // the next one peeking in so it's clear there's more.
          else if (phone)
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: PageView(
                  controller: _phonePager,
                  padEnds: false,
                  children: [
                    for (final stage in _boardStages)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                        child: _KanbanColumn(stage: stage, leads: grouped[stage] ?? [], totalOpen: totalPipeline,
                            onChanged: _load, onAddDeal: () => setState(() => _showNewDeal = true)),
                      ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                  child: IntrinsicHeight(child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _boardStages.map((stage) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _KanbanColumn(stage: stage, leads: grouped[stage] ?? [], totalOpen: totalPipeline, onChanged: _load, onAddDeal: () => setState(() => _showNewDeal = true)),
                      ),
                    )).toList(),
                  )),
                ),
              ),
            ),
        ]);
      }),

      // New Deal dialog
      if (_showNewDeal)
        _NewDealDialog(
          onClose: () => setState(() => _showNewDeal = false),
          onSaved: () { setState(() => _showNewDeal = false); _load(); },
        ),
    ]);
  }

  Widget _filterDropdown(BuildContext context, String label, IconData icon, String? value, List<String> options, ValueChanged<String?> onChanged) {
    final active = value != null;
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      color: context.pal.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.rMd), side: BorderSide(color: context.pal.border)),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(value: null, child: Text('All')),
        ...options.map((o) => PopupMenuItem<String?>(value: o, child: Text(o))),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.violet.withValues(alpha: 0.10) : context.pal.surface1,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? AppColors.violet.withValues(alpha: 0.5) : context.pal.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? AppColors.violet : context.pal.textDim),
          const SizedBox(width: 7),
          Text(value ?? label, style: AppTheme.bodySm.copyWith(fontSize: 12, color: active ? AppColors.violet : null)),
          const SizedBox(width: 5),
          Icon(Symbols.expand_more, size: 15, color: context.pal.textDim),
        ]),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({required this.stage, required this.leads, required this.totalOpen, required this.onChanged, required this.onAddDeal});
  final PipelineStage stage;
  final List<SalesLead> leads;
  final int totalOpen;
  final VoidCallback onChanged;
  final VoidCallback onAddDeal;

  Color get _dotColor => _stageColor(stage);

  Color? get _columnTint => switch (stage) {
    PipelineStage.won  => AppColors.greenSoft,
    PipelineStage.lost => AppColors.coralSoft,
    _                  => null,
  };

  Color? get _columnBorder => switch (stage) {
    PipelineStage.won  => AppColors.teal.withValues(alpha: 0.25),
    PipelineStage.lost => AppColors.coral.withValues(alpha: 0.25),
    _                  => null,
  };

  @override
  Widget build(BuildContext context) {
    final total = leads.fold<int>(0, (a, l) => a + l.dealValue);
    final share = totalOpen > 0 ? (total / totalOpen * 100).round() : 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 460),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _columnTint ?? context.pal.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _columnBorder ?? context.pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: _dotColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(child: Text(stage.label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5, color: stage == PipelineStage.won ? AppColors.green : context.pal.textMute), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(5)),
                child: Text('${leads.length}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(tshFromDouble(total), style: AppTheme.monoSm.copyWith(fontSize: 12.5)),
              if (stage != PipelineStage.won) ...[const SizedBox(width: 6), Text('$share%', style: AppTheme.bodySub.copyWith(fontSize: 10))],
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              ...leads.map((l) => _KanbanCard(lead: l, dotColor: _dotColor, onChanged: onChanged)),
              if (stage != PipelineStage.won)
                GestureDetector(
                  onTap: onAddDeal,
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: context.pal.border)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Symbols.add, size: 13, color: context.pal.textDim),
                      const SizedBox(width: 5),
                      Text('Add deal', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                    ]),
                  ),
                ),
            ]),
          )),
        ],
      ),
    );
  }
}

final _avatarPalette = [AppColors.cyan, AppColors.amber, AppColors.violet, AppColors.coral, AppColors.info, AppColors.green];

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.lead, required this.dotColor, required this.onChanged});
  final SalesLead lead;
  final Color dotColor;
  final VoidCallback onChanged;

  String get _initials {
    final parts = lead.contact.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  String? get _nextStep {
    if (lead.demoDate != null) return 'Next: demo ${lead.demoDate}';
    if (lead.followUpDate != null) return 'Next: follow up ${lead.followUpDate}';
    return null;
  }

  bool get _stalled => lead.daysInStage >= 90 || lead.isFollowUpDue;

  @override
  Widget build(BuildContext context) {
    final avatarColor = _avatarPalette[lead.id % _avatarPalette.length];
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id)));
        onChanged();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _stalled ? AppColors.amber.withValues(alpha: 0.35) : context.pal.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(lead.hospital, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () async {
                final changed = await showDialog<bool>(context: context, builder: (_) => _LeadEditDialog(lead: lead));
                if (changed == true) onChanged();
              },
              child: Icon(Symbols.edit, size: 13, color: context.pal.textMute),
            ),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            Container(
              width: 18, height: 18, alignment: Alignment.center,
              decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
              child: Text(_initials, style: AppTheme.monoXs.copyWith(fontSize: 8, fontWeight: FontWeight.w700, color: const Color(0xFF08090B))),
            ),
            const SizedBox(width: 7),
            Expanded(child: Text(lead.contact, style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(5)),
              child: Text(lead.machineType, style: AppTheme.monoXs.copyWith(fontSize: 9.5)),
            ),
            if (lead.source != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (lead.source == LeadSource.tender ? AppColors.violet : context.pal.textDim).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(lead.source!.label, style: AppTheme.monoXs.copyWith(
                    fontSize: 9.5, color: lead.source == LeadSource.tender ? AppColors.violet : context.pal.textMute)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(tshFromDouble(lead.dealValue), style: AppTheme.kpiValue.copyWith(fontSize: 16, color: dotColor)),
          const SizedBox(height: 8),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 7),
          Row(children: [
            Icon(_stalled ? Symbols.warning : Symbols.check_circle, size: 12, color: _stalled ? AppColors.amber : AppColors.green),
            const SizedBox(width: 6),
            Expanded(child: Text(
              _stalled ? '${lead.daysInStage}d in stage — stalled' : '${lead.daysInStage}d in stage',
              style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: _stalled ? AppColors.amber : AppColors.green),
            )),
          ]),
          if (_nextStep != null) ...[
            const SizedBox(height: 5),
            Text(_nextStep!, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
          ],
        ]),
      ),
    );
  }
}

// ── Lead edit dialog ───────────────────────────────────────────────────────

class _LeadEditDialog extends StatefulWidget {
  const _LeadEditDialog({required this.lead});
  final SalesLead lead;

  @override
  State<_LeadEditDialog> createState() => _LeadEditDialogState();
}

class _LeadEditDialogState extends State<_LeadEditDialog> {
  late String _stage;
  int? _assignedTo;
  DateTime? _followUpDate;
  DateTime? _closeDate;
  String _forecast = 'pipeline';
  List<StaffMember> _staff = [];
  bool _saving = false;
  bool _loadingStaff = true;

  static const _stageValues = [
    'lead', 'qualified', 'demo_scheduled', 'proposal_sent', 'negotiation', 'won', 'lost',
  ];
  static const _stageLabels = [
    'Lead', 'Qualified', 'Demo Scheduled', 'Proposal Sent', 'Negotiation', 'Won', 'Lost',
  ];

  @override
  void initState() {
    super.initState();
    _stage = switch (widget.lead.stage) {
      PipelineStage.lead          => 'lead',
      PipelineStage.qualified     => 'qualified',
      PipelineStage.demoScheduled => 'demo_scheduled',
      PipelineStage.proposalSent  => 'proposal_sent',
      PipelineStage.negotiation   => 'negotiation',
      PipelineStage.won           => 'won',
      PipelineStage.lost          => 'lost',
    };
    _assignedTo = widget.lead.assignedTo;
    _followUpDate = widget.lead.followUpDate != null ? DateTime.tryParse(widget.lead.followUpDate!) : null;
    _closeDate = widget.lead.expectedCloseDate != null ? DateTime.tryParse(widget.lead.expectedCloseDate!) : null;
    _forecast = widget.lead.forecastCategory.apiValue;
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await StaffService.instance.list();
      if (mounted) setState(() { _staff = staff; _loadingStaff = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await SalesService.instance.update(widget.lead.id, {
        'stage': _stage,
        'assigned_to': _assignedTo,
        'follow_up_date': _followUpDate != null ? _isoDate(_followUpDate!) : null,
        'expected_close_date': _closeDate != null ? _isoDate(_closeDate!) : null,
        'forecast_category': _forecast,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pal.surface1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Container(
      width: 460,
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.trending_up, size: 18, color: AppColors.teal),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.lead.hospital, style: AppTheme.bodyStrong)),
          GestureDetector(onTap: () => Navigator.pop(context),
              child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
        ]),
        const SizedBox(height: 4),
        Text('${widget.lead.contact} · ${widget.lead.machineType} · TSh ${(widget.lead.dealValue / 1e6).toStringAsFixed(0)}M',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        const SizedBox(height: 18),

        _SDrop(label: 'Stage', value: _stage, items: _stageValues, display: _stageLabels,
            onChanged: (v) => setState(() => _stage = v)),
        const SizedBox(height: 14),

        _RepDropdown(loading: _loadingStaff, staff: _staff, value: _assignedTo,
            onChanged: (v) => setState(() => _assignedTo = v)),
        const SizedBox(height: 14),
        _FollowUpField(label: 'Follow-up date', date: _followUpDate,
            onChanged: (d) => setState(() => _followUpDate = d)),
        const SizedBox(height: 14),
        _ForecastFields(
          closeDate: _closeDate, forecast: _forecast,
          onCloseDate: (d) => setState(() => _closeDate = d),
          onForecast: (v) => setState(() => _forecast = v),
        ),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(height: 38,
              decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                  borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('Cancel', style: AppTheme.bodySm))),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: _save,
            child: Container(height: 38,
              decoration: BoxDecoration(color: AppColors.teal,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(child: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Save', style: AppTheme.bodyStrong.copyWith(
                    color: const Color(0xFF06120F), fontSize: 13)))),
          )),
        ]),
      ]),
    ),
  );
}

// ── New Deal Dialog ────────────────────────────────────────────────────────

class _NewDealDialog extends StatefulWidget {
  const _NewDealDialog({required this.onClose, this.onSaved});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_NewDealDialog> createState() => _NewDealDialogState();
}

class _NewDealDialogState extends State<_NewDealDialog> {
  final _hospCtrl  = TextEditingController();
  final _contCtrl  = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _sourceNotesCtrl = TextEditingController();
  String  _machine = 'Hematology Analyzer';
  String  _stage   = 'lead';
  String  _source  = 'other';
  int?    _assignedTo;
  DateTime? _followUpDate;
  DateTime? _closeDate;
  String  _forecast = 'pipeline';
  List<StaffMember> _staff = [];
  bool   _loadingStaff = true;
  bool   _saving   = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await StaffService.instance.list();
      if (mounted) setState(() { _staff = staff; _loadingStaff = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  @override
  void dispose() {
    _hospCtrl.dispose(); _contCtrl.dispose(); _valueCtrl.dispose(); _sourceNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _hospCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await SalesService.instance.create({
        'hospital_name_raw': _hospCtrl.text.trim(),
        'contact_name_raw':  _contCtrl.text.trim(),
        'machine_type': _machine,
        'deal_value':  int.tryParse(_valueCtrl.text.replaceAll(',', '')) ?? 0,
        'stage':       _stage,
        'source':       _source,
        'source_notes': _sourceNotesCtrl.text.trim().isEmpty ? null : _sourceNotesCtrl.text.trim(),
        'assigned_to': _assignedTo,
        'follow_up_date': _followUpDate != null ? _isoDate(_followUpDate!) : null,
        'expected_close_date': _closeDate != null ? _isoDate(_closeDate!) : null,
        'forecast_category': _forecast,
      });
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 500,
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
                Icon(Symbols.trending_up, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('New Deal', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                _SField('Hospital / Client', _hospCtrl, 'e.g. Mwananyamala Regional Hospital'),
                const SizedBox(height: 14),
                _SField('Contact person', _contCtrl, 'e.g. Dr. James Mbeki'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _SDrop(
                    label: 'Machine Type',
                    value: _machine,
                    items: const ['Hematology Analyzer', 'Ultrasound Unit', 'Ventilator',
                        'ECG Machine', 'Patient Monitor', 'Defibrillator'],
                    onChanged: (v) => setState(() => _machine = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _SField('Deal Value (TSh)', _valueCtrl, '150000000', numeric: true)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _SDrop(
                    label: 'Stage',
                    value: _stage,
                    items: const ['lead', 'qualified', 'demo_scheduled', 'proposal_sent', 'negotiation'],
                    display: const ['Lead', 'Qualified', 'Demo Scheduled', 'Proposal Sent', 'Negotiation'],
                    onChanged: (v) => setState(() => _stage = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _RepDropdown(loading: _loadingStaff, staff: _staff, value: _assignedTo,
                        onChanged: (v) => setState(() => _assignedTo = v)),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _SDrop(
                    label: 'Source',
                    value: _source,
                    items: const ['referral', 'tender', 'inbound_call', 'walk_in', 'other'],
                    display: const ['Referral', 'Tender', 'Inbound Call', 'Walk-in', 'Other'],
                    onChanged: (v) => setState(() => _source = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _SField('Source Notes (optional)', _sourceNotesCtrl, 'e.g. tender ref #, referrer name')),
                ]),
                const SizedBox(height: 14),
                _FollowUpField(label: 'Follow-up date (optional)', date: _followUpDate,
                    onChanged: (d) => setState(() => _followUpDate = d)),
                const SizedBox(height: 14),
                _ForecastFields(
                  closeDate: _closeDate, forecast: _forecast,
                  onCloseDate: (d) => setState(() => _closeDate = d),
                  onForecast: (v) => setState(() => _forecast = v),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal,
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Create Deal', style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)))),
                )),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _SField extends StatelessWidget {
  const _SField(this.label, this.ctrl, this.hint, {this.numeric = false});
  final String label, hint;
  final TextEditingController ctrl;
  final bool numeric;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint, keyboardType: numeric ? TextInputType.number : TextInputType.text);
}

// Expected close date + the rep's forecast call — what the sales dashboard's
// quarter forecast is built from. Side by side, shared by both lead dialogs.
class _ForecastFields extends StatelessWidget {
  const _ForecastFields({required this.closeDate, required this.forecast,
      required this.onCloseDate, required this.onForecast});
  final DateTime? closeDate;
  final String forecast;
  final ValueChanged<DateTime?> onCloseDate;
  final ValueChanged<String> onForecast;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: LabeledDateField(
      label: 'Expected close',
      date: closeDate,
      placeholder: 'Not set',
      onClear: () => onCloseDate(null),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: closeDate ?? now,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now.add(const Duration(days: 365 * 3)),
        );
        if (picked != null) onCloseDate(picked);
      },
    )),
    const SizedBox(width: 14),
    Expanded(child: LabeledDropdown<String>(
      label: 'Forecast',
      value: forecast,
      items: [for (final c in ForecastCategory.values) c.apiValue],
      displayBuilder: (v) => parseForecastCategory(v).label,
      onChanged: (v) => onForecast(v),
    )),
  ]);
}

// Sales rep picker, shared by both lead dialogs.
class _RepDropdown extends StatelessWidget {
  const _RepDropdown({required this.loading, required this.staff, required this.value, required this.onChanged});
  final bool loading;
  final List<StaffMember> staff;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => LabeledDropdown<int?>(
    label: 'Sales rep',
    // A rep id the staff list doesn't (yet) contain would have no item to
    // show — fall back to Unassigned rather than breaking the dropdown.
    value: staff.any((s) => s.id == value) ? value : null,
    items: [null, for (final s in staff) s.id],
    displayBuilder: (id) => id == null ? (loading ? 'Loading…' : 'Unassigned') : staff.firstWhere((s) => s.id == id).name,
    onChanged: loading ? null : onChanged,
    enabled: !loading,
  );
}

// Follow-up date with a clear button, shared by both lead dialogs.
class _FollowUpField extends StatelessWidget {
  const _FollowUpField({required this.label, required this.date, required this.onChanged});
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => LabeledDateField(
    label: label,
    date: date,
    placeholder: 'No follow-up scheduled',
    onClear: () => onChanged(null),
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: date ?? now,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now.add(const Duration(days: 365 * 2)),
      );
      if (picked != null) onChanged(picked);
    },
  );
}

class _SDrop extends StatelessWidget {
  const _SDrop({required this.label, required this.value, required this.items,
      this.display, required this.onChanged});
  final String label, value;
  final List<String> items;
  final List<String>? display;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LabeledDropdown<String>(
    label: label,
    value: value,
    items: items,
    displayBuilder: (v) => display != null ? display![items.indexOf(v)] : v,
    onChanged: onChanged,
  );
}
