import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/leave_request.dart';
import '../../services/hr_setting_service.dart';
import '../../services/leave_service.dart';
import '../../services/position_service.dart';
import '../../services/public_holiday_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';

/// HR Settings — ported from HR Redesign spec 1j: two columns instead of
/// one long scroll (Leave allocations + General defaults on the left,
/// Holiday calendar + Positions on the right).
class HrSettingsScreen extends StatefulWidget {
  const HrSettingsScreen({super.key});

  @override
  State<HrSettingsScreen> createState() => _HrSettingsScreenState();
}

class _HrSettingsScreenState extends State<HrSettingsScreen> {
  List<LeaveTypeCatalogEntry> _leaveTypes = [];
  List<PublicHoliday> _holidays = [];
  List<Position> _positions = [];
  bool _loading = true;
  String? _error;

  final Map<String, TextEditingController> _settingCtrls = {};
  bool _savingSettings = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning.
    final cachedTypes = LeaveService.cachedTypes;
    final cachedHolidays = PublicHolidayService.cachedDefaultList;
    final cachedSettings = HrSettingService.cachedSettings;
    final cachedPositions = PositionService.cachedList;
    if (cachedTypes != null) _leaveTypes = cachedTypes;
    if (cachedHolidays != null) _holidays = cachedHolidays;
    if (cachedPositions != null) _positions = cachedPositions;
    if (cachedSettings != null) {
      for (final entry in cachedSettings.entries) {
        _settingCtrls.putIfAbsent(entry.key, () => TextEditingController()).text = entry.value;
      }
    }
    if (cachedTypes != null || cachedHolidays != null || cachedSettings != null || cachedPositions != null) {
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _settingCtrls.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_leaveTypes.isEmpty && _holidays.isEmpty && _positions.isEmpty && _settingCtrls.isEmpty) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final results = await Future.wait([
        LeaveService.instance.types(),
        PublicHolidayService.instance.list(),
        HrSettingService.instance.get(),
        PositionService.instance.list(force: true),
      ]);
      if (!mounted) return;
      final settings = results[2] as Map<String, String>;
      for (final entry in settings.entries) {
        _settingCtrls.putIfAbsent(entry.key, () => TextEditingController()).text = entry.value;
      }
      setState(() {
        _leaveTypes = results[0] as List<LeaveTypeCatalogEntry>;
        _holidays   = results[1] as List<PublicHoliday>;
        _positions  = results[3] as List<Position>;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _saveLeaveTypeDays(LeaveTypeCatalogEntry type, int days) async {
    try {
      await LeaveService.instance.updateType(type.id, {'default_days_per_year': days});
      if (mounted) { showSuccessToast(context, '${type.label} updated.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _savingSettings = true);
    try {
      final payload = { for (final e in _settingCtrls.entries) e.key: e.value.text.trim() };
      await HrSettingService.instance.update(payload);
      if (mounted) { showSuccessToast(context, 'Settings saved.'); setState(() => _savingSettings = false); }
    } catch (e) {
      if (mounted) { setState(() => _savingSettings = false); showErrorToast(context, e); }
    }
  }

  Future<void> _addHoliday() async {
    final nameCtrl = TextEditingController();
    DateTime? date;
    bool recurring = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('New Public Holiday', style: AppTheme.cardTitle),
        content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledTextField(label: 'Name', controller: nameCtrl),
          const SizedBox(height: 12),
          LabeledDateField(
            label: 'Date',
            date: date,
            onTap: () async {
              final picked = await showDatePicker(context: dialogCtx, initialDate: date ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (picked != null) setDialogState(() => date = picked);
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Checkbox(value: recurring, onChanged: (v) => setDialogState(() => recurring = v ?? false)),
            const Text('Recurs every year'),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || date == null) return;
              try {
                await PublicHolidayService.instance.create({
                  'name': nameCtrl.text.trim(),
                  'date': date!.toIso8601String().split('T').first,
                  'recurring': recurring,
                });
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
              } catch (e) {
                if (dialogCtx.mounted) showErrorToast(dialogCtx, e);
              }
            },
            child: const Text('Add'),
          ),
        ],
      )),
    );
    if (created == true) _load();
  }

  Future<void> _deleteHoliday(PublicHoliday h) async {
    try {
      await PublicHolidayService.instance.delete(h.id);
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  // Positions feed the picker on the Staff/Recruitment "New Vacancy"
  // forms — HR owns this catalog since HR runs recruiting, same authority
  // tier (hasStaffManageAuthority) as everything else on this screen.
  Future<void> _addOrEditPosition({Position? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final deptCtrl = TextEditingController(text: existing?.department ?? '');
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text(existing == null ? 'New Position' : 'Edit Position', style: AppTheme.cardTitle),
        content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledTextField(label: 'Title', controller: titleCtrl),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Department (optional)', controller: deptCtrl),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              try {
                final data = {
                  'title': titleCtrl.text.trim(),
                  'department': deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : null,
                };
                if (existing == null) {
                  await PositionService.instance.create(data);
                } else {
                  await PositionService.instance.update(existing.id, data);
                }
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
              } catch (e) {
                if (dialogCtx.mounted) showErrorToast(dialogCtx, e);
              }
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    if (go == true) _load();
  }

  Future<void> _deletePosition(Position p) async {
    try {
      await PositionService.instance.delete(p.id);
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  static Color _leaveTypeColor(String key) => switch (key) {
    'annual' => AppColors.amber,
    'sick' => const Color(0xFFD97706),
    'maternity' => AppColors.violet,
    'compassionate' => AppColors.cyan,
    'public_holiday' => AppColors.info,
    _ => AppColors.teal,
  };

  static List<Color> get _deptPalette => [AppColors.teal, AppColors.violet, AppColors.amber, AppColors.info, AppColors.coral, AppColors.cyan];
  Color _deptColor(String? dept) => dept == null ? AppColors.teal : _deptPalette[dept.hashCode.abs() % _deptPalette.length];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _leaveTypes.isEmpty && _holidays.isEmpty && _positions.isEmpty && _settingCtrls.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final wide = cst.maxWidth >= 900;
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 32, decoration: BoxDecoration(color: context.pal.textMute, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('HR Settings', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
                const SizedBox(height: 3),
                Text('Leave allocations, holiday calendar, positions and defaults', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              FilledButton.icon(
                onPressed: _savingSettings ? null : _saveSettings,
                icon: _savingSettings
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Symbols.save, size: 16),
                label: const Text('Save all'),
              ),
            ]),
            const SizedBox(height: 20),
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _leftColumn(context)),
                    const SizedBox(width: 20),
                    Expanded(child: _rightColumn(context)),
                  ])
                : Column(children: [_leftColumn(context), const SizedBox(height: 20), _rightColumn(context)]),
          ]),
        ),
      );
    });
  }

  Widget _leftColumn(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _SectionCard(
      title: 'Leave day allocations', icon: Symbols.event, accent: AppColors.amber,
      child: Column(children: _leaveTypes.map((t) => _LeaveTypeRow(
        type: t, color: _leaveTypeColor(t.key),
        onSave: (days) => _saveLeaveTypeDays(t, days),
      )).toList()),
    ),
    const SizedBox(height: 20),
    _SectionCard(
      title: 'General defaults', icon: Symbols.tune, accent: AppColors.cyan,
      trailing: FilledButton(
        onPressed: _savingSettings ? null : _saveSettings,
        child: _savingSettings
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save'),
      ),
      child: LayoutBuilder(builder: (ctx, cst) {
        final twoUp = cst.maxWidth >= 320;
        final fields = [
          _SettingField(label: 'Default probation period', unit: 'days', ctrl: _settingCtrls['default_probation_days']),
          _SettingField(label: 'Alert lead time before expiry', unit: 'days', ctrl: _settingCtrls['reminder_lead_days']),
          _SettingField(label: 'Expected start time', unit: '', ctrl: _settingCtrls['expected_start_time']),
          _SettingField(label: 'Expected end time', unit: '', ctrl: _settingCtrls['expected_end_time']),
        ];
        if (!twoUp) return Column(children: [for (final f in fields) ...[f, const SizedBox(height: 12)]]..removeLast());
        return Wrap(spacing: 14, runSpacing: 14, children: fields.map((f) => SizedBox(width: (cst.maxWidth - 14) / 2, child: f)).toList());
      }),
    ),
  ]);

  Widget _rightColumn(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _SectionCard(
      title: 'Public holiday calendar', icon: Symbols.calendar_month, accent: AppColors.info,
      count: _holidays.length,
      trailing: TextButton.icon(onPressed: _addHoliday, icon: const Icon(Symbols.add, size: 15), label: const Text('Add')),
      child: _holidays.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No holidays added yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : Column(children: _holidays.asMap().entries.map((e) {
              final h = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: e.key == _holidays.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider))),
                child: Row(children: [
                  Text(h.date, style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(h.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
                  if (h.recurring) Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                    child: Text('yearly', style: AppTheme.monoXs.copyWith(color: AppColors.info, fontSize: 9.5)),
                  ),
                  GestureDetector(onTap: () => _deleteHoliday(h), child: Icon(Symbols.delete_outline, size: 15, color: context.pal.textDim)),
                ]),
              );
            }).toList()),
    ),
    const SizedBox(height: 20),
    _SectionCard(
      title: 'Positions', icon: Symbols.badge, accent: AppColors.cyan,
      count: _positions.length,
      trailing: TextButton.icon(onPressed: () => _addOrEditPosition(), icon: const Icon(Symbols.add, size: 15), label: const Text('Add')),
      child: _positions.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No positions yet — add one so Staff and Recruitment can assign it.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
          : Column(children: _positions.asMap().entries.map((e) {
              final p = e.value;
              final color = _deptColor(p.department);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: e.key == _positions.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider))),
                child: Row(children: [
                  Expanded(child: Text(p.title, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
                  if (p.department != null) Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                    child: Text(p.department!, style: AppTheme.monoXs.copyWith(color: color, fontSize: 9.5)),
                  ),
                  GestureDetector(onTap: () => _addOrEditPosition(existing: p), child: Icon(Symbols.edit, size: 15, color: context.pal.textDim)),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => _deletePosition(p), child: Icon(Symbols.delete_outline, size: 15, color: context.pal.textDim)),
                ]),
              );
            }).toList()),
    ),
  ]);
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child, this.trailing, required this.accent, this.count});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Color accent;
  final int? count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 15, color: accent),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 11)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
        ],
        const Spacer(),
        ?trailing,
      ]),
      const SizedBox(height: 14),
      child,
    ]),
  );
}

