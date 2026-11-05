import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show can;
import '../../models/org_node.dart';
import '../../services/setting_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common/fullscreen_editor_shell.dart';
import '../../widgets/common/labeled_field.dart';

const _kSettingKey = 'org_chart_json';

/// 8 distinct, vivid hues — deliberately its own palette rather than
/// AppColors, since several AppColors tokens (teal/blue/green) are aliased
/// to the same brand green and wouldn't give 8 visually distinct colors.
const _palette = <Color>[
  Color(0xFFFBBF24), // amber — director
  Color(0xFF22C55E), // green
  Color(0xFF38BDF8), // sky
  Color(0xFFA78BFA), // violet
  Color(0xFFF472B6), // pink
  Color(0xFFFB923C), // orange
  Color(0xFFF87171), // red
  Color(0xFF2DD4BF), // teal
];

List<OrgNode> _defaultNodes() {
  const spacing = 200.0;
  const rowY = 240.0;
  return [
    OrgNode(id: 'director', label: 'Director', parentId: null, x: 620, y: 40, colorIndex: 0),
    OrgNode(id: 'sales', label: 'Sales', parentId: 'director', x: 20, y: rowY, colorIndex: 1),
    OrgNode(id: 'service', label: 'Service', parentId: 'director', x: 20 + spacing, y: rowY, colorIndex: 2),
    OrgNode(id: 'application', label: 'Application', parentId: 'director', x: 20 + spacing * 2, y: rowY, colorIndex: 3),
    OrgNode(id: 'finance', label: 'Accounts & Finance', parentId: 'director', x: 20 + spacing * 3, y: rowY, colorIndex: 4),
    OrgNode(id: 'warehouse', label: 'Warehouse & Logistics', parentId: 'director', x: 20 + spacing * 4, y: rowY, colorIndex: 5),
    OrgNode(id: 'legal', label: 'Legal', parentId: 'director', x: 20 + spacing * 5, y: rowY, colorIndex: 6),
    OrgNode(id: 'support', label: 'Facilities & Support Services', parentId: 'director', x: 20 + spacing * 6, y: rowY, colorIndex: 7),
  ];
}

/// Free-form, hand-rolled node graph editor (no external package) for
/// sketching the org hierarchy — drag nodes anywhere, add/rename/recolor/
/// delete, export the tree as Mermaid flowchart syntax. Persisted through
/// the existing Setting key/value store (Director-only writes, matching
/// how every other admin-level setting in this screen is already gated).
class OrgChartEditor extends StatefulWidget {
  const OrgChartEditor({super.key});

  @override
  State<OrgChartEditor> createState() => _OrgChartEditorState();
}

class _OrgChartEditorState extends State<OrgChartEditor> {
  List<OrgNode> _nodes = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  final _transform = TransformationController();
  int _nextId = 0;

