import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasStaffManageAuthority, hasTaskManageAuthority, roleDisplayName;
import '../../models/task_item.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/csv_export.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../widgets/common/labeled_field.dart';
import '../../theme/app_palette.dart';
import '../../services/role_service.dart';
import '../../models/permission.dart';
import '../../widgets/common/phone_layout.dart';

// ── Local data models ───────────────────────────────────────────────────────
class _Task {
  const _Task({
    required this.id,           required this.title,
    required this.type,         required this.priority,
    required this.status,       required this.hospital,
    required this.location,     required this.assigneeId,
    required this.assigneeName, required this.assigneeInitials,
    required this.assigneeVariant, required this.dueLabel,
    required this.dueTime,      required this.assignedAt,
    this.dbId,                  this.startedAt,
    this.completedAt,           this.isGeneral = false,
    this.rawTask,
  });
  final String id, title;
  final String type;      // 'field' | 'sales' | 'office' | 'finance' | 'cs' | 'general'
  final String priority;  // 'critical' | 'high' | 'medium' | 'low'
  final String status;    // 'overdue' | 'open' | 'in_progress' | 'resolved'
  final String hospital, location;
  final String assigneeId, assigneeName, assigneeInitials;
  final AvatarVariant assigneeVariant;
  final String dueLabel, dueTime, assignedAt;
  final int?      dbId;
  final String?   startedAt;
  final String?   completedAt;
  final bool      isGeneral;
  final TaskItem? rawTask;
}

class _TeamMember {
  const _TeamMember({
    required this.id,       required this.name,
    required this.initials, required this.role,
    required this.group,    required this.zone,
    required this.availStatus, required this.workload,
    required this.variant,  this.staffIntId,
  });
  final String id, name, initials, role, group, zone, availStatus;
  final double workload;
  final AvatarVariant variant;
  final int?    staffIntId;
}