class _LeaveTypeRow extends StatefulWidget {
  const _LeaveTypeRow({required this.type, required this.onSave, required this.color});
  final LeaveTypeCatalogEntry type;
  final Color color;
  final ValueChanged<int> onSave;

  @override
  State<_LeaveTypeRow> createState() => _LeaveTypeRowState();
}

class _LeaveTypeRowState extends State<_LeaveTypeRow> {
  late final _ctrl = TextEditingController(text: widget.type.defaultDaysPerYear.toString());

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.type.label, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
      if (widget.type.autoFromCalendar)
        Text('From calendar', style: AppTheme.bodySub.copyWith(fontSize: 11.5))
      else if (widget.type.requiresManualDays)
        Text('Set at approval', style: AppTheme.bodySub.copyWith(fontSize: 11.5))
      else ...[
        SizedBox(
          width: 90,
          child: CellField(controller: _ctrl, keyboardType: TextInputType.number, suffixText: 'days'),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            final v = int.tryParse(_ctrl.text.trim());
            if (v != null) widget.onSave(v);
          },
          child: Icon(Symbols.check, size: 17, color: AppColors.teal),
        ),
      ],
    ]),
  );
}

class _SettingField extends StatelessWidget {
  const _SettingField({required this.label, required this.ctrl, this.unit = ''});
  final String label;
  final TextEditingController? ctrl;
  final String unit;

  @override
  Widget build(BuildContext context) =>
      LabeledTextField(label: unit.isEmpty ? label : '$label ($unit)', controller: ctrl!);
}
