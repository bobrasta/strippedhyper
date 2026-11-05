import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/location.dart';
import '../../services/location_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/shimmer_box.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  List<Location> _all = [];
  String _search = '';
  String? _typeFilter;
  bool  _loading = true;
  String? _error;
  Location? _selected;
  bool _showAdd  = false;
  bool _showEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await LocationService.instance.list(includeInactive: true);
      if (mounted) setState(() { _all = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<Location> get _filtered {
    var list = _all;
    if (_typeFilter != null) list = list.where((l) => l.type == _typeFilter).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((l) =>
          l.name.toLowerCase().contains(q) ||
          (l.code?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  Future<void> _deactivate(Location loc) async {
    try {
      await LocationService.instance.deactivate(loc.id);
      if (mounted) {
        setState(() {
          if (_selected == loc) _selected = null;
        });
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  static const _types = [null, 'warehouse', 'store', 'room', 'vehicle', 'other'];
  static const _typeLabels = ['All', 'Warehouse', 'Store', 'Room', 'Vehicle', 'Other'];

  Color _typeColor(String type) => switch (type) {
    'warehouse' => AppColors.teal,
    'store'     => AppColors.violet,
    'room'      => AppColors.green,
    'vehicle'   => AppColors.amber,
    _           => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Stack(children: [
      Column(children: [
        // Top bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: BoxDecoration(
            color: context.pal.surface1,
            border: Border(bottom: BorderSide(color: context.pal.border)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.warehouse, size: 20, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(child: Text('Locations', style: AppTheme.cardTitle.copyWith(fontSize: 15),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () => setState(() { _showAdd = true; _selected = null; }),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Symbols.add, size: 16, color: Color(0xFF06120F)),
                    const SizedBox(width: 6),
                    Text('Add Location', style: AppTheme.bodyStrong.copyWith(
                        color: const Color(0xFF06120F), fontSize: 12.5)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SearchField(hint: 'Search locations…', onChanged: (v) => setState(() => _search = v)),
              ),
            ]),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_types.length, (i) {
                  final selected = _typeFilter == _types[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () => setState(() => _typeFilter = _types[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.teal : Colors.transparent,
                          border: Border.all(color: selected ? AppColors.teal : context.pal.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_typeLabels[i],
                            style: AppTheme.bodySm.copyWith(
                              color: selected ? const Color(0xFF06120F) : context.pal.textMute,
                              fontSize: 12,
                            )),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ]),
        ),

        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: context.pal.surface2,
            border: Border(bottom: BorderSide(color: context.pal.border)),
          ),
          child: Row(children: [
            Expanded(flex: 3, child: Text('NAME', style: AppTheme.labelCaps)),
            Expanded(flex: 1, child: Text('TYPE', style: AppTheme.labelCaps)),
            Expanded(flex: 2, child: Text('ADDRESS', style: AppTheme.labelCaps)),
            Expanded(flex: 1, child: Text('STATUS', style: AppTheme.labelCaps)),
            const SizedBox(width: 64),
          ]),
        ),

        // List
        Expanded(
          child: Row(children: [
            Expanded(
              flex: _selected != null ? 7 : 1,
              child: SingleChildScrollView(
                child: Column(children: [
                  if (_loading) shimmerTable(count: 6, cols: 4)
                  else if (_error != null)
                    ErrorView(message: _error!, onRetry: _load, compact: true)
                  else if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.warehouse, size: 36, color: context.pal.textDim),
                        const SizedBox(height: 10),
                        Text('No locations found', style: AppTheme.bodySub),
                      ])),
                    )
                  else
                    ...items.map((loc) => _LocationRow(
                      loc: loc,
                      selected: _selected == loc,
                      typeColor: _typeColor(loc.type),
                      onTap: () => setState(() => _selected = _selected == loc ? null : loc),
                      onEdit: () => setState(() { _selected = loc; _showEdit = true; }),
                      onDelete: () => _deactivate(loc),
                    )),
                ]),
              ),
            ),
            if (_selected != null) ...[
              Container(width: 1, color: context.pal.border),
              Expanded(flex: 5, child: _DetailPanel(
                loc: _selected!,
                typeColor: _typeColor(_selected!.type),
                onClose: () => setState(() => _selected = null),
                onEdit: () => setState(() => _showEdit = true),
              )),
            ],
          ]),
        ),
      ]),

      if (_showAdd)
        _LocationFormModal(
          onClose: () => setState(() => _showAdd = false),
          onSaved: () { setState(() => _showAdd = false); _load(); },
        ),
      if (_showEdit && _selected != null)
        _LocationFormModal(
          location: _selected!,
          onClose: () => setState(() => _showEdit = false),
          onSaved: () { setState(() => _showEdit = false); _load(); },
        ),
    ]);
  }
}

// ── Row ──────────────────────────────────────────────────────────────────────

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.loc, required this.selected,
    required this.typeColor,
    required this.onTap, this.onEdit, this.onDelete,
  });
  final Location loc;
  final bool selected;
  final Color typeColor;
  final VoidCallback onTap;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? context.pal.surface2 : Colors.transparent,
        border: Border(bottom: BorderSide(color: context.pal.divider)),
      ),
      child: Row(children: [
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc.name, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
          if (loc.code != null)
            Text(loc.code!, style: AppTheme.monoXs.copyWith(color: context.pal.textMute, fontSize: 10.5)),
        ])),
        Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(loc.typeLabel,
              style: AppTheme.monoXs.copyWith(color: typeColor, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ))),
        Expanded(flex: 2, child: Text(
            loc.address ?? '—',
            style: AppTheme.bodySub.copyWith(fontSize: 12),
            overflow: TextOverflow.ellipsis)),
        Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: (loc.isActive ? AppColors.green : AppColors.textDim)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(loc.isActive ? 'Active' : 'Inactive',
              style: AppTheme.monoXs.copyWith(
                  color: loc.isActive ? AppColors.green : context.pal.textDim,
                  fontSize: 10.5)),
        ))),
        SizedBox(width: 64, child: Row(children: [
          const SizedBox(width: 4),
          GestureDetector(onTap: onEdit,
              child: Icon(Symbols.edit, size: 15, color: context.pal.textDim)),
          const SizedBox(width: 12),
          GestureDetector(onTap: onDelete,
              child: Icon(Symbols.delete_outline, size: 15, color: AppColors.coral)),
        ])),
      ]),
    ),
  );
}