// ── Screen ──────────────────────────────────────────────────────────────────
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, this.initialTaskId});
  final int? initialTaskId;
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  int _typeTab      = 0;
  int _selectedTask = 0;
  int _narrowPane   = 0;
  bool _autoSelectedTask = false;

  List<_TeamMember> _liveTeam         = [];
  List<_Task>       _liveGeneralTasks = [];

  bool _loadingTeam  = true;
  bool _loadingTasks = true;
  bool _showNewTask  = false;
  bool _showNewStaff = false;

  bool get _canManageStaff => hasStaffManageAuthority(userRoleNotifier.value);
  bool get _canManageTasks => hasTaskManageAuthority(userRoleNotifier.value);

  int?    _filterStaffId;
  String? _filterStaffName;

  List<_Task> get _allTasks => _liveGeneralTasks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadStaff(), _loadGeneralTasks()]);
    if (!_autoSelectedTask && widget.initialTaskId != null && mounted) {
      _autoSelectedTask = true;
      final idx = _allTasks.indexWhere((t) => t.isGeneral && t.dbId == widget.initialTaskId);
      if (idx >= 0) _selectTask(idx);
    }
  }

  Future<void> _loadStaff() async {
    try {
      final members = await StaffService.instance.list();
      if (mounted) {
        setState(() {
          _liveTeam    = members.map(_staffToTeamMember).toList();
          _loadingTeam = false;
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _loadingTeam = false); }
    }
  }

  Future<void> _loadGeneralTasks() async {
    setState(() => _loadingTasks = true);
    try {
      final items = await TaskService.instance.list();
      if (mounted) {
        setState(() {
          _liveGeneralTasks = items.map(_generalTaskToTask).toList();
          _loadingTasks     = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  // ── Model converters ──────────────────────────────────────────────────────
  static _TeamMember _staffToTeamMember(StaffMember s) => _TeamMember(
    id:          's${s.id}',
    name:        s.name,
    initials:    s.initials,
    role:        s.role,
    group:       s.group ?? 'office',
    zone:        s.zone ?? 'Dar es Salaam',
    availStatus: s.availStatus.label,
    workload:    s.workload,
    variant:     s.variant,
    staffIntId:  s.id,
  );

  static _Task _generalTaskToTask(TaskItem t) => _Task(
    id:               'GT-${t.id}',
    title:            t.title,
    type:             t.category,
    priority:         t.priority,
    status:           switch (t.status) {
      'in_progress' => 'in_progress',
      'completed'   => 'resolved',
      'overdue'     => 'overdue',
      _             => 'open',
    },
    hospital:         t.assigneeName ?? 'Unassigned',
    location:         t.taskType,
    assigneeId:       t.assignedTo != null ? 's${t.assignedTo}' : '—',
    assigneeName:     t.assigneeName ?? 'Unassigned',
    assigneeInitials: t.assigneeInitials ?? '?',
    assigneeVariant:  AvatarVariant.blue,
    dueLabel:         switch (t.status) {
      'overdue'     => 'Overdue',
      'in_progress' => 'In Progress',
      'completed'   => 'Done',
      _             => 'Open',
    },
    dueTime:          t.dueDate ?? t.createdAt.substring(0, 10),
    assignedAt:       t.createdAt,
    dbId:             t.id,
    startedAt:        t.startedAt,
    completedAt:      t.completedAt,
    isGeneral:        true,
    rawTask:          t,
  );

  // ── Task grouping ─────────────────────────────────────────────────────────
  // No 'field' tab: field-service task types are retired. Legacy tasks whose
  // category is still 'field' show under "All" with the generic colour.
  static const _typeKeys = ['', 'sales', 'office', 'finance', 'cs', 'general'];

  _Task? get _task {
    if (_allTasks.isEmpty) return null;
    return _allTasks[_selectedTask.clamp(0, _allTasks.length - 1)];
  }

  void _selectTask(int idx) => setState(() { _selectedTask = idx; _narrowPane = 1; });

  Map<String, List<({_Task task, int idx})>> get _grouped {
    final out = <String, List<({_Task task, int idx})>>{
      'Overdue': [], 'Open': [], 'In Progress': [], 'Done': [], 'Other': [],
    };
    for (int i = 0; i < _allTasks.length; i++) {
      final t = _allTasks[i];
      if (!(_typeTab == 0 || t.type == _typeKeys[_typeTab])) continue;
      if (_filterStaffId != null) {
        final match = t.assigneeId == 's$_filterStaffId';
        if (!match) continue;
      }
      final bucket = switch (t.dueLabel) {
        'Overdue'     => 'Overdue',
        'In Progress' => 'In Progress',
        'Open'        => 'Open',
        'Done'        => 'Done',
        _             => 'Other',
      };
      out[bucket]!.add((task: t, idx: i));
    }
    return out;
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  void _filterByStaff(int staffId, String staffName) {
    setState(() {
      if (_filterStaffId == staffId) {
        _filterStaffId   = null;
        _filterStaffName = null;
      } else {
        _filterStaffId   = staffId;
        _filterStaffName = staffName;
        _narrowPane      = 0;
      }
    });
  }

  Future<void> _assignTask(_TeamMember m) async {
    final task = _task;
    if (task == null || task.dbId == null) return;
    try {
      await TaskService.instance.update(task.dbId!, {'assigned_to': m.staffIntId});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${task.id} assigned to ${m.name}'),
          backgroundColor: AppColors.teal,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _startTask(_Task task) async {
    if (task.dbId == null || !task.isGeneral) return;
    try {
      await TaskService.instance.update(task.dbId!, {'status': 'in_progress'});
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _resolveTask(_Task task) async {
    if (task.dbId == null) return;
    try {
      await TaskService.instance.update(task.dbId!, {'status': 'completed'});
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _exportCsv() async {
    final grp     = _grouped;
    final visible = grp.values.expand((l) => l).map((e) => e.task).toList();
    final rawItems = visible
        .where((t) => t.isGeneral && t.rawTask != null)
        .map((t) => t.rawTask!)
        .toList();
    if (rawItems.isEmpty) {
      if (mounted) showErrorToast(context, Exception('No general tasks to export.'));
      return;
    }
    await CsvExport.tasks(rawItems, staffName: _filterStaffName);
  }

  // ── Builders ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final wide   = cst.maxWidth >= 1100;
      final medium = !wide && cst.maxWidth >= 660;
      if (wide)   return _buildWide();
      if (medium) return _buildMedium();
      return _buildNarrow();
    });
  }

  Widget _buildWide() => Stack(children: [
    Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 280, child: _TaskListPane(
        typeTab: _typeTab, onTypeTab: (i) => setState(() => _typeTab = i),
        grouped: _grouped, selectedIdx: _selectedTask, onSelect: _selectTask,
        onAdd: _canManageTasks ? () => setState(() => _showNewTask = true) : null,
        loading: _loadingTasks, onRefresh: _load,
        filterStaffName: _filterStaffName,
        onClearFilter: () => setState(() { _filterStaffId = null; _filterStaffName = null; }),
        onExport: _exportCsv,
      )),
      Expanded(flex: 7, child: _task == null
          ? _emptyDetail()
          : _TaskDetailPane(
              task: _task!,
              onAssign: () => _showTeamSheet(context),
              onStart:  () => _startTask(_task!),
              onDone:   () => _resolveTask(_task!),
            )),
      Expanded(flex: 5, child: _TeamAvailabilityPane(
        task: _task, team: _liveTeam, loadingTeam: _loadingTeam,
        onAssign: _assignTask,
        filterStaffId:   _filterStaffId,
        onFilterByStaff: _filterByStaff,
        onAddStaff: _canManageStaff ? () => setState(() => _showNewStaff = true) : null,
      )),
    ]),
    if (_showNewTask) _newTaskOverlay(),
    if (_showNewStaff) _newStaffOverlay(),
  ]);

  Widget _buildMedium() => Stack(children: [
    Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 260, child: _TaskListPane(
        typeTab: _typeTab, onTypeTab: (i) => setState(() => _typeTab = i),
        grouped: _grouped, selectedIdx: _selectedTask, onSelect: _selectTask,
        onAdd: _canManageTasks ? () => setState(() => _showNewTask = true) : null,
        loading: _loadingTasks, onRefresh: _load,
        filterStaffName: _filterStaffName,
        onClearFilter: () => setState(() { _filterStaffId = null; _filterStaffName = null; }),
        onExport: _exportCsv,
      )),
      Expanded(child: _task == null
          ? _emptyDetail()
          : _TaskDetailPane(
              task: _task!,
              onAssign: () => _showTeamSheet(context),
              onStart:  () => _startTask(_task!),
              onDone:   () => _resolveTask(_task!),
            )),
    ]),
    if (_showNewTask) _newTaskOverlay(),
  ]);

  Widget _buildNarrow() {
    final Widget content = switch (_narrowPane) {
      1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _NarrowBack(label: 'Tasks', onBack: () => setState(() => _narrowPane = 0)),
        Expanded(child: _task == null
            ? _emptyDetail()
            : _TaskDetailPane(
                task: _task!,
                onAssign: () => setState(() => _narrowPane = 2),
                onStart:  () => _startTask(_task!),
                onDone:   () => _resolveTask(_task!),
              )),
      ]),
      2 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _NarrowBack(label: 'Task Detail', onBack: () => setState(() => _narrowPane = 1)),
        Expanded(child: _TeamAvailabilityPane(
          task: _task, team: _liveTeam, loadingTeam: _loadingTeam,
          onAssign: (m) { _assignTask(m); setState(() => _narrowPane = 1); },
          filterStaffId:   _filterStaffId,
          onFilterByStaff: _filterByStaff,
          onAddStaff: _canManageStaff ? () => setState(() => _showNewStaff = true) : null,
        )),
      ]),
      _ => _TaskListPane(
        typeTab: _typeTab, onTypeTab: (i) => setState(() => _typeTab = i),
        grouped: _grouped, selectedIdx: _selectedTask, onSelect: _selectTask,
        onAdd: _canManageTasks ? () => setState(() => _showNewTask = true) : null,
        loading: _loadingTasks, onRefresh: _load,
        filterStaffName: _filterStaffName,
        onClearFilter: () => setState(() { _filterStaffId = null; _filterStaffName = null; }),
        onExport: _exportCsv,
      ),
    };
    return Stack(children: [
      content,
      if (_showNewTask) _newTaskOverlay(),
      if (_showNewStaff) _newStaffOverlay(),
    ]);
  }

  Widget _emptyDetail() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Symbols.task_alt, size: 40, color: context.pal.textDim),
    const SizedBox(height: 12),
    Text('No task selected', style: AppTheme.bodySub),
    const SizedBox(height: 8),
    Text('Select a task from the list to view details.',
        style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim)),
  ]));

  Widget _newTaskOverlay() => _NewTaskDialog(
    teamMembers: _liveTeam,
    onClose: () => setState(() => _showNewTask = false),
    onSaved: () { setState(() => _showNewTask = false); _loadGeneralTasks(); },
  );

  Widget _newStaffOverlay() => _NewStaffDialog(
    onClose: () => setState(() => _showNewStaff = false),
    onSaved: () {
      setState(() => _showNewStaff = false);
      StaffService.instance.invalidateCache();
      _loadStaff();
    },
  );

  void _showTeamSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      backgroundColor: ctx.pal.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, ctrl) => _TeamAvailabilityPane(
          task: _task, team: _liveTeam, loadingTeam: _loadingTeam,
          scrollController: ctrl,
          onAssign: (m) { Navigator.pop(ctx); _assignTask(m); },
          filterStaffId:   _filterStaffId,
          onFilterByStaff: _filterByStaff,
        ),
      ),
    );
  }
}

