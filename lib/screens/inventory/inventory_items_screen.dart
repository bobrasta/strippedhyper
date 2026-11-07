import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/category.dart';
import '../../models/inventory_item.dart';
import '../../models/location.dart';
import '../../services/category_service.dart';
import '../../services/inventory_service.dart';
import '../../services/location_service.dart';
import '../../services/stock_movement_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/csv_export.dart';
import '../../utils/format.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/shimmer_box.dart';
import 'inventory_item_detail_screen.dart';
import '../../widgets/common/phone_layout.dart';

class InventoryItemsScreen extends StatefulWidget {
  const InventoryItemsScreen({super.key});

  @override
  State<InventoryItemsScreen> createState() => _InventoryItemsScreenState();
}

class _InventoryItemsScreenState extends State<InventoryItemsScreen> {
  String  _stockFilter    = 'all';
  String? _categoryFilter;
  String  _search         = '';
  InventoryItem? _selected;
  bool _showAdd    = false;
  bool _showEdit   = false;
  bool _showMove   = false;

  List<InventoryItem> _allItems = [];
  bool   _loading  = true;
  String? _error;
  int    _showCount = _pageSize;
  static const _pageSize = 100;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known catalog immediately (if
    // any) instead of blanking to a spinner on every navigation — see
    // MachineService for the full reasoning.
    final cached = InventoryService.cachedDefaultList;
    if (cached != null) { _allItems = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_allItems.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await InventoryService.instance.list();
      if (mounted) setState(() { _allItems = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _deactivate(InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Deactivate ${item.name}?', style: AppTheme.bodyStrong),
        content: Text('The item will be hidden from active inventory.', style: AppTheme.bodySub),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('Cancel', style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text('Deactivate', style: AppTheme.bodySm.copyWith(color: AppColors.coral))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InventoryService.instance.deactivate(item.id);
      if (mounted) { setState(() { if (_selected == item) _selected = null; }); _load(); }
    } catch (_) {}
  }

  Future<void> _exportCsv() async {
    try {
      final path = await CsvExport.inventoryItems(_filtered);
      if (path != null && mounted) showSuccessToast(context, 'Exported ${_filtered.length} item(s) to CSV');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  List<InventoryItem> get _filtered {
    var list = _allItems;
    if (_stockFilter == 'low') list = list.where((p) => p.isLowStock && !p.isOutOfStock).toList();
    if (_stockFilter == 'out') list = list.where((p) => p.isOutOfStock).toList();
    if (_categoryFilter != null) list = list.where((p) => p.category == _categoryFilter).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.sku.toLowerCase().contains(q) ||
        (p.manufacturer?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  // Categories are now a real, admin-managed list (not a fixed enum), so
  // `item.category` already IS the display name — just show it as-is and
  // pick a stable color by hashing the name across a small fixed palette.
  static String _catLabel(String cat) => cat;

  static List<Color> get _catPalette => [
    AppColors.teal, AppColors.blue, AppColors.violet,
    AppColors.amber, AppColors.coral, AppColors.info,
  ];
  static Color _catColor(String cat) =>
      cat.isEmpty ? AppColors.textDim : _catPalette[cat.hashCode.abs() % _catPalette.length];

  @override
  Widget build(BuildContext context) {
    final allFiltered = _filtered;
    final items       = allFiltered.take(_showCount).toList();
    final remaining   = allFiltered.length - items.length;
    final lowCount    = _allItems.where((p) => p.isLowStock && !p.isOutOfStock).length;
    final outCount    = _allItems.where((p) => p.isOutOfStock).length;

    final categories = <String, int>{};
    for (final p in _allItems) { categories[p.category] = (categories[p.category] ?? 0) + 1; }

    final chips = [
      _Chip(label: 'All',       count: '${_allItems.length}', active: _stockFilter == 'all',
          onTap: () => setState(() { _stockFilter = 'all'; _showCount = _pageSize; })),
      const SizedBox(width: 6),
      _Chip(label: 'Low Stock', count: '$lowCount', color: AppColors.amber,
          active: _stockFilter == 'low',
          onTap: () => setState(() { _stockFilter = 'low'; _showCount = _pageSize; })),
      const SizedBox(width: 6),
      _Chip(label: 'Out',       count: '$outCount', color: AppColors.coral,
          active: _stockFilter == 'out',
          onTap: () => setState(() { _stockFilter = 'out'; _showCount = _pageSize; })),
      const SizedBox(width: 14),
      if (categories.isNotEmpty)
        _CategoryFilterDropdown(
          categories: categories,
          value: _categoryFilter,
          onChanged: (v) => setState(() { _categoryFilter = v; _showCount = _pageSize; }),
        ),
    ];

    return LayoutBuilder(builder: (context, cst) {
    // Phones: cards instead of the 6-column table, detail as its own page
    // instead of a side panel, filters on a swipeable row, search full width.
    final narrow = cst.maxWidth < 600;
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Header ──
        Container(
          padding: narrow
              ? const EdgeInsets.fromLTRB(16, 14, 16, 12)
              : const EdgeInsets.fromLTRB(24, 18, 24, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Inventory Items', style: AppTheme.pageTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (narrow)
                IconButton(
                  tooltip: 'Export',
                  onPressed: _exportCsv,
                  icon: Icon(Symbols.download, size: 20, color: context.pal.textMute),
                )
              else ...[
                AppButton(label: 'Export', icon: Symbols.download, variant: BtnVariant.ghost, onPressed: _exportCsv),
                const SizedBox(width: 8),
              ],
              AppButton(label: narrow ? 'Add' : 'Add Item', icon: Symbols.add, variant: BtnVariant.primary,
                  onPressed: () => setState(() => _showAdd = true)),
            ]),
            const SizedBox(height: 4),
            Text('${_allItems.length} SKUs · $lowCount low · $outCount out of stock',
                style: AppTheme.bodySub),
            const SizedBox(height: 12),
            if (narrow) ...[
              SearchField(hint: 'Search name, SKU, manufacturer…',
                  onChanged: (v) => setState(() { _search = v; _showCount = _pageSize; })),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: chips),
              ),
            ] else
              Row(children: [
                ...chips,
                const Spacer(),
                _SearchBox(onChanged: (v) => setState(() { _search = v; _showCount = _pageSize; })),
              ]),
          ]),
        ),
        // ── Two-panel body ──
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 3, child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(children: [
                // Table header
                if (!narrow) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
                  child: Row(children: [
                    _Th('Name / Manufacturer', flex: 3),
                    _Th('Category', flex: 2), _Th('Stock', flex: 1),
                    _Th('Reorder', flex: 1), _Th('Unit Cost', flex: 1),
                    const SizedBox(width: 64),
                  ]),
                ),
                if (_loading)
                  shimmerTable(count: 8, cols: 5)
                else if (_error != null && _allItems.isEmpty)
                  ErrorView(message: _error!, onRetry: _load, compact: true)
                else if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Symbols.inventory_2, size: 36, color: context.pal.textDim),
                      const SizedBox(height: 10),
                      Text('No items found', style: AppTheme.bodySub),
                    ])),
                  )
                else ...[
                  if (narrow) ...[
                    const SizedBox(height: 8),
                    ...items.map((p) => _ItemCard(
                      item: p,
                      catLabel: _catLabel(p.category), catColor: _catColor(p.category),
                      onTap:    () => _openDetailPage(p),
                      onEdit:   () => setState(() { _selected = p; _showEdit = true; }),
                      onDelete: () => _deactivate(p),
                    )),
                  ] else ...items.map((p) => _ItemRow(
                    item: p, selected: _selected == p,
                    catLabel: _catLabel(p.category), catColor: _catColor(p.category),
                    onTap:    () => setState(() => _selected = _selected == p ? null : p),
                    onEdit:   () => setState(() { _selected = p; _showEdit = true; }),
                    onDelete: () => _deactivate(p),
                  )),
                  if (remaining > 0)
                    GestureDetector(
                      onTap: () => setState(() => _showCount += _pageSize),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: Text('Showing ${items.length} of ${allFiltered.length} · '
                            'Load ${remaining < _pageSize ? remaining : _pageSize} more',
                            style: AppTheme.bodySm.copyWith(color: AppColors.teal, fontSize: 12.5)),
                      ),
                    )
                  else if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(child: Text('Showing all ${items.length} items',
                          style: AppTheme.bodySub.copyWith(fontSize: 12))),
                    ),
                ],
              ]),
            ),
          )),
          // Detail panel (wide only — phones open it as a page)
          if (_selected != null && !narrow) ...[
            Container(width: 1, color: context.pal.border),
            Expanded(flex: 2, child: _ItemDetailPanel(
              item:    _selected!,
              catLabel: _catLabel(_selected!.category),
              catColor: _catColor(_selected!.category),
              onClose:  () => setState(() => _selected = null),
              onEdit:   () => setState(() => _showEdit = true),
              onMove:   () => setState(() => _showMove = true),
            )),
          ],
        ])),
      ]),
      if (_showAdd)
        _ItemFormModal(
          catLabel: _catLabel, catColor: _catColor,
          onClose: () => setState(() => _showAdd = false),
          onSaved: () { setState(() => _showAdd = false); _load(); },
        ),
      if (_showEdit && _selected != null)
        _ItemFormModal(
          item: _selected!, catLabel: _catLabel, catColor: _catColor,
          onClose: () => setState(() => _showEdit = false),
          onSaved: () { setState(() => _showEdit = false); _load(); },
        ),
      if (_showMove && _selected != null)
        _RecordMovementModal(
          item:    _selected!,
          onClose: () => setState(() => _showMove = false),
          onSaved: () { setState(() => _showMove = false); _load(); },
        ),
    ]);
    });
  }

  /// Phone detail: the same panel as a full page in the content area, so
  /// back (button or gesture) returns to the list where it was scrolled.
  /// Edit / Record movement close the page and open their sheet on the list.
  void _openDetailPage(InventoryItem p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => Scaffold(
      backgroundColor: ctx.pal.bg,
      body: _ItemDetailPanel(
        item:     p,
        catLabel: _catLabel(p.category),
        catColor: _catColor(p.category),
        onClose:  () => Navigator.of(ctx).pop(),
        onEdit:   () { Navigator.of(ctx).pop(); setState(() { _selected = p; _showEdit = true; }); },
        onMove:   () { Navigator.of(ctx).pop(); setState(() { _selected = p; _showMove = true; }); },
      ),
    )));
  }
}

