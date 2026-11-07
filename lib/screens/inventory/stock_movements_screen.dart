import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/inventory_item.dart';
import '../../models/location.dart';
import '../../models/stock_movement.dart';
import '../../services/inventory_service.dart';
import '../../services/location_service.dart';
import '../../services/stock_movement_service.dart';
import '../../services/stock_out_request_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/shimmer_box.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  String? _typeFilter;
  bool _showRecord = false;

  List<StockMovement> _movements = [];
  bool   _loading = true;
  String? _error;
  Period _period = Period.defaultPeriod;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known unfiltered list immediately
    // (if any) instead of blanking to a spinner on every navigation — see
    // InventoryService for the full reasoning. Scoped to the default (no type
    // filter) view, matching how StockMovementService.cachedDefaultList is
    // populated.
    final cached = StockMovementService.cachedDefaultList;
    if (cached != null && _typeFilter == null) { _movements = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_movements.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await StockMovementService.instance.list(type: _typeFilter, period: _period);
      if (mounted) setState(() { _movements = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  static Color _typeColor(String t) => switch (t) {
    'receive'    => AppColors.teal,
    'issue'      => AppColors.coral,
    'transfer'   => AppColors.blue,
    'write_off'  => AppColors.amber,
    'adjustment' => AppColors.violet,
    'return'     => AppColors.teal,
    _            => AppColors.textDim,
  };

  static IconData _typeIcon(String t) => switch (t) {
    'receive'    => Symbols.add_circle,
    'issue'      => Symbols.remove_circle,
    'transfer'   => Symbols.swap_horiz,
    'write_off'  => Symbols.delete_forever,
    'adjustment' => Symbols.tune,
    'return'     => Symbols.undo,
    _            => Symbols.swap_vert,
  };

  @override
  Widget build(BuildContext context) {
    const types = ['receive', 'issue', 'transfer', 'write_off', 'adjustment', 'return'];
    const typeLabels = ['Receive', 'Issue', 'Transfer', 'Write-off', 'Adjustment', 'Return'];

    return LayoutBuilder(builder: (context, cst) {
    final phone = isPhoneWidth(cst.maxWidth);
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Header ───────────────────────────────────────────────────────────
        if (phone) PhonePageHeader(
          title: 'Stock Movements',
          subtitle: 'Full audit trail of all stock in/out',
          primary: PageAction(label: 'Record Movement', shortLabel: 'Record', icon: Symbols.add,
              onPressed: () => setState(() => _showRecord = true)),
          filters: [
            PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
            _TypeChip(label: 'All', active: _typeFilter == null,
                onTap: () { setState(() => _typeFilter = null); _load(); }),
            for (final (i, t) in types.indexed)
              _TypeChip(label: typeLabels[i], active: _typeFilter == t, color: _typeColor(t),
                  onTap: () { setState(() => _typeFilter = _typeFilter == t ? null : t); _load(); }),
          ],
        ) else Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stock Movements', style: AppTheme.pageTitle),
              const SizedBox(height: 2),
              Text('Full audit trail of all stock in/out', style: AppTheme.bodySub),
            ]),
            const SizedBox(width: 24),
            // Type chips
            Flexible(child: Wrap(spacing: 6, children: [
              _TypeChip(label: 'All', active: _typeFilter == null,
                  onTap: () { setState(() => _typeFilter = null); _load(); }),
              ...types.asMap().entries.map((e) => _TypeChip(
                label: typeLabels[e.key],
                active: _typeFilter == e.value,
                color: _typeColor(e.value),
                onTap: () {
                  setState(() => _typeFilter = _typeFilter == e.value ? null : e.value);
                  _load();
                },
              )),
            ])),
            const Spacer(),
            PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
            const SizedBox(width: 8),
            AppButton(label: 'Record Movement', icon: Symbols.add, variant: BtnVariant.primary,
                onPressed: () => setState(() => _showRecord = true)),
          ]),
        ),
        // ── Table ────────────────────────────────────────────────────────────
        if (!phone) Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          child: Row(children: [
            _Th('Date/Time', flex: 2), _Th('Item', flex: 3),
            _Th('Type', flex: 1), _Th('Location', flex: 2), _Th('Qty Change', flex: 1),
            _Th('Before — After', flex: 2), _Th('Notes / Reference', flex: 2),
            _Th('By', flex: 1),
          ]),
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
            ? shimmerTable(count: 10, cols: 7)
            : _error != null && _movements.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : _movements.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Symbols.history, size: 40, color: context.pal.textDim),
                    const SizedBox(height: 12),
                    Text('No movements recorded yet', style: AppTheme.bodySub),
                  ]))
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _movements.length,
                    padding: phone ? const EdgeInsets.only(top: 10) : null,
                    itemBuilder: (_, i) => phone
                        ? _MovementCard(
                            movement: _movements[i],
                            typeColor: _typeColor(_movements[i].type),
                            typeIcon:  _typeIcon(_movements[i].type),
                          )
                        : _MovementRow(
                            movement: _movements[i],
                            typeColor: _typeColor(_movements[i].type),
                            typeIcon:  _typeIcon(_movements[i].type),
                          ),
                  ),
        )),
      ]),
      if (_showRecord)
        _RecordMovementModal(
          onClose: () => setState(() => _showRecord = false),
          onSaved: () { setState(() => _showRecord = false); _load(); },
        ),
    ]);
    });
  }
}