// ── Task list pane ──────────────────────────────────────────────────────────
class _TaskListPane extends StatelessWidget {
  const _TaskListPane({
    required this.typeTab, required this.onTypeTab,
    required this.grouped, required this.selectedIdx, required this.onSelect,
    this.onAdd, this.loading = false, this.onRefresh,
    this.filterStaffName, this.onClearFilter, this.onExport,
  });

  final int typeTab;
  final ValueChanged<int> onTypeTab;
  final Map<String, List<({_Task task, int idx})>> grouped;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;
  final bool loading;
  final Future<void> Function()? onRefresh;
  final String?      filterStaffName;
  final VoidCallback? onClearFilter;
  final VoidCallback? onExport;

  static const _tabs = ['All', 'Sales', 'Office', 'Finance', 'CS', 'General'];
  static List<Color> get _tabColors => [
    AppColors.textMute, AppColors.violet,
    AppColors.blue, AppColors.amber, AppColors.coral, AppColors.textDim,
  ];

  @override
  Widget build(BuildContext context) {
    final totalTasks = grouped.values.fold(0, (s, l) => s + l.length);
    final overdue    = grouped['Overdue']!.length;

    return Container(
      decoration: BoxDecoration(
        color: context.pal.sidebarBg,
        border: Border(right: BorderSide(color: context.pal.border)),
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
          child: Row(children: [
            Text('Tasks', style: AppTheme.pageTitle.copyWith(fontSize: 15)),
            const SizedBox(width: 6),
            _Pill('$totalTasks', AppColors.teal),
            if (overdue > 0) ...[
              const SizedBox(width: 4),
              _Pill('$overdue overdue', AppColors.coral),
            ],
            const Spacer(),
            if (onExport != null)
              GestureDetector(
                onTap: onExport,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Symbols.download, size: 16, color: context.pal.textDim),
                ),
              ),
            if (onAdd != null)
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.teal, borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Symbols.add, size: 16, color: Color(0xFF06120F)),
                ),
              ),
          ]),
        ),

        // Staff filter chip
        if (filterStaffName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.violet.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Symbols.person, size: 12, color: AppColors.violet),
                const SizedBox(width: 5),
                Expanded(child: Text(filterStaffName!,
                    style: AppTheme.monoXs.copyWith(color: AppColors.violet, fontSize: 10),
                    overflow: TextOverflow.ellipsis)),
                GestureDetector(
                  onTap: onClearFilter,
                  child: Icon(Symbols.close, size: 13, color: AppColors.violet),
                ),
              ]),
            ),
          ),

        const SizedBox(height: 10),

        // Type tabs
        SizedBox(
          height: 32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _tabs.length,
            itemBuilder: (_, i) {
              final active = typeTab == i;
              final color  = _tabColors[i];
              return GestureDetector(
                onTap: () => onTypeTab(i),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: active ? color.withValues(alpha: 0.4) : context.pal.border)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (i > 0) ...[
                      Container(width: 6, height: 6,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                    ],
                    Text(_tabs[i], style: AppTheme.bodySm.copyWith(
                      fontSize: 11.5,
                      color: active ? color : context.pal.textMute,
                      fontWeight: FontWeight.w500,
                    )),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // Task groups
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : RefreshIndicator(
                  onRefresh: onRefresh ?? () async {},
                  child: grouped.values.every((l) => l.isEmpty)
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Symbols.task_alt, size: 32, color: context.pal.textDim),
                              const SizedBox(height: 8),
                              Text('No tasks', style: AppTheme.bodySub),
                            ])),
                          ),
                        ])
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            for (final entry in grouped.entries)
                              if (entry.value.isNotEmpty)
                                _TaskGroup(
                                  label: entry.key, items: entry.value,
                                  selectedIdx: selectedIdx, onSelect: onSelect,
                                ),
                          ],
                        ),
                ),
        ),
      ]),
    );
  }
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    required this.label, required this.items,
    required this.selectedIdx, required this.onSelect,
  });
  final String label;
  final List<({_Task task, int idx})> items;
  final int selectedIdx;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = switch (label) {
      'Overdue'     => AppColors.coral,
      'In Progress' => AppColors.teal,
      'Open'        => AppColors.amber,
      'Done'        => AppColors.blue,
      _             => AppColors.textDim,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: AppTheme.monoXs.copyWith(color: labelColor, letterSpacing: 0.08)),
          const SizedBox(width: 6),
          Text('${items.length}',
              style: AppTheme.monoXs.copyWith(color: labelColor.withValues(alpha: 0.6))),
        ]),
      ),
      ...items.map((e) => _TaskListItem(
        task: e.task, selected: selectedIdx == e.idx,
        onTap: () => onSelect(e.idx),
      )),
    ]);
  }
}