// ── Item row ─────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item, required this.selected,
    required this.catLabel, required this.catColor,
    required this.onTap, this.onEdit, this.onDelete,
  });
  final InventoryItem item;
  final bool selected;
  final String catLabel;
  final Color catColor;
  final VoidCallback onTap;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final stockColor = item.isOutOfStock
        ? AppColors.coral : item.isLowStock ? AppColors.amber : AppColors.teal;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.pal.surface2 : Colors.transparent,
          border: Border(bottom: BorderSide(color: context.pal.divider)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.name, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
              if (item.hasCe)  _CertBadge('CE'),
              if (item.hasFda) _CertBadge('FDA'),
              if (item.hasTbs) _CertBadge('TBS'),
            ]),
            if (item.manufacturer != null)
              Text(item.manufacturer!, style: AppTheme.bodySub.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
          ])),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(catLabel, style: AppTheme.monoXs.copyWith(color: catColor, fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ))),
          Expanded(flex: 1, child: Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: stockColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (item.isOutOfStock || item.isLowStock) ...[
                Icon(item.isOutOfStock ? Symbols.error : Symbols.warning, size: 12, color: stockColor),
                const SizedBox(width: 3),
              ],
              Text('${item.stockQty} ${item.unitOfMeasure}',
                  style: AppTheme.monoXs.copyWith(color: stockColor, fontWeight: FontWeight.w700)),
            ]),
          ))),
          Expanded(flex: 1, child: Text('— ${item.reorderLevel}',
              style: AppTheme.monoXs.copyWith(color: context.pal.textDim))),
          Expanded(flex: 1, child: Text(costText(item.unitCost, item.costCurrency),
              style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
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
}

// ── Item card (phones) ───────────────────────────────────────────────────────

/// One item as a two-line card: name + stock on top, category · cost below.
/// Edit / deactivate sit in a ⋮ menu instead of 15 px icons.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item, required this.catLabel, required this.catColor,
    required this.onTap, this.onEdit, this.onDelete,
  });
  final InventoryItem item;
  final String catLabel;
  final Color catColor;
  final VoidCallback onTap;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final stockColor = item.isOutOfStock
        ? AppColors.coral : item.isLowStock ? AppColors.amber : AppColors.teal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: context.pal.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.pal.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: AppTheme.bodyStrong.copyWith(fontSize: 14),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (item.manufacturer != null) ...[
                  const SizedBox(height: 2),
                  Text(item.manufacturer!, style: AppTheme.bodySub.copyWith(fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (item.isOutOfStock || item.isLowStock) ...[
                        Icon(item.isOutOfStock ? Symbols.error : Symbols.warning, size: 12, color: stockColor),
                        const SizedBox(width: 3),
                      ],
                      Text('${item.stockQty} ${item.unitOfMeasure}',
                          style: AppTheme.monoXs.copyWith(color: stockColor, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  if (catLabel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(catLabel, style: AppTheme.monoXs.copyWith(color: catColor, fontSize: 10)),
                    ),
                  Text(costText(item.unitCost, item.costCurrency),
                      style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
                ]),
              ])),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                color: context.pal.surface1,
                icon: Icon(Symbols.more_vert, size: 20, color: context.pal.textDim),
                onSelected: (v) => (v == 'edit' ? onEdit : onDelete)?.call(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('Edit', style: AppTheme.bodySm)),
                  PopupMenuItem(value: 'delete', child: Text('Deactivate',
                      style: AppTheme.bodySm.copyWith(color: AppColors.coral))),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Detail panel ─────────────────────────────────────────────────────────────

class _ItemDetailPanel extends StatelessWidget {
  const _ItemDetailPanel({
    required this.item, required this.catLabel, required this.catColor,
    required this.onClose, this.onEdit, this.onMove,
  });
  final InventoryItem item;
  final String catLabel;
  final Color catColor;
  final VoidCallback onClose;
  final VoidCallback? onEdit, onMove;

  @override
  Widget build(BuildContext context) {
    final stockColor = item.isOutOfStock
        ? AppColors.coral : item.isLowStock ? AppColors.amber : AppColors.teal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.name, style: AppTheme.bodyStrong)),
          GestureDetector(onTap: onClose,
              child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
        ]),
        const SizedBox(height: 3),
        Text(item.sku, style: AppTheme.monoXs.copyWith(color: context.pal.textMute)),
        const SizedBox(height: 14),
        // Stock status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: stockColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stockColor.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(item.isOutOfStock ? Symbols.error
                : item.isLowStock ? Symbols.warning : Symbols.check_circle,
                size: 20, color: stockColor),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item.stockQty} ${item.unitOfMeasure} in stock',
                  style: AppTheme.bodyStrong.copyWith(color: stockColor)),
              Text(item.isOutOfStock ? 'Out of stock — reorder now'
                  : item.isLowStock ? 'Below reorder level (${item.reorderLevel})'
                  : 'Stock level OK',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: stockColor)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        // Certifications
        if (item.hasCe || item.hasFda || item.hasTbs) ...[
          Wrap(spacing: 6, children: [
            if (item.hasCe)  _CertBadge('CE',  large: true),
            if (item.hasFda) _CertBadge('FDA', large: true),
            if (item.hasTbs) _CertBadge('TBS', large: true),
          ]),
          const SizedBox(height: 14),
        ],
        if (item.stockLevels.isNotEmpty) ...[
          Text('Stock by Location', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
          const SizedBox(height: 6),
          ...item.stockLevels.map((l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Symbols.location_on, size: 12, color: context.pal.textDim),
              const SizedBox(width: 6),
              Expanded(child: Text(l.locationName,
                  style: AppTheme.bodySm.copyWith(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
              Text('${l.quantityOnHand.toStringAsFixed(0)} ${item.unitOfMeasure}',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
            ]),
          )),
          const SizedBox(height: 14),
        ],
        _Row('SKU',          item.sku),
        _Row('Category',     catLabel),
        _Row('Unit',         item.unitOfMeasure),
        if (item.manufacturer != null) _Row('Manufacturer', item.manufacturer!),
        if (item.barcode != null)      _Row('Barcode',      item.barcode!),
        _Row('Unit Cost',    costText(item.unitCost, item.costCurrency)),
        _Row('Stock Value',  costText(item.stockQty * item.unitCost, item.costCurrency)),
        _Row('Reorder At',   '${item.reorderLevel} ${item.unitOfMeasure}'),
        if (item.supplier.isNotEmpty) _Row('Supplier', item.supplier),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: onMove,
          child: Container(height: 38,
            decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Symbols.swap_vert, size: 16, color: Color(0xFF06120F)),
              const SizedBox(width: 8),
              Text('Record Movement', style: AppTheme.bodyStrong.copyWith(
                  color: const Color(0xFF06120F), fontSize: 13)),
            ]),
          ),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: onEdit,
          child: Container(height: 38,
            decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('Edit Item', style: AppTheme.bodySm)),
          ),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InventoryItemDetailScreen(item: item),
            ),
          ),
          child: Container(height: 38,
            decoration: BoxDecoration(border: Border.all(color: context.pal.border),
                borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Symbols.open_in_full, size: 14, color: context.pal.textMute),
              const SizedBox(width: 7),
              Text('Full Details', style: AppTheme.bodySm),
            ]),
          ),
        )),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