// ── Detail panel ─────────────────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.loc, required this.typeColor,
    required this.onClose, this.onEdit,
  });
  final Location loc;
  final Color typeColor;
  final VoidCallback onClose;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(loc.name, style: AppTheme.bodyStrong)),
        GestureDetector(onTap: onClose,
            child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 3),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(loc.typeLabel,
            style: AppTheme.monoXs.copyWith(color: typeColor, fontSize: 10.5)),
      ),
      const SizedBox(height: 14),
      if (loc.code != null)    _Row('Code',    loc.code!),
      if (loc.address != null) _Row('Address', loc.address!),
      _Row('Status', loc.isActive ? 'Active' : 'Inactive'),
      if (loc.notes != null && loc.notes!.isNotEmpty)
        _Row('Notes', loc.notes!),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: GestureDetector(
        onTap: onEdit,
        child: Container(height: 38,
          decoration: BoxDecoration(
              border: Border.all(color: context.pal.border),
              borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('Edit Location', style: AppTheme.bodySm)),
        ),
      )),
    ]),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

// ── Form modal ───────────────────────────────────────────────────────────────

class _LocationFormModal extends StatefulWidget {
  const _LocationFormModal({this.location, required this.onClose, this.onSaved});
  final Location?  location;
  final VoidCallback onClose;
  final VoidCallback? onSaved;

  @override
  State<_LocationFormModal> createState() => _LocationFormModalState();
}

class _LocationFormModalState extends State<_LocationFormModal> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  String _type = 'warehouse';
  bool _saving = false;
  String? _error;

  static const _types = ['warehouse', 'store', 'room', 'vehicle', 'other'];
  static const _typeLabels = ['Warehouse', 'Store', 'Room', 'Vehicle', 'Other'];

  @override
  void initState() {
    super.initState();
    final l = widget.location;
    _nameCtrl    = TextEditingController(text: l?.name ?? '');
    _codeCtrl    = TextEditingController(text: l?.code ?? '');
    _addressCtrl = TextEditingController(text: l?.address ?? '');
    _notesCtrl   = TextEditingController(text: l?.notes ?? '');
    _type        = l?.type ?? 'warehouse';
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _codeCtrl.dispose();
    _addressCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Name is required.'); return; }

    setState(() { _saving = true; _error = null; });
    final data = {
      'name':    name,
      'code':    _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      'type':    _type,
      'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      'notes':   _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    };

    try {
      if (widget.location != null) {
        await LocationService.instance.update(widget.location!.id, data);
      } else {
        await LocationService.instance.create(data);
      }
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
          width: 440,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.warehouse, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    widget.location != null ? 'Edit Location' : 'Add Location',
                    style: AppTheme.bodyStrong)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Divider(height: 1, color: context.pal.border),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: AppTheme.bodySm.copyWith(color: AppColors.coral)),
                  ),
                  const SizedBox(height: 12),
                ],
                _Field('Name *', _nameCtrl, hint: 'e.g. Main Warehouse'),
                const SizedBox(height: 12),
                _Field('Code', _codeCtrl, hint: 'e.g. WH-01 (optional, must be unique)'),
                const SizedBox(height: 12),
                Text('Type', style: AppTheme.fieldLabel),
                const SizedBox(height: 6),
                DropdownFieldBox<String>(
                  value: _type,
                  items: List.generate(_types.length, (i) => DropdownMenuItem(
                        value: _types[i],
                        child: Text(_typeLabels[i], style: AppTheme.bodySm),
                      )),
                  onChanged: (v) { if (v != null) setState(() => _type = v); },
                ),
                const SizedBox(height: 12),
                _Field('Address', _addressCtrl, hint: 'Physical address (optional)', maxLines: 2),
                const SizedBox(height: 12),
                _Field('Notes', _notesCtrl, hint: 'Internal notes (optional)', maxLines: 2),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(height: 40,
                    decoration: BoxDecoration(
                      color: _saving ? AppColors.teal.withValues(alpha: 0.5) : AppColors.teal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(
                        _saving ? 'Saving…' : (widget.location != null ? 'Save Changes' : 'Add Location'),
                        style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F)))),
                  ),
                )),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.ctrl, {this.hint, this.maxLines = 1});
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final int maxLines;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint, maxLines: maxLines);
}