  bool _maximized = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known chart immediately
    // (surviving widget disposal, unlike State fields) while a real refresh
    // happens silently in the background — see MachineService's own doc
    // comment for the full reasoning. SettingService.cachedAll is the
    // shared settings cache (not owned by this screen), parsed the same way
    // _load() below parses it.
    final cachedAll = SettingService.cachedAll;
    if (cachedAll != null) {
      final raw = cachedAll[_kSettingKey];
      try {
        if (raw != null && raw.trim().isNotEmpty) {
          final list = jsonDecode(raw) as List;
          _nodes = list.map((e) => OrgNode.fromJson(e as Map<String, dynamic>)).toList();
        } else {
          _nodes = _defaultNodes();
        }
        _loading = false;
      } catch (_) {
        // Malformed cached JSON — fall through to the normal load path
        // below instead of crashing init.
      }
    }
    _load();
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
        title: 'Organization Chart',
        onClose: _toggleMaximize,
        toolbar: _buildToolbar(inOverlay: true),
        error: _error,
        child: _buildCanvas(),
      ));
      _overlayEntry = entry;
      Overlay.of(context).insert(entry);
      setState(() => _maximized = true);
    }
  }

  Future<void> _load() async {
    setState(() {
      if (_nodes.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final all = await SettingService.instance.all();
      final raw = all[_kSettingKey];
      if (raw != null && raw.trim().isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _nodes = list.map((e) => OrgNode.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        _nodes = _defaultNodes();
      }
    } catch (e) {
      _error = friendlyOrgChartError(e);
      _nodes = _defaultNodes();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = jsonEncode(_nodes.map((n) => n.toJson()).toList());
      await SettingService.instance.set(_kSettingKey, json);
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyOrgChartError(e))));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _markDirty() => setState(() => _dirty = true);

  // Everyone can view the chart; the Administrator, Director and CTO edit it
  // (org_chart.manage — SettingController accepts org_chart_json from them).
  bool get _canEdit => can('org_chart.manage') || can('authority.admin_tier');

  String _newId() {
    _nextId++;
    return 'node_${DateTime.now().millisecondsSinceEpoch}_$_nextId';
  }

  void _addNode() {
    showDialog(context: context, builder: (_) => _NodeDialog(
      existing: _nodes,
      onSave: (label, parentId, colorIndex) {
        setState(() {
          final parent = _nodes.where((n) => n.id == parentId).firstOrNull;
          _nodes.add(OrgNode(
            id: _newId(), label: label, parentId: parentId,
            x: (parent?.x ?? 40) + 40, y: (parent?.y ?? 40) + 160,
            colorIndex: colorIndex,
          ));
        });
        _markDirty();
      },
    ));
  }

  void _editNode(OrgNode node) {
    showDialog(context: context, builder: (dialogCtx) => _NodeDialog(
      existing: _nodes,
      editing: node,
      onSave: (label, parentId, colorIndex) {
        setState(() {
          node.label = label;
          node.parentId = parentId;
          node.colorIndex = colorIndex;
        });
        _markDirty();
      },
      onDelete: _nodes.any((n) => n.parentId == node.id) ? null : () {
        setState(() => _nodes.removeWhere((n) => n.id == node.id));
        _markDirty();
        Navigator.pop(dialogCtx);
      },
    ));
  }

  void _resetToDefault() {
    setState(() => _nodes = _defaultNodes());
    _markDirty();
  }

  String _toMermaid() {
    String safe(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final buf = StringBuffer('flowchart TD\n');
    for (final n in _nodes) {
      final label = n.label.replaceAll('"', "'");
      buf.writeln('    ${safe(n.id)}["$label"]');
    }
    for (final n in _nodes) {
      if (n.parentId != null && _nodes.any((p) => p.id == n.parentId)) {
        buf.writeln('    ${safe(n.parentId!)} --> ${safe(n.id)}');
      }
    }
    return buf.toString();
  }

  void _showImport() {
    final ctrl = TextEditingController();
    String? error;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: ctx.pal.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Symbols.file_upload, size: 18),
          const SizedBox(width: 8),
          Text('Import Mermaid', style: AppTheme.bodyStrong),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Paste flowchart/graph Mermaid code below. This replaces the current chart '
                '— nodes are auto-arranged by hierarchy, then you can drag them freely.',
                style: AppTheme.bodySub.copyWith(fontSize: 12)),
            const SizedBox(height: 10),
            LabeledTextField(label: '', controller: ctrl, maxLines: 10, hint: 'flowchart TD\n    A[Director] --> B[Sales]\n    A --> C[Service]'),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AppTheme.bodySub.copyWith(color: Colors.redAccent, fontSize: 12)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () {
              final parsed = parseMermaidToNodes(ctrl.text);
              if (parsed.isEmpty) {
                setDialogState(() => error = 'Could not find any nodes in that — check the syntax and try again.');
                return;
              }
              setState(() => _nodes = parsed);
              _markDirty();
              Navigator.pop(ctx);
            },
            icon: const Icon(Symbols.check, size: 16),
            label: const Text('Import'),
          ),
        ],
      ),
    ));
  }

  void _showExport() {
    final mermaid = _toMermaid();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: ctx.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [
        const Icon(Symbols.data_object, size: 18),
        const SizedBox(width: 8),
        Text('Mermaid Export', style: AppTheme.bodyStrong),
      ]),
      content: SizedBox(
        width: 480,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ctx.pal.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ctx.pal.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(mermaid, style: AppTheme.monoXs.copyWith(fontSize: 12, height: 1.6)),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: mermaid));
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Mermaid code copied to clipboard')));
          },
          icon: const Icon(Symbols.content_copy, size: 16),
          label: const Text('Copy'),
        ),
      ],
    ));
  }

  Widget _buildToolbar({bool inOverlay = false}) {
    if (!_canEdit) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _showExport,
          icon: const Icon(Symbols.data_object, size: 16),
          label: const Text('Export Mermaid'),
        ),
        OutlinedButton.icon(
          onPressed: _toggleMaximize,
          icon: Icon(inOverlay ? Symbols.close_fullscreen : Symbols.open_in_full, size: 16),
          label: Text(inOverlay ? 'Restore' : 'Maximize'),
        ),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
        onPressed: _resetToDefault,
        icon: const Icon(Symbols.restart_alt, size: 16),
        label: const Text('Reset'),
      ),
      OutlinedButton.icon(
        onPressed: _showImport,
        icon: const Icon(Symbols.file_upload, size: 16),
        label: const Text('Import Mermaid'),
      ),
      OutlinedButton.icon(
        onPressed: _showExport,
        icon: const Icon(Symbols.data_object, size: 16),
        label: const Text('Export Mermaid'),
      ),
      OutlinedButton.icon(
        onPressed: _addNode,
        icon: const Icon(Symbols.add, size: 16),
        label: const Text('Add Node'),
      ),
      OutlinedButton.icon(
        onPressed: _toggleMaximize,
        icon: Icon(inOverlay ? Symbols.close_fullscreen : Symbols.open_in_full, size: 16),
        label: Text(inOverlay ? 'Restore' : 'Maximize'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Symbols.save, size: 16),
        label: Text(_dirty ? 'Save changes' : 'Saved'),
      ),
    ]);
  }

  Widget _buildCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: 0.4,
          maxScale: 2.0,
          boundaryMargin: const EdgeInsets.all(400),
          child: SizedBox(
            width: 2200,
            height: 1100,
            child: Stack(children: [
              CustomPaint(
                size: const Size(2200, 1100),
                painter: _EdgePainter(_nodes, context.pal.textDim),
              ),
              for (final node in _nodes)
                _DraggableNode(
                  key: ValueKey(node.id),
                  node: node,
                  color: _palette[node.colorIndex % _palette.length],
                  transform: _transform,
                  readOnly: !_canEdit,
                  onMoved: _markDirty,
                  onTap: () => _editNode(node),
                ),
            ]),
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
            child: Text(_canEdit ? 'Drag nodes · pinch/scroll to zoom · tap a node to edit' : 'Pinch/scroll to zoom',
              style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Organization Chart', style: AppTheme.cardTitle),
          const SizedBox(height: 4),
          Text(_canEdit
              ? 'Drag nodes to arrange, add departments, export as Mermaid for docs. '
                'Sketch roles and approval lines here before wiring them into Access Control.'
              : 'Who reports to whom across Hypermed.',
              style: AppTheme.bodySub.copyWith(fontSize: 12)),
        ])),
        _buildToolbar(),
      ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: AppTheme.bodySub.copyWith(color: Colors.redAccent)),
        ),
      const SizedBox(height: 14),
      if (_maximized)
        Container(
          height: 560,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.border),
          ),
          child: Text('Shown fullscreen — tap Restore to bring it back here',
            style: AppTheme.bodySub),
        )
      else
        SizedBox(height: 560, child: _buildCanvas()),
    ]);
  }
}

