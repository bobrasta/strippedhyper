import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/permission.dart';
import '../../services/setting_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common/fullscreen_editor_shell.dart';

const _kLayoutKey = 'roles_graph_layout_json';

List<Color> get _rolePalette => [
  AppColors.teal, AppColors.violet, AppColors.amber,
  AppColors.coral, AppColors.info, const Color(0xFFF472B6), const Color(0xFFFB923C),
];

/// Read-only(ish) bipartite graph of Roles <-> Permission modules, built
/// from the same live RoleService/PermissionService data the card view
/// (_rolesTab) already shows — this is a different lens on the same data,
/// not a separate source of truth. Node positions are draggable and persist
/// (own Setting key) purely for layout convenience; granting/revoking
/// permissions still happens through the existing Role Builder cards.
class RolesGraphView extends StatefulWidget {
  const RolesGraphView({
    super.key,
    required this.roles,
    required this.catalog,
    required this.overrides,
  });
  final List<RoleSummary> roles;
  final Map<String, List<PermissionCatalogItem>> catalog;
  final List<UserPermissionOverride> overrides;

  @override
  State<RolesGraphView> createState() => _RolesGraphViewState();
}

class _RolesGraphViewState extends State<RolesGraphView> {
  final _transform = TransformationController();
  final Map<String, Offset> _rolePos = {};
  final Map<String, Offset> _modulePos = {};
  String? _selectedRole;
  String? _selectedModule;

  bool _maximized = false;
  OverlayEntry? _overlayEntry;

  late Map<String, String> _keyToModule;
  late Map<String, Set<String>> _roleModules; // role name -> module set
  late Map<String, Map<String, List<String>>> _roleModuleKeys; // role -> module -> keys