// ── Record Movement modal ────────────────────────────────────────────────────

class _RecordMovementModal extends StatefulWidget {
  const _RecordMovementModal({required this.item, required this.onClose, this.onSaved});
  final InventoryItem item;
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_RecordMovementModal> createState() => _RecordMovementModalState();
}

class _RecordMovementModalState extends State<_RecordMovementModal> {
  String _type = 'receive';
  final _qtyCtrl    = TextEditingController(text: '1');
  final _notesCtrl  = TextEditingController();
  bool   _saving = false;
  String? _error;

  int? _locationId;
  int? _toLocationId;
  List<Location> _locations = [];
  bool _loadingLocations = true;

  static const _types = ['receive', 'issue', 'transfer', 'write_off', 'adjustment', 'return'];
  static const _typeLabels = ['Receive', 'Issue / Use', 'Transfer', 'Write-off', 'Adjustment', 'Return'];
  bool get _isTransfer => _type == 'transfer';

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await LocationService.instance.list();
      if (mounted){ setState(() {
        _locations = locs;
        _locationId ??= locs.isNotEmpty ? locs.first.id : null;
        _loadingLocations = false;
      });}
    } catch (_) {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  @override
  void dispose() { _qtyCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty == 0) { setState(() => _error = 'Enter a non-zero quantity.'); return; }
    if (_locationId == null) { setState(() => _error = 'Select a location.'); return; }
    if (_isTransfer && _toLocationId == null) { setState(() => _error = 'Select a destination location.'); return; }
    if (_isTransfer && _toLocationId == _locationId) { setState(() => _error = 'Source and destination must differ.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await StockMovementService.instance.record(
        inventoryItemId: widget.item.id,
        locationId: _locationId!,
        toLocationId: _isTransfer ? _toLocationId : null,
        type:     _type,
        quantity: qty,
        notes:    _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) showSuccessToast(context, 'Movement recorded for ${widget.item.name}');
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
          width: 420,
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
                Expanded(child: Text('Record Movement — ${widget.item.name}',
                    style: AppTheme.bodyStrong, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Movement type', style: AppTheme.fieldLabel),
                const SizedBox(height: 6),
                DropdownFieldBox<String>(
                  value: _type,
                  items: _types.asMap().entries.map((e) => DropdownMenuItem(
                      value: e.value, child: Text(_typeLabels[e.key]),
                    )).toList(),
                  onChanged: (v) { if (v != null) setState(() => _type = v); },
                ),
                const SizedBox(height: 12),
                Text(_isTransfer ? 'FROM LOCATION' : 'LOCATION', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                const SizedBox(height: 6),
                if (_loadingLocations)
                  ShimmerBox(height: fieldHeightOf(context), radius: 10)
                else
                  DropdownFieldBox<int>(
                    value: _locationId,
                    items: _locations.map((l) => DropdownMenuItem(
                        value: l.id, child: Text(l.name),
                      )).toList(),
                    onChanged: (v) { if (v != null) setState(() {
                        _locationId = v;
                        if (_toLocationId == v) _toLocationId = null;
                      }); },
                  ),
                if (_isTransfer) ...[
                  const SizedBox(height: 12),
                  Text('TO LOCATION', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                  const SizedBox(height: 6),
                  if (_loadingLocations)
                    ShimmerBox(height: fieldHeightOf(context), radius: 10)
                  else
                    DropdownFieldBox<int>(
                      value: _toLocationId,
                      hint: 'Select destination',
                      items: _locations
                            .where((l) => l.id != _locationId)
                            .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                            .toList(),
                      onChanged: (v) { if (v != null) setState(() => _toLocationId = v); },
                    ),
                ],
                const SizedBox(height: 12),
                LabeledTextField(label: 'Quantity', controller: _qtyCtrl, keyboardType: TextInputType.number, hint: '1'),
                const SizedBox(height: 12),
                LabeledTextField(label: 'Notes (optional)', controller: _notesCtrl, hint: 'e.g. received from supplier'),
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
                      : Text('Confirm', style: AppTheme.bodyStrong.copyWith(
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

// ── Add / Edit modal ─────────────────────────────────────────────────────────

class _ItemFormModal extends StatefulWidget {
  const _ItemFormModal({this.item, required this.catLabel, required this.catColor,
      required this.onClose, this.onSaved});
  final InventoryItem? item;
  final String Function(String) catLabel;
  final Color  Function(String) catColor;
  final VoidCallback  onClose;
  final VoidCallback? onSaved;

  @override
  State<_ItemFormModal> createState() => _ItemFormModalState();
}

class _ItemFormModalState extends State<_ItemFormModal> {
  late final _nameCtrl  = TextEditingController(text: widget.item?.name ?? '');
  late final _skuCtrl   = TextEditingController(text: widget.item?.sku  ?? '');
  late final _qtyCtrl   = TextEditingController(text: widget.item != null ? '${widget.item!.stockQty}' : '0');
  late final _costCtrl  = TextEditingController(text: widget.item != null ? widget.item!.unitCost.toStringAsFixed(0) : '');
  late String _costCurrency = widget.item?.costCurrency ?? 'TZS';
  late final _reorderCtrl = TextEditingController(text: widget.item != null ? '${widget.item!.reorderLevel}' : '2');
  late final _mfgCtrl   = TextEditingController(text: widget.item?.manufacturer ?? '');
  int?    _categoryId;
  late String _uom      = widget.item?.unitOfMeasure ?? 'piece';
  late bool   _hasCe    = widget.item?.hasCe  ?? false;
  late bool   _hasFda   = widget.item?.hasFda ?? false;
  late bool   _hasTbs   = widget.item?.hasTbs ?? false;
  late bool   _needsReview = widget.item?.needsReview ?? false;
  late final _warrantyCtrl = TextEditingController(
      text: widget.item?.warrantyMonths?.toString() ?? '');
  bool    _saving = false;
  String? _error;

  List<Category> _categories = [];
  bool _loadingCategories = true;

  static const _uoms = ['piece', 'box', 'litre', 'set', 'kg', 'roll', 'pair', 'bottle'];

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.item?.categoryId;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await CategoryService.instance.list();
      if (mounted) {setState(() {
        _categories = cats;
        // Match what the dropdown will visually show — it falls back to the
        // first item when the current value isn't in the list.
        _categoryId ??= cats.isNotEmpty ? cats.first.id : null;
        _loadingCategories = false;
      });}
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _skuCtrl.dispose(); _qtyCtrl.dispose();
    _costCtrl.dispose(); _reorderCtrl.dispose(); _mfgCtrl.dispose();
    _warrantyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _nameCtrl.text.trim().isEmpty || _skuCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final data = {
        'name':           _nameCtrl.text.trim(),
        'sku':            _skuCtrl.text.trim(),
        'category_id':    _categoryId,
        'unit_of_measure': _uom,
        'unit_cost':      int.tryParse(_costCtrl.text.trim()) ?? 0,
        'cost_currency':  _costCurrency,
        'stock_qty':      int.tryParse(_qtyCtrl.text.trim()) ?? 0,
        'reorder_level':  int.tryParse(_reorderCtrl.text.trim()) ?? 2,
        'manufacturer':   _mfgCtrl.text.trim().isEmpty ? null : _mfgCtrl.text.trim(),
        'has_ce':         _hasCe,
        'has_fda':        _hasFda,
        'has_tbs':        _hasTbs,
        'warranty_months': _warrantyCtrl.text.trim().isEmpty ? null : int.tryParse(_warrantyCtrl.text.trim()),
        if (_isEdit) 'needs_review': _needsReview,
      };
      if (_isEdit) {
        await InventoryService.instance.update(widget.item!.id, data);
      } else {
        await InventoryService.instance.create(data);
      }
      if (mounted) showSuccessToast(context, _isEdit ? 'Item updated' : 'Item added');
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
      child: PhoneModalBox(scroll: false, child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 560,
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(_isEdit ? Symbols.edit : Symbols.inventory_2, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Text(_isEdit ? 'Edit: ${widget.item!.name}' : 'Add Inventory Item',
                    style: AppTheme.bodyStrong),
                const Spacer(),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(children: [
                Row(children: [
                  Expanded(child: _Field(label: 'Item Name', ctrl: _nameCtrl, hint: 'e.g. Flow Sensor Module')),
                  const SizedBox(width: 14),
                  Expanded(child: _Field(label: 'SKU', ctrl: _skuCtrl, hint: 'e.g. MIN-FS-6800')),
                ]),
                const SizedBox(height: 14),
                _Field(label: 'Manufacturer', ctrl: _mfgCtrl, hint: 'e.g. Mindray Medical'),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _loadingCategories
                    ? const _DropdownSkeleton(label: 'Category')
                    : _Dropdown(
                        label: 'Category',
                        value: _categoryId != null ? '$_categoryId' : '',
                        items: _categories.map((c) => '${c.id}').toList(),
                        labels: _categories.map((c) => c.name).toList(),
                        onChanged: (v) => setState(() => _categoryId = int.tryParse(v)),
                      )),
                  const SizedBox(width: 14),
                  Expanded(child: _Dropdown(
                    label: 'Unit of Measure', value: _uom,
                    items: _uoms,
                    onChanged: (v) => setState(() => _uom = v),
                  )),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Field(label: 'Qty in Stock', ctrl: _qtyCtrl, hint: '0', numeric: true)),
                  const SizedBox(width: 14),
                  Expanded(child: _Field(label: 'Reorder Level', ctrl: _reorderCtrl, hint: '2', numeric: true)),
                  const SizedBox(width: 14),
                  Expanded(child: _Field(label: 'Unit Cost', ctrl: _costCtrl, hint: '0', numeric: true)),
                  const SizedBox(width: 8),
                  SizedBox(width: 96, child: _Dropdown(label: 'Currency', value: _costCurrency, items: kCostCurrencies,
                      onChanged: (v) => setState(() => _costCurrency = v))),
                ]),
                const SizedBox(height: 14),
                // Certifications
                // Wraps so the chips drop under the label on a phone.
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('CERTIFICATIONS', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                  ),
                  _CheckChip(label: 'CE',  value: _hasCe,  onChanged: (v) => setState(() => _hasCe = v)),
                  _CheckChip(label: 'FDA', value: _hasFda, onChanged: (v) => setState(() => _hasFda = v)),
                  _CheckChip(label: 'TBS', value: _hasTbs, onChanged: (v) => setState(() => _hasTbs = v)),
                ]),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: SizedBox(width: 140, child: _Field(
                    label: 'Warranty (months)', ctrl: _warrantyCtrl, hint: '12', numeric: true))),
                if (_isEdit) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    _CheckChip(label: 'Needs Review', value: _needsReview,
                        onChanged: (v) => setState(() => _needsReview = v)),
                  ]),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ],
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
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
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? 'Save Changes' : 'Add Item',
                          style: AppTheme.bodyStrong.copyWith(
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

class _CertBadge extends StatelessWidget {
  const _CertBadge(this.label, {this.large = false});
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 4),
    padding: EdgeInsets.symmetric(horizontal: large ? 7 : 4, vertical: large ? 3 : 1),
    decoration: BoxDecoration(
      color: AppColors.tealSoft,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: AppTheme.monoXs.copyWith(
        color: AppColors.teal, fontSize: large ? 10.5 : 9, fontWeight: FontWeight.w700)),
  );
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value ? AppColors.tealSoft : context.pal.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: value ? AppColors.teal : context.pal.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(value ? Symbols.check_circle : Symbols.radio_button_unchecked,
            size: 14, color: value ? AppColors.teal : context.pal.textDim),
        const SizedBox(width: 5),
        Text(label, style: AppTheme.bodySm.copyWith(
            color: value ? AppColors.teal : context.pal.textMute,
            fontWeight: value ? FontWeight.w600 : FontWeight.w400, fontSize: 12)),
      ]),
    ),
  );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) =>
      SearchField(width: 260, hint: 'Search name, SKU, manufacturer…', onChanged: onChanged);
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.ctrl, required this.hint,
      this.numeric = false});
  final String label, hint;
  final TextEditingController ctrl;
  final bool numeric;

  // The Settings text input (shared LabeledTextField).
  @override
  Widget build(BuildContext context) => LabeledTextField(label: label, controller: ctrl, hint: hint, keyboardType: numeric ? TextInputType.number : TextInputType.text);
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items,
      this.labels, required this.onChanged});
  final String label, value;
  final List<String> items;
  final List<String>? labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    // No options yet (e.g. no categories set up): an empty, disabled box
    // instead of crashing on items.first.
    if (items.isEmpty)
      DropdownFieldBox<String>(value: null, items: const [], onChanged: null)
    else DropdownFieldBox<String>(
      value: items.contains(value) ? value : items.first,
      items: items.asMap().entries.map((e) => DropdownMenuItem(
          value: e.value, child: Text(labels != null ? labels![e.key] : e.value),
        )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    ),
  ]);
}

class _DropdownSkeleton extends StatelessWidget {
  const _DropdownSkeleton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.labelCaps.copyWith(fontSize: 10)),
    const SizedBox(height: 6),
    const ShimmerBox(height: 38, radius: 8),
  ]);
}

class _CategoryFilterDropdown extends StatelessWidget {
  const _CategoryFilterDropdown({required this.categories, required this.value, required this.onChanged});
  final Map<String, int> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final total = categories.values.fold(0, (a, b) => a + b);
    return DropdownFieldBox<String?>(
      width: 220,
      value: value,
      items: [
          DropdownMenuItem(value: null, child: Text('All Categories ($total)', overflow: TextOverflow.ellipsis)),
          ...categories.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text('${e.key} (${e.value})', overflow: TextOverflow.ellipsis))),
        ],
      onChanged: onChanged,
      active: value != null,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.active,
      required this.onTap, this.color});
  final String label, count;
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppTheme.bodySm.copyWith(
            color: active ? (color ?? AppColors.teal) : context.pal.textMute, fontSize: 12)),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (color ?? AppColors.teal).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(count, style: AppTheme.bodySub.copyWith(
                color: color ?? AppColors.teal, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
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