class _TaskListItem extends StatelessWidget {
  const _TaskListItem({required this.task, required this.selected, required this.onTap});
  final _Task task;
  final bool selected;
  final VoidCallback onTap;

  Color get _priorityColor => switch (task.priority) {
    'critical' => AppColors.coral,
    'high'     => AppColors.amber,
    'medium'   => AppColors.blue,
    _          => AppColors.textDim,
  };

  Color get _typeColor => switch (task.type) {
    'sales'   => AppColors.violet,
    'office'  => AppColors.blue,
    'finance' => AppColors.amber,
    'cs'      => AppColors.coral,
    _         => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
      decoration: BoxDecoration(
        color: selected ? context.pal.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? context.pal.borderStrong : Colors.transparent),
      ),
      child: Row(children: [
        Container(
          width: 3, height: 44,
          margin: const EdgeInsets.only(left: 6, right: 8),
          decoration: BoxDecoration(
              color: _priorityColor, borderRadius: BorderRadius.circular(2)),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(task.type.toUpperCase(),
                  style: AppTheme.monoXs.copyWith(fontSize: 9, color: _typeColor)),
            ),
            if (task.isGeneral) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('TASK',
                    style: AppTheme.monoXs.copyWith(fontSize: 9, color: AppColors.blue)),
              ),
            ],
            const Spacer(),
            Text(task.dueTime,
                style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textDim)),
          ]),
          const SizedBox(height: 5),
          Text(task.title,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(
              fontSize: 11.5, fontWeight: FontWeight.w500,
              color: selected ? context.pal.text : context.pal.textMute,
            )),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 3),
            Flexible(child: Text(task.assigneeName, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 10))),
            const SizedBox(width: 6),
            AvatarWidget(initials: task.assigneeInitials, size: 16,
                variant: task.assigneeVariant),
          ]),
        ])),
      ]),
    ),
  );
}

// ── Task detail pane ────────────────────────────────────────────────────────
class _TaskDetailPane extends StatelessWidget {
  const _TaskDetailPane({
    required this.task,
    this.onAssign, this.onStart, this.onDone,
  });

  final _Task task;
  final VoidCallback? onAssign;
  final VoidCallback? onStart;
  final VoidCallback? onDone;