// ── Movement card (phones) ───────────────────────────────────────────────────

/// Item, type icon and signed quantity up top; place, stock change, who and
/// when underneath — the 8-column row folded into a card.
class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.movement, required this.typeColor, required this.typeIcon});
  final StockMovement movement;
  final Color typeColor;
  final IconData typeIcon;

  @override
  Widget build(BuildContext context) {
    final sign  = movement.isInbound ? '+' : '';
    final color = movement.isInbound ? AppColors.teal : AppColors.coral;
    return PhoneRecordCard(
      lead: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(typeIcon, size: 18, color: typeColor),
      ),
      title: movement.itemName ?? '—',
      subtitle: '${movement.typeLabel} · ${movement.locationLabel}',
      badge: Text('$sign${movement.quantity}', style: AppTheme.bodyStrong.copyWith(
          color: color, fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()])),
      meta: [
        '${formatDate(movement.createdAt)} ${formatTime(movement.createdAt)}',
        '${movement.quantityBefore} → ${movement.quantityAfter}',
        ?movement.performedByName,
        if ((movement.notes ?? '').isNotEmpty) movement.notes!,
      ],
    );
  }
}

// ── Movement row ─────────────────────────────────────────────────────────────

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement, required this.typeColor, required this.typeIcon});
  final StockMovement movement;
  final Color typeColor;
  final IconData typeIcon;

  @override
  Widget build(BuildContext context) {
    final sign   = movement.isInbound ? '+' : '';
    final color  = movement.isInbound ? AppColors.teal : AppColors.coral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Date/time
        Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDate(movement.createdAt), style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
          Text(formatTime(movement.createdAt), style: AppTheme.bodySub.copyWith(fontSize: 11)),
        ])),
        // Item
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(movement.itemName ?? '—', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
              overflow: TextOverflow.ellipsis),
          if (movement.itemSku != null)
            Text(movement.itemSku!, style: AppTheme.monoXs.copyWith(
                color: context.pal.textMute, fontSize: 10.5)),
        ])),
        // Type badge
        Expanded(flex: 1, child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(typeIcon, size: 13, color: typeColor),
          const SizedBox(width: 4),
          Flexible(child: Text(movement.typeLabel,
              style: AppTheme.monoXs.copyWith(color: typeColor, fontSize: 10.5),
              overflow: TextOverflow.ellipsis)),
        ])),
        // Location (from — to for transfers)
        Expanded(flex: 2, child: Text(movement.locationLabel,
            style: AppTheme.bodySub.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
        // Qty change
        Expanded(flex: 1, child: Text('$sign${movement.quantity}',
            style: AppTheme.bodyStrong.copyWith(
                color: color, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]))),
        // Before — After
        Expanded(flex: 2, child: Row(children: [
          Text('${movement.quantityBefore}', style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
          Icon(Symbols.arrow_forward, size: 12, color: context.pal.textDim),
          Text('${movement.quantityAfter}', style: AppTheme.monoXs.copyWith(color: context.pal.text)),
        ])),
        // Notes / reference
        Expanded(flex: 2, child: Text(movement.notes ?? movement.referenceType ?? '—',
            style: AppTheme.bodySub.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
        // Performed by
        Expanded(flex: 1, child: Text(movement.performedByName ?? '—',
            style: AppTheme.bodySub.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ── Record Movement modal ────────────────────────────────────────────────────

class _RecordMovementModal extends StatefulWidget {
  const _RecordMovementModal({required this.onClose, this.onSaved});
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_RecordMovementModal> createState() => _RecordMovementModalState();
}

class _RecordMovementModalState extends State<_RecordMovementModal> {
  List<InventoryItem> _items = [];
  int?    _selectedItemId;
  List<Location> _locations = [];
  int?    _locationId;
  int?    _toLocationId;
  String  _type = 'receive';
  final _qtyCtrl   = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();
  bool   _saving = false;
  String? _error;

  static const _types      = ['receive', 'issue', 'transfer', 'write_off', 'adjustment', 'return'];
  static const _typeLabels = ['Receive', 'Issue / Use', 'Transfer', 'Write-off', 'Adjustment', 'Return'];
  bool get _isTransfer => _type == 'transfer';
  bool get _needsApproval => _type == 'issue' || _type == 'write_off';

  @override
  void initState() {
    super.initState();
    InventoryService.instance.list().then((list) {
      if (mounted) setState(() => _items = list);
    });
    LocationService.instance.list().then((locs) {
      if (mounted) {setState(() {
        _locations = locs;
        _locationId ??= locs.isNotEmpty ? locs.first.id : null;
      });}
    });
  }

  @override
  void dispose() { _qtyCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (_selectedItemId == null) { setState(() => _error = 'Select an inventory item.'); return; }
    if (_locationId == null) { setState(() => _error = 'Select a location.'); return; }
    if (qty == 0) { setState(() => _error = 'Enter a non-zero quantity.'); return; }
    if (_isTransfer && _toLocationId == null) { setState(() => _error = 'Select a destination location.'); return; }
    if (_isTransfer && _toLocationId == _locationId) { setState(() => _error = 'Source and destination must differ.'); return; }
    if (_needsApproval && _notesCtrl.text.trim().isEmpty) { setState(() => _error = 'A reason is required for stock leaving the store.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      if (_needsApproval) {
        await StockOutRequestService.instance.create({
          'inventory_item_id': _selectedItemId,
          'location_id':       _locationId,
          'type':              _type,
          'quantity':          qty.abs(),
          'reason':            _notesCtrl.text.trim(),
        });
        if (mounted) showSuccessToast(context, 'Stock-out request submitted for approval');
      } else {
        await StockMovementService.instance.record(
          inventoryItemId: _selectedItemId!,
          locationId: _locationId!,
          toLocationId: _isTransfer ? _toLocationId : null,
          type:    _type,
          quantity: qty,
          notes:   _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
        if (mounted) showSuccessToast(context, 'Movement recorded successfully');
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
      color: const Color(0xAA06070A), alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.swap_vert, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Record Stock Movement', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Item picker — inventory catalog can run to
                // hundreds/thousands of SKUs, client-side combobox per
                // Section 4 of hypermed_claude_code_prompt.md.
                Text('ITEM', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                const SizedBox(height: 6),
                AppSearchableSelectField<int>(
                  hint: 'Select item…',
                  selectedLabel: () {
                    final i = _items.where((i) => i.id == _selectedItemId).firstOrNull;
                    return i == null ? null : '${i.sku} · ${i.name}';
                  }(),
                  items: _items.map((item) => AppSelectItem(
                    value: item.id, label: '${item.sku} · ${item.name}')).toList(),
                  onSelected: (item) => setState(() => _selectedItemId = item?.value),
                ),
                const SizedBox(height: 12),
                // Location picker
                Text(_isTransfer ? 'From location' : 'Location', style: AppTheme.fieldLabel),
                const SizedBox(height: 6),
                DropdownFieldBox<int?>(
                  value: _locationId,
                  hint: 'Select location…',
                  items: _locations.map((l) => DropdownMenuItem(
                      value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                  onChanged: (v) => setState(() {
                      _locationId = v;
                      if (_toLocationId == v) _toLocationId = null;
                    }),
                ),
                if (_isTransfer) ...[
                  const SizedBox(height: 12),
                  Text('To location', style: AppTheme.fieldLabel),
                  const SizedBox(height: 6),
                  DropdownFieldBox<int?>(
                    value: _toLocationId,
                    hint: 'Select destination…',
                    items: _locations.where((l) => l.id != _locationId).map((l) => DropdownMenuItem(
                        value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis),
                      )).toList(),
                    onChanged: (v) => setState(() => _toLocationId = v),
                  ),
                ],
                const SizedBox(height: 12),
                // Type + qty row
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Type', style: AppTheme.fieldLabel),
                    const SizedBox(height: 6),
                    DropdownFieldBox<String>(
                      value: _type,
                      items: _types.asMap().entries.map((e) => DropdownMenuItem(
                          value: e.value, child: Text(_typeLabels[e.key]),
                        )).toList(),
                      onChanged: (v) { if (v != null) setState(() => _type = v); },
                    ),
                  ])),
                  const SizedBox(width: 14),
                  SizedBox(width: 100, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LabeledTextField(label: 'Quantity', controller: _qtyCtrl, keyboardType: TextInputType.number, hint: '1'),
                  ])),
                ]),
                const SizedBox(height: 12),
                LabeledTextField(label: _needsApproval ? 'Reason (required)' : 'Notes', controller: _notesCtrl, hint: _needsApproval ? 'Why is this stock leaving the store?' : 'Optional reason or reference'),
                if (_needsApproval) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Symbols.info, size: 13, color: AppColors.amber),
                      const SizedBox(width: 8),
                      Expanded(child: Text('This submits a request — stock won\'t be deducted until a CTO/Director approves it.',
                          style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
                    ]),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
                  onTap: _saving ? null : _submit,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Record', style: AppTheme.bodyStrong.copyWith(
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

// ── Shared widgets ───────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.active, required this.onTap, this.color});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? (color ?? AppColors.teal).withValues(alpha: 0.12) : context.pal.surface1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? (color ?? AppColors.teal) : context.pal.border),
      ),
      child: Text(label, style: AppTheme.bodySm.copyWith(
          color: active ? (color ?? AppColors.teal) : context.pal.textMute, fontSize: 12)),
    ),
  );
}

class _Th extends StatelessWidget {
  const _Th(this.label, {required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(label.toUpperCase(),
        style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.10)),
  );
}