// ── Mermaid import ───────────────────────────────────────────────────────────

final _edgeLineRe = RegExp(
  r'^(.*?)(?:-{2,3}>|={2,3}>|-\.-{1,2}>|-{2,3}|-\.-{1,2})(?:\|[^|]*\|)?\s*(.+)$');
final _nodeTokenRe = RegExp(
  r'^([A-Za-z0-9_]+)\s*(?:\[("(?:[^"]*)"|[^\]]*)\]|\(("(?:[^"]*)"|[^)]*)\)|\{("(?:[^"]*)"|[^}]*)\})?\s*$');
final _leadingIdRe = RegExp(r'^([A-Za-z0-9_]+)');
final _skipLineRe = RegExp(
  r'^(flowchart|graph|subgraph|end\b|classDef|class\s|style\s|click\s|linkStyle)',
  caseSensitive: false);

/// Parses a practical subset of Mermaid flowchart/graph syntax (node
/// declarations with [], (), {} labels; --> / --- / -.-> / ==> edges,
/// with or without |edge label|) into a laid-out node tree. Unrecognized
/// lines (subgraph/style/classDef/etc.) are skipped rather than failing the
/// whole import — this is a visualization aid, not a spec-complete parser.
List<OrgNode> parseMermaidToNodes(String text) {
  final labels = <String, String>{};
  final order = <String>[];
  final edges = <MapEntry<String, String>>[];

  void registerNode(String token) {
    token = token.trim();
    if (token.isEmpty) return;
    final m = _nodeTokenRe.firstMatch(token);
    if (m == null) return;
    final id = m.group(1)!;
    final rawLabel = m.group(2) ?? m.group(3) ?? m.group(4);
    if (!labels.containsKey(id)) {
      order.add(id);
      labels[id] = id;
    }
    if (rawLabel != null) {
      final label = rawLabel.replaceAll('"', '').trim();
      if (label.isNotEmpty) labels[id] = label;
    }
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('%%')) continue;
    if (_skipLineRe.hasMatch(line)) continue;

    final edgeMatch = _edgeLineRe.firstMatch(line);
    if (edgeMatch != null) {
      final left = edgeMatch.group(1)!.trim();
      final right = edgeMatch.group(2)!.trim();
      if (left.isEmpty || right.isEmpty) continue;
      registerNode(left);
      registerNode(right);
      final leftId = _leadingIdRe.firstMatch(left)?.group(1);
      final rightId = _leadingIdRe.firstMatch(right)?.group(1);
      if (leftId != null && rightId != null) {
        edges.add(MapEntry(leftId, rightId));
      }
    } else {
      registerNode(line);
    }
  }

  if (order.isEmpty) return [];

  final parentOf = <String, String>{};
  for (final e in edges) {
    parentOf.putIfAbsent(e.value, () => e.key);
  }

  final depth = <String, int>{};
  final roots = order.where((id) => !parentOf.containsKey(id)).toList();
  if (roots.isEmpty) roots.add(order.first); // all-cyclic fallback
  final queue = <String>[...roots];
  for (final r in roots) {
    depth[r] = 0;
  }
  var qi = 0;
  while (qi < queue.length) {
    final cur = queue[qi++];
    for (final e in edges) {
      if (e.key == cur && !depth.containsKey(e.value)) {
        depth[e.value] = (depth[cur] ?? 0) + 1;
        queue.add(e.value);
      }
    }
  }
  for (final id in order) {
    depth.putIfAbsent(id, () => 0);
  }

  final byDepth = <int, List<String>>{};
  for (final id in order) {
    byDepth.putIfAbsent(depth[id]!, () => []).add(id);
  }

  const colW = 190.0, rowH = 160.0;
  final nodes = <OrgNode>[];
  var colorI = 0;
  final depths = byDepth.keys.toList()..sort();
  for (final d in depths) {
    final ids = byDepth[d]!;
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      nodes.add(OrgNode(
        id: id, label: labels[id] ?? id, parentId: parentOf[id],
        x: 40 + i * colW, y: 40 + d * rowH,
        colorIndex: colorI++ % _palette.length,
      ));
    }
  }
  return nodes;
}