  Color get _typeColor => switch (task.type) {
    'sales'   => AppColors.violet,
    'office'  => AppColors.blue,
    'finance' => AppColors.amber,
    'cs'      => AppColors.coral,
    _         => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final isResolved = task.status == 'resolved';
    final canStart   = task.isGeneral && task.status == 'open';
    final isStarted  = task.status == 'in_progress';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              _Badge(task.id, AppColors.teal, AppColors.tealSoft),
              _Badge(task.type.toUpperCase(), _typeColor, _typeColor.withValues(alpha: 0.12)),
              _PriorityBadge(task.priority),
              _StatusBadge(task.status),
              if (task.isGeneral)
                _Badge(task.location, AppColors.blue, AppColors.blueSoft),
            ]),
            const SizedBox(height: 10),
            Text(task.title, style: AppTheme.pageTitle.copyWith(fontSize: 15.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _InfoPill(Symbols.person, task.assigneeName),
              _InfoPill(Symbols.calendar_today,
                  task.isGeneral ? 'Due ${task.dueTime}' : task.dueTime),
            ]),
          ])),
          const SizedBox(width: 12),
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (canStart)
              AppButton(label: 'Start Task', icon: Symbols.play_arrow,
                  variant: BtnVariant.normal, small: true, onPressed: onStart),
            if (canStart) const SizedBox(height: 6),
            if (!isResolved)
              AppButton(label: 'Mark Done', icon: Symbols.check_circle,
                  variant: BtnVariant.primary, small: true, onPressed: onDone),
            const SizedBox(height: 6),
            AppButton(label: 'Assign', icon: Symbols.group_add,
                variant: BtnVariant.normal, small: true, onPressed: onAssign),
          ]),
        ]),
        const SizedBox(height: 20),

        // Assignee card
        _SectionCard(
          icon: Symbols.person,
          title: 'Assigned To',
          child: Row(children: [
            AvatarWidget(initials: task.assigneeInitials, size: 36,
                variant: task.assigneeVariant),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.assigneeName == '—' ? 'Unassigned' : task.assigneeName,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 14)),
              const SizedBox(height: 3),
              Text(task.isGeneral ? task.location : task.hospital,
                  style: AppTheme.bodySub.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ])),
            if (task.assigneeName == '—' || task.assigneeName == 'Unassigned')
              GestureDetector(
                onTap: onAssign,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.teal.withValues(alpha: 0.3))),
                  child: Text('Assign now', style: AppTheme.bodySm.copyWith(
                      color: AppColors.teal, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        // Timeline (general tasks only)
        if (task.isGeneral) ...[
          _SectionCard(
            icon: Symbols.timeline,
            title: 'Timeline',
            child: _Timeline(
              assignedAt:  task.assignedAt,
              startedAt:   task.startedAt,
              completedAt: task.completedAt,
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Details grid
        _SectionCard(
          icon: Symbols.info,
          title: 'Details',
          child: Wrap(spacing: 20, runSpacing: 12, children: [
            _SchedItem(Symbols.tag,       'ID',       task.id),
            _SchedItem(Symbols.category,  'Type',     task.type.toUpperCase()),
            _SchedItem(Symbols.flag,      'Priority', task.priority.toUpperCase()),
            if (task.isGeneral)
              _SchedItem(Symbols.task_alt, 'Task',    task.location),
            _SchedItem(Symbols.schedule,  task.isGeneral ? 'Due Date' : 'Reported', task.dueTime),
          ]),
        ),
        const SizedBox(height: 24),

        // Bottom action row
        if (!isResolved)
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: onAssign,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  border: Border.all(color: context.pal.border),
                  borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('Reassign',
                    style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
              ),
            )),
            if (canStart) ...[
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: onStart,
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.blue, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Symbols.play_arrow, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Start Task', style: AppTheme.bodyStrong.copyWith(
                        color: Colors.white, fontSize: 13)),
                  ]),
                ),
              )),
            ],
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: onDone,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.teal, borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(
                      color: AppColors.teal.withValues(alpha: 0.3), blurRadius: 12)]),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Symbols.check_circle, size: 16, color: Color(0xFF06120F)),
                  const SizedBox(width: 8),
                  Text(isStarted ? 'Mark Complete' : 'Mark Done',
                      style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)),
                ]),
              ),
            )),
          ])
        else
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.tealSoft, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.3))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Symbols.check_circle, size: 16, color: AppColors.teal),
              const SizedBox(width: 8),
              Text('Completed', style: AppTheme.bodyStrong.copyWith(
                  color: AppColors.teal, fontSize: 13)),
            ]),
          ),
      ]),
    );
  }
}

// ── Timeline widget ─────────────────────────────────────────────────────────
class _Timeline extends StatelessWidget {
  const _Timeline({required this.assignedAt, this.startedAt, this.completedAt});
  final String  assignedAt;
  final String? startedAt;
  final String? completedAt;

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.day} ${_months[local.month - 1]} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    _TimeStep(label: 'ASSIGNED',    timestamp: _fmt(assignedAt),  done: true,               isLast: false),
    _TimeStep(label: 'IN PROGRESS', timestamp: _fmt(startedAt),   done: startedAt != null,  isLast: false),
    _TimeStep(label: 'COMPLETED',   timestamp: _fmt(completedAt), done: completedAt != null, isLast: true),
  ]);
}

class _TimeStep extends StatelessWidget {
  const _TimeStep({
    required this.label, required this.timestamp,
    required this.done,  required this.isLast,
  });
  final String label, timestamp;
  final bool done, isLast;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.teal : context.pal.textDim;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: done ? AppColors.teal : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        if (!isLast)
          Container(width: 1.5, height: 34, color: context.pal.border),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTheme.monoXs.copyWith(
              fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(timestamp, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          SizedBox(height: isLast ? 0 : 16),
        ]),
      )),
    ]);
  }
}

// ── Team availability pane ──────────────────────────────────────────────────
class _TeamAvailabilityPane extends StatelessWidget {
  const _TeamAvailabilityPane({
    required this.task, required this.team, required this.onAssign,
    this.loadingTeam = false, this.scrollController,
    this.filterStaffId, this.onFilterByStaff, this.onAddStaff,
  });
  final _Task? task;
  final List<_TeamMember> team;
  final bool loadingTeam;
  final ValueChanged<_TeamMember> onAssign;
  final ScrollController? scrollController;
  final int?                          filterStaffId;
  final void Function(int, String)?   onFilterByStaff;
  final VoidCallback?                 onAddStaff;