  @override
  void initState() {
    super.initState();
    _computeGraph();
    _loadLayout();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  void _toggleMaximize() {
    if (_maximized) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() => _maximized = false);
    } else {
      final entry = OverlayEntry(builder: (_) => FullscreenEditorShell(
        title: 'Roles & Permissions Graph',
        onClose: _toggleMaximize,
        toolbar: const SizedBox.shrink(),
        child: _buildContent(),
      ));
      _overlayEntry = entry;
      Overlay.of(context).insert(entry);
      setState(() => _maximized = true);
    }
  }

  @override
  void didUpdateWidget(covariant RolesGraphView old) {
    super.didUpdateWidget(old);
    if (old.roles != widget.roles || old.catalog != widget.catalog) {
      _computeGraph();
    }
  }

  void _computeGraph() {
    _keyToModule = {};
    widget.catalog.forEach((module, items) {
      for (final item in items) {
        _keyToModule[item.key] = module;
      }
    });

    _roleModules = {};
    _roleModuleKeys = {};
    for (final role in widget.roles) {
      final modules = <String>{};
      final byModule = <String, List<String>>{};
      for (final key in role.permissionKeys) {
        final module = _keyToModule[key] ?? 'other';
        modules.add(module);
        byModule.putIfAbsent(module, () => []).add(key);
      }
      _roleModules[role.name] = modules;
      _roleModuleKeys[role.name] = byModule;
    }

    const roleColW = 210.0, roleRowH = 74.0;
    for (var i = 0; i < widget.roles.length; i++) {
      final name = widget.roles[i].name;
      _rolePos.putIfAbsent(name, () => Offset(24, 24 + i * roleRowH));
    }
    final modules = widget.catalog.keys.toList()..sort();
    const moduleRowH = 74.0;
    for (var i = 0; i < modules.length; i++) {
      _modulePos.putIfAbsent(modules[i], () => Offset(24 + roleColW + 260, 24 + i * moduleRowH));
    }
  }

  Future<void> _loadLayout() async {
    try {
      final all = await SettingService.instance.all();
      final raw = all[_kLayoutKey];
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final roles = (map['roles'] as Map?)?.cast<String, dynamic>() ?? {};
      final modules = (map['modules'] as Map?)?.cast<String, dynamic>() ?? {};
      roles.forEach((k, v) {
        final l = v as List;
        _rolePos[k] = Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
      });
      modules.forEach((k, v) {
        final l = v as List;
        _modulePos[k] = Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
      });
      if (mounted) setState(() {});
    } catch (_) {
      // fine — keep the computed default layout
    }
  }

  Future<void> _saveLayout() async {
    try {
      final json = jsonEncode({
        'roles': _rolePos.map((k, v) => MapEntry(k, [v.dx, v.dy])),
        'modules': _modulePos.map((k, v) => MapEntry(k, [v.dx, v.dy])),
      });
      await SettingService.instance.set(_kLayoutKey, json);
    } catch (_) {
      // layout persistence is a nicety, not critical — fail silently
    }
  }

  Widget _buildContent() {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        Expanded(
          child: Stack(children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.5,
              maxScale: 2.0,
              boundaryMargin: const EdgeInsets.all(300),
              child: SizedBox(
                width: 1200,
                height: 900,
                child: Stack(children: [
                  CustomPaint(
                    size: const Size(1200, 900),
                    painter: _BipartiteEdgePainter(
                      roles: widget.roles,
                      rolePos: _rolePos,
                      modulePos: _modulePos,
                      roleModules: _roleModules,
                      highlightRole: _selectedRole,
                      highlightModule: _selectedModule,
                    ),
                  ),
                  for (var i = 0; i < widget.roles.length; i++)
                    _buildRoleNode(widget.roles[i], _rolePalette[i % _rolePalette.length]),
                  for (final module in widget.catalog.keys)
                    _buildModuleNode(module),
                ]),
              ),
            ),
            Positioned(
              left: 10, top: 10,
              child: _Legend(),
            ),
            Positioned(
              right: 10, top: 10,
              child: OutlinedButton.icon(
                onPressed: _toggleMaximize,
                icon: Icon(_maximized ? Symbols.close_fullscreen : Symbols.open_in_full, size: 15),
                label: Text(_maximized ? 'Restore' : 'Maximize'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.pal.surface1.withValues(alpha: 0.9),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  textStyle: AppTheme.bodySm.copyWith(fontSize: 11.5),
                ),
              ),
            ),
            Positioned(
              right: 10, bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.pal.surface1.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.pal.border),
                ),
                child: Text('Drag nodes · tap to inspect · positions save automatically',
                  style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
              ),
            ),
          ]),
        ),
        if (wide) Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: context.pal.border)),
          ),
          child: _buildDetailPanel(context),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_maximized) {
      return Container(
        height: 560,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.pal.border),
        ),
        child: Text('Shown fullscreen — tap Restore to bring it back here',
          style: AppTheme.bodySub),
      );
    }
    return SizedBox(height: 560, child: _buildContent());
  }

  Widget _buildRoleNode(RoleSummary role, Color color) {
    final pos = _rolePos[role.name]!;
    final selected = _selectedRole == role.name;
    final dimmed = _selectedModule != null && !(_roleModules[role.name]?.contains(_selectedModule) ?? false);
    return Positioned(
      left: pos.dx, top: pos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedRole = _selectedRole == role.name ? null : role.name;
          _selectedModule = null;
        }),
        onPanUpdate: (d) {
          final scale = _transform.value.getMaxScaleOnAxis();
          setState(() => _rolePos[role.name] = pos + Offset(d.delta.dx / scale, d.delta.dy / scale));
        },
        onPanEnd: (_) => _saveLayout(),
        child: AnimatedOpacity(
          opacity: dimmed ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 190,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.28 : 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color, width: selected ? 2 : 1.5),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)],
            ),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_roleLabel(role.name), style: AppTheme.bodyStrong.copyWith(fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${role.permissionCount} perms', style: AppTheme.monoXs.copyWith(fontSize: 9.5)),
              ])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildModuleNode(String module) {
    final pos = _modulePos[module]!;
    final selected = _selectedModule == module;
    final dimmed = _selectedRole != null && !(_roleModules[_selectedRole]?.contains(module) ?? false);
    const color = AppColors.info;
    return Positioned(
      left: pos.dx, top: pos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedModule = _selectedModule == module ? null : module;
          _selectedRole = null;
        }),
        onPanUpdate: (d) {
          final scale = _transform.value.getMaxScaleOnAxis();
          setState(() => _modulePos[module] = pos + Offset(d.delta.dx / scale, d.delta.dy / scale));
        },
        onPanEnd: (_) => _saveLayout(),
        child: AnimatedOpacity(
          opacity: dimmed ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.pal.surface3,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: selected ? 2 : 1.2),
            ),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(child: Text(module, style: AppTheme.bodyStrong.copyWith(fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ),
    );
  }

  String _roleLabel(String name) => name.replaceAll('_', ' ').trim().toUpperCase();

  Widget _buildDetailPanel(BuildContext context) {
    if (_selectedRole != null) return _roleDetail(context, _selectedRole!);
    if (_selectedModule != null) return _moduleDetail(context, _selectedModule!);
    return _overridesDetail(context);
  }

  Widget _roleDetail(BuildContext context, String roleName) {
    final byModule = _roleModuleKeys[roleName] ?? {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_roleLabel(roleName), style: AppTheme.bodyStrong.copyWith(fontSize: 14)),
        const SizedBox(height: 4),
        Text('${byModule.values.fold(0, (s, l) => s + l.length)} permissions across ${byModule.length} modules',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        const SizedBox(height: 14),
        ...byModule.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.key.toUpperCase(), style: AppTheme.monoXs.copyWith(color: AppColors.info)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: e.value.map((key) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: context.pal.surface2,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: context.pal.border),
              ),
              child: Text(_permLabel(key), style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
            )).toList()),
          ]),
        )),
      ]),
    );
  }

  Widget _moduleDetail(BuildContext context, String module) {
    final items = widget.catalog[module] ?? [];
    final rolesWithModule = widget.roles.where((r) => _roleModules[r.name]?.contains(module) ?? false).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(module.toUpperCase(), style: AppTheme.bodyStrong.copyWith(fontSize: 14)),
        const SizedBox(height: 4),
        Text('${items.length} permissions · granted to ${rolesWithModule.length} roles',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        const SizedBox(height: 14),
        Text('PERMISSIONS', style: AppTheme.monoXs),
        const SizedBox(height: 6),
        ...items.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.label, style: AppTheme.bodySm.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
            if (p.description != null)
              Text(p.description!, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
          ]),
        )),
        const SizedBox(height: 10),
        Text('GRANTED TO', style: AppTheme.monoXs),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: rolesWithModule.map((r) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(_roleLabel(r.name), style: AppTheme.bodySub.copyWith(
            fontSize: 10.5, color: AppColors.teal)),
        )).toList()),
      ]),
    );
  }

  Widget _overridesDetail(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Symbols.tune, size: 15, color: context.pal.textMute),
          const SizedBox(width: 8),
          Expanded(child: Text('Individual Overrides', style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
          Text('${widget.overrides.length}', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('Tap a role or permission module on the canvas to inspect its grants. '
            'These are per-user allow/deny grants layered on top of role permissions.',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: widget.overrides.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No active overrides', style: AppTheme.bodySub),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: widget.overrides.length,
                itemBuilder: (context, i) {
                  final o = widget.overrides[i];
                  final allow = o.effect == 'allow';
                  final color = allow ? AppColors.teal : AppColors.coral;
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(allow ? 'ALLOW' : 'DENY', style: AppTheme.monoXs.copyWith(
                            color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(o.userName ?? 'Unknown user',
                          style: AppTheme.bodySm.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 4),
                      Text(o.label, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
                      if (o.reason != null && o.reason!.isNotEmpty)
                        Text(o.reason!, style: AppTheme.bodySub.copyWith(fontSize: 10, fontStyle: FontStyle.italic)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  String _permLabel(String key) {
    for (final items in widget.catalog.values) {
      for (final p in items) {
        if (p.key == key) return p.label;
      }
    }
    return key;
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: context.pal.surface1.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: AppColors.teal, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('Role', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
      ]),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text('Permission module', style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
      ]),
    ]),
  );
}

class _BipartiteEdgePainter extends CustomPainter {
  const _BipartiteEdgePainter({
    required this.roles,
    required this.rolePos,
    required this.modulePos,
    required this.roleModules,
    this.highlightRole,
    this.highlightModule,
  });
  final List<RoleSummary> roles;
  final Map<String, Offset> rolePos;
  final Map<String, Offset> modulePos;
  final Map<String, Set<String>> roleModules;
  final String? highlightRole;
  final String? highlightModule;

  static const _roleW = 190.0, _roleH = 52.0;
  static const _moduleH = 42.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final lit = Paint()
      ..color = AppColors.teal.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final hasHighlight = highlightRole != null || highlightModule != null;

    for (final role in roles) {
      final rp = rolePos[role.name];
      if (rp == null) continue;
      final modules = roleModules[role.name] ?? {};
      for (final module in modules) {
        final mp = modulePos[module];
        if (mp == null) continue;
        final isHighlighted = highlightRole == role.name || highlightModule == module;
        final start = Offset(rp.dx + _roleW, rp.dy + _roleH / 2);
        final end = Offset(mp.dx, mp.dy + _moduleH / 2);
        final midX = (start.dx + end.dx) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
        canvas.drawPath(path, (hasHighlight && !isHighlighted) ? dim : (isHighlighted ? lit : dim));
      }
    }
  }

  @override
  bool shouldRepaint(_BipartiteEdgePainter oldDelegate) => true;
}