String friendlyOrgChartError(Object e) {
  final msg = e.toString();
  if (msg.contains('403')) return 'Only the Director can save the org chart — showing your local draft.';
  if (msg.contains('SocketException') || msg.contains('connection')) {
    return 'No connection — showing the last saved chart or a fresh default.';
  }
  return 'Could not load the saved chart — showing a fresh default.';
}

// ── Draggable node widget ───────────────────────────────────────────────────

class _DraggableNode extends StatelessWidget {
  const _DraggableNode({
    super.key,
    required this.node,
    required this.color,
    required this.transform,
    required this.onMoved,
    required this.onTap,
    this.readOnly = false,
  });
  final OrgNode node;
  final Color color;
  final TransformationController transform;
  final bool readOnly;
  final VoidCallback onMoved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: node.x,
      top: node.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: readOnly ? null : onTap,
        onPanUpdate: readOnly ? null : (details) {
          final scale = transform.value.getMaxScaleOnAxis();
          node.x += details.delta.dx / scale;
          node.y += details.delta.dy / scale;
          onMoved();
        },
        child: Container(
          width: 168,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)],
          ),
          child: Row(children: [
            Container(width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(node.label,
              style: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

// ── Connection line painter ─────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  const _EdgePainter(this.nodes, this.lineColor);
  final List<OrgNode> nodes;
  final Color lineColor;

  static const _nodeW = 168.0;
  static const _nodeH = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    for (final n in nodes) {
      if (n.parentId == null) continue;
      final parent = nodes.where((p) => p.id == n.parentId).firstOrNull;
      if (parent == null) continue;

      final start = Offset(parent.x + _nodeW / 2, parent.y + _nodeH);
      final end = Offset(n.x + _nodeW / 2, n.y);
      final midY = (start.dy + end.dy) / 2;

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx, midY, end.dx, midY, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) =>
      oldDelegate.nodes != nodes || oldDelegate.lineColor != lineColor;
}

// ── Add / edit node dialog ──────────────────────────────────────────────────

class _NodeDialog extends StatefulWidget {
  const _NodeDialog({
    required this.existing,
    required this.onSave,
    this.editing,
    this.onDelete,
  });
  final List<OrgNode> existing;
  final OrgNode? editing;
  final void Function(String label, String? parentId, int colorIndex) onSave;
  final VoidCallback? onDelete;

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  late final _labelCtrl = TextEditingController(text: widget.editing?.label ?? '');
  String? _parentId;
  late int _colorIndex = widget.editing?.colorIndex ?? 0;

  @override
  void initState() {
    super.initState();
    _parentId = widget.editing?.parentId;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    final parentOptions = widget.existing.where((n) => n.id != widget.editing?.id).toList();

    return AlertDialog(
      backgroundColor: context.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(isEditing ? 'Edit Node' : 'Add Node', style: AppTheme.bodyStrong),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledTextField(label: 'Label', controller: _labelCtrl, hint: 'e.g. Marketing'),
          const SizedBox(height: 14),
          LabeledDropdown<String?>(
            label: 'Reports to',
            value: _parentId,
            items: [null, ...parentOptions.map((n) => n.id)],
            displayBuilder: (id) => id == null ? '— None (top level) —' : parentOptions.firstWhere((n) => n.id == id).label,
            onChanged: (v) => setState(() => _parentId = v),
          ),
          const SizedBox(height: 14),
          Text('Color', style: AppTheme.fieldLabel),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: List.generate(_palette.length, (i) {
            final selected = i == _colorIndex;
            return GestureDetector(
              onTap: () => setState(() => _colorIndex = i),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _palette[i], shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent, width: 2.5),
                  boxShadow: selected
                      ? [BoxShadow(color: _palette[i].withValues(alpha: 0.6), blurRadius: 8)]
                      : null,
                ),
              ),
            );
          })),
        ]),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          )
        else
          const SizedBox.shrink(),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () {
              final label = _labelCtrl.text.trim();
              if (label.isEmpty) return;
              widget.onSave(label, _parentId, _colorIndex);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ]),
      ],
    );
  }
}