  static const _groups = [
    ('office', 'Office & Sales'),
    ('field',  'Field staff'),
    ('admin',  'Admin & External'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        border: Border(left: BorderSide(color: context.pal.border)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Expanded(child: Text('Team Availability', style: AppTheme.bodyStrong.copyWith(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (onAddStaff != null) ...[
                GestureDetector(
                  onTap: onAddStaff,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(6)),
                    child: Icon(Symbols.person_add, size: 13, color: AppColors.teal),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: AppColors.teal, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 6)]),
              ),
              const SizedBox(width: 5),
              Text('Live', style: AppTheme.monoXs.copyWith(color: AppColors.teal)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Tap a person to filter task list',
                style: AppTheme.monoXs.copyWith(
                    color: filterStaffId != null ? AppColors.violet : context.pal.textDim,
                    fontSize: 9.5)),
          ),

          if (loadingTeam)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (team.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.group_off, size: 32, color: context.pal.textDim),
                const SizedBox(height: 8),
                Text('No staff loaded', style: AppTheme.bodySub),
              ])),
            )
          else
            for (final grp in _groups) ...[
              if (team.any((m) => m.group == grp.$1)) ...[
                _GroupHeader(grp.$2),
                ...team.where((m) => m.group == grp.$1).map((m) => _TeamMemberRow(
                  member: m, currentTask: task, onAssign: onAssign,
                  isFiltered: filterStaffId == m.staffIntId,
                  onFilter: onFilterByStaff != null && m.staffIntId != null
                      ? () => onFilterByStaff!(m.staffIntId!, m.name)
                      : null,
                )),
              ],
            ],

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.pal.surface2, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.pal.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Symbols.auto_fix_high, size: 13, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Auto-route Rules', style: AppTheme.bodyStrong.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: AppColors.tealSoft, borderRadius: BorderRadius.circular(4)),
                    child: Text('Active',
                        style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 9.5)),
                  ),
                ]),
                const SizedBox(height: 8),
                _AutoRule(Symbols.business_center, 'Office & account tasks',
                    'Account owner →team-lead fallback'),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Narrow back bar ─────────────────────────────────────────────────────────
class _NarrowBack extends StatelessWidget {
  const _NarrowBack({required this.label, required this.onBack});
  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onBack,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.pal.border))),
      child: Row(children: [
        Icon(Symbols.arrow_back, size: 16, color: AppColors.teal),
        const SizedBox(width: 8),
        Text(label, style: AppTheme.bodySub.copyWith(color: AppColors.teal)),
      ]),
    ),
  );
}

// ── Section card ────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.teal),
          const SizedBox(width: 8),
          Text(title, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(16), child: child),
    ]),
  );
}

// ── Group header ────────────────────────────────────────────────────────────
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: Text(label.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.08)),
  );
}

// ── Team member row ─────────────────────────────────────────────────────────
class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({
    required this.member, required this.currentTask, required this.onAssign,
    this.isFiltered = false, this.onFilter,
  });
  final _TeamMember member;
  final _Task? currentTask;
  final ValueChanged<_TeamMember> onAssign;
  final bool         isFiltered;
  final VoidCallback? onFilter;

  Color get _statusColor => switch (member.availStatus) {
    'Available' => AppColors.teal,
    'On task'   => AppColors.blue,
    'Assigned'  => AppColors.violet,
    'At desk'   => AppColors.teal,
    'Busy'      => AppColors.amber,
    _           => AppColors.textDim,
  };

  bool get _isAssigned => currentTask != null && member.id == currentTask!.assigneeId;
  bool get _canAssign  =>
      member.availStatus == 'Available' || member.availStatus == 'At desk';

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onFilter,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isFiltered
            ? AppColors.violet.withValues(alpha: 0.08)
            : _isAssigned ? AppColors.violetSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isFiltered
            ? AppColors.violet.withValues(alpha: 0.4)
            : _isAssigned
                ? AppColors.violet.withValues(alpha: 0.35)
                : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            AvatarWidget(initials: member.initials, size: 30, variant: member.variant),
            if (_canAssign || _isAssigned)
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.teal, shape: BoxShape.circle,
                    border: Border.all(color: context.pal.surface1, width: 1.5)),
                ),
              ),
          ]),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member.name, style: AppTheme.bodySm.copyWith(
              fontSize: 11.5, fontWeight: FontWeight.w600,
              color: isFiltered ? AppColors.violet
                  : _isAssigned ? AppColors.violet : context.pal.text),
              overflow: TextOverflow.ellipsis),
            Text('${roleDisplayName(member.role)} · ${member.zone}',
                style: AppTheme.bodySub.copyWith(fontSize: 10)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4)),
            child: Text(_isAssigned ? 'Assigned' : member.availStatus,
              style: AppTheme.monoXs.copyWith(
                color: _isAssigned ? AppColors.violet : _statusColor, fontSize: 9.5)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: member.workload, minHeight: 3,
                backgroundColor: context.pal.surface3,
                valueColor: AlwaysStoppedAnimation(_workloadColor(member.workload)),
              ),
            ),
          ])),
          const SizedBox(width: 10),
          if (_canAssign && !_isAssigned)
            GestureDetector(
              onTap: () => onAssign(member),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft, borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.teal.withValues(alpha: 0.3))),
                child: Text('Assign', style: AppTheme.bodySm.copyWith(
                    color: AppColors.teal, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ),
            ),
          if (_isAssigned)
            GestureDetector(
              onTap: () => onAssign(member),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.violetSoft, borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.violet.withValues(alpha: 0.3))),
                child: Text('Reassign', style: AppTheme.bodySm.copyWith(
                    color: AppColors.violet, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ]),
    ),
  );

  Color _workloadColor(double v) {
    if (v >= 0.85) return AppColors.coral;
    if (v >= 0.6)  return AppColors.amber;
    return AppColors.teal;
  }
}

// ── Small helpers ───────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge(this.label, this.fg, this.bg);
  final String label; final Color fg, bg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: AppTheme.bodySub.copyWith(
        color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: AppTheme.monoXs.copyWith(
        color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      'in_progress' => (AppColors.teal,  AppColors.tealSoft,  'Active'),
      'overdue'     => (AppColors.coral, AppColors.coralSoft, 'Overdue'),
      'resolved'    => (AppColors.blue,  AppColors.blueSoft,  'Completed'),
      _             => (AppColors.amber, AppColors.amberSoft, 'Open'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: AppTheme.bodySub.copyWith(
          color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge(this.priority);
  final String priority;
  @override
  Widget build(BuildContext context) {
    final (Color c, String l) = switch (priority) {
      'critical' => (AppColors.coral,      'Critical'),
      'high'     => (AppColors.amber,      'High'),
      'medium'   => (AppColors.blue,       'Medium'),
      _          => (context.pal.textDim,  'Low'),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(l, style: AppTheme.bodySub.copyWith(
          color: c, fontSize: 10, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.icon, this.label);
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.pal.surface2, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.pal.border)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: context.pal.textDim),
      const SizedBox(width: 5),
      Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11)),
    ]),
  );
}

class _SchedItem extends StatelessWidget {
  const _SchedItem(this.icon, this.label, this.value);
  final IconData icon; final String label, value;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: context.pal.textDim),
    const SizedBox(width: 6),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: AppTheme.monoXs.copyWith(fontSize: 9, color: context.pal.textDim)),
      Text(value, style: AppTheme.bodySm.copyWith(fontSize: 12)),
    ]),
  ]);
}

class _AutoRule extends StatelessWidget {
  const _AutoRule(this.icon, this.type, this.rule);
  final IconData icon; final String type, rule;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 12, color: context.pal.textDim),
    const SizedBox(width: 6),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(type, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
      Text(rule, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
    ])),
  ]);
}

// ── New Task Dialog ─────────────────────────────────────────────────────────
class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog({required this.teamMembers, required this.onClose, this.onSaved});
  final List<_TeamMember> teamMembers;
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  _TeamMember? _assignee;
  String    _category = 'general';
  String    _taskType = 'Custom Task';
  String    _priority = 'High';
  DateTime? _dueDate;
  bool      _saving  = false;
  String?   _error;

  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
  ];
  static const _categoryLabels = {
    'sales':   'Sales',
    'finance': 'Finance',
    'office':  'Office',
    'cs':      'CS',
    'general': 'General',
  };

  @override
  void initState() {
    super.initState();
    if (widget.teamMembers.isNotEmpty) {
      _assignee = widget.teamMembers.first;
      _setDefaults(_assignee!.role);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  void _setDefaults(String role) {
    _category = TaskItem.defaultCategoryForRole(role);
    _taskType = TaskItem.typesByCategory[_category]!.first;
  }

  void _onAssigneeChanged(_TeamMember m) {
    setState(() {
      _assignee = m;
      _setDefaults(m.role);
    });
  }

  void _onCategoryChanged(String cat) {
    setState(() {
      _category = cat;
      _taskType = TaskItem.typesByCategory[cat]!.first;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (_dueDate == null) {
      setState(() => _error = 'Due date is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await TaskService.instance.create({
        'title':       _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        'category':    _category,
        'task_type':   _taskType,
        'priority':    _priority.toLowerCase(),
        'assigned_to': _assignee?.staffIntId,
        'due_date':    _dueDate!.toIso8601String().substring(0, 10),
      });
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
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
          width: 520,
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(
                color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.task_alt, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('New Task', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(children: [
                // Row 1: Assign To + Category
                Row(children: [
                  Expanded(child: widget.teamMembers.isEmpty
                    ? _TF('Assign To', TextEditingController(), 'No staff available')
                    : _memberDrop()),
                  const SizedBox(width: 14),
                  Expanded(child: _TDrop(
                    label: 'Category',
                    value: _category,
                    items: _categoryLabels.keys.toList(),
                    display: _categoryLabels.values.toList(),
                    onChanged: _onCategoryChanged,
                  )),
                ]),
                const SizedBox(height: 14),

                // Row 2: Task Type + Priority
                Row(children: [
                  Expanded(child: _TDrop(
                    label: 'Task Type',
                    value: _taskType,
                    items: TaskItem.typesByCategory[_category]!,
                    onChanged: (v) => setState(() => _taskType = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _TDrop(
                    label: 'Priority',
                    value: _priority,
                    items: const ['Critical', 'High', 'Medium', 'Low'],
                    onChanged: (v) => setState(() => _priority = v),
                  )),
                ]),
                const SizedBox(height: 14),

                // Title
                _TF('Title (required)', _titleCtrl, 'e.g. Prepare Q2 reconciliation report'),
                const SizedBox(height: 14),

                // Due Date
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Due date (required)', style: AppTheme.fieldLabel),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.pal.surface2, borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _dueDate == null && _error != null
                                ? AppColors.coral : context.pal.border)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        Icon(Symbols.calendar_today, size: 14, color: context.pal.textDim),
                        const SizedBox(width: 8),
                        Text(
                          _dueDate != null
                            ? '${_dueDate!.day} ${_months[_dueDate!.month - 1]} ${_dueDate!.year}'
                            : 'Select due date—',
                          style: AppTheme.bodySm.copyWith(
                            color: _dueDate != null ? context.pal.text : context.pal.textDim),
                        ),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Description
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabeledTextField(label: 'Description', controller: _descCtrl, maxLines: 3, hint: 'Optional details…'),
                ]),

                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.error_outline, size: 14, color: AppColors.coral),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!,
                      style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12))),
                  ]),
                ],
              ]),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(20),
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
                    decoration: BoxDecoration(
                        color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Create Task', style: AppTheme.bodyStrong.copyWith(
                          color: const Color(0xFF06120F), fontSize: 13)))),
                )),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );

  // ~200 staff — client-side combobox per Section 4 of
  // hypermed_claude_code_prompt.md, searchable by name/role/zone, not just
  // name (replaces the plain DropdownButton "New Task > Assign to" field).
  Widget _memberDrop() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ASSIGN TO', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
      const SizedBox(height: 6),
      AppSearchableSelectField<String>(
        selectedLabel: _assignee?.name,
        items: widget.teamMembers.map((m) => AppSelectItem(
          value: m.id,
          label: '${m.name} — ${roleDisplayName(m.role)}${m.zone.isNotEmpty ? ' — ${m.zone}' : ''}',
          leading: AvatarWidget(initials: m.initials, size: 18, variant: m.variant),
        )).toList(),
        onSelected: (item) {
          if (item == null) return;
          final m = widget.teamMembers.firstWhere((m) => m.id == item.value);
          _onAssigneeChanged(m);
        },
      ),
    ]);
  }
}

// ── New staff dialog ────────────────────────────────────────────────────────
class _NewStaffDialog extends StatefulWidget {
  const _NewStaffDialog({required this.onClose, this.onSaved});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_NewStaffDialog> createState() => _NewStaffDialogState();
}

class _NewStaffDialogState extends State<_NewStaffDialog> {
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _zoneCtrl   = TextEditingController();
  final _salaryCtrl = TextEditingController();
  String  _role   = 'sales';
  bool    _saving = false;
  String? _error;

  // Roles come from the Role Builder (roles table) — no hard-coded list —
  // and display in ALL CAPS.
  List<String> _roles = [for (final r in RoleService.cachedList ?? const <RoleSummary>[]) r.name];

  @override
  void initState() {
    super.initState();
    RoleService.instance.list().then((list) {
      if (!mounted) return;
      setState(() {
        _roles = [for (final r in list) r.name];
        if (_roles.isNotEmpty && !_roles.contains(_role)) _role = _roles.first;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _zoneCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
      setState(() => _error = 'A valid email is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await StaffService.instance.create({
        'name':  _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        'role':  _role,
        'zone':  _zoneCtrl.text.trim().isNotEmpty ? _zoneCtrl.text.trim() : null,
        'base_salary': int.tryParse(_salaryCtrl.text.trim()),
      });
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = friendlyError(e); });
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
          width: 480,
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(
                color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.person_add, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Add Staff Member', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(children: [
                _TF('Full Name', _nameCtrl, 'e.g. Amina Juma'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _TF('Email', _emailCtrl, 'amina@hypermed.tz')),
                  const SizedBox(width: 14),
                  Expanded(child: _TF('Phone (optional)', _phoneCtrl, '+255…')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _TDrop(
                    label: 'Role',
                    value: _role,
                    items: _roles.isEmpty ? [_role] : _roles,
                    display: (_roles.isEmpty ? [_role] : _roles).map(roleDisplayName).toList(),
                    onChanged: (v) => setState(() => _role = v),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _TF('Zone (optional)', _zoneCtrl, 'Dar es Salaam')),
                ]),
                const SizedBox(height: 14),
                _TF('Base Salary (TZS, optional)', _salaryCtrl, 'e.g. 600000'),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Symbols.info, size: 13, color: context.pal.textDim),
                  const SizedBox(width: 6),
                  Expanded(child: Text('A temporary password is generated —the new user should change it on first login.',
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim))),
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.error_outline, size: 14, color: AppColors.coral),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_error!,
                      style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12))),
                  ]),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                    decoration: BoxDecoration(
                        color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Add Staff', style: AppTheme.bodyStrong.copyWith(
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

// ── Dialog field helpers ────────────────────────────────────────────────────
class _TF extends StatelessWidget {
  const _TF(this.label, this.ctrl, this.hint);
  final String label, hint;
  final TextEditingController ctrl;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint);
}

class _TDrop extends StatelessWidget {
  const _TDrop({
    required this.label, required this.value, required this.items,
    this.display, required this.onChanged,
  });
  final String label, value;
  final List<String>  items;
  final List<String>? display;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<String>(
      value: items.contains(value) ? value : items.first,
      items: items.asMap().entries.map((e) => DropdownMenuItem(
          value: e.value,
          child: Text(display != null ? display![e.key] : e.value),
        )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}
