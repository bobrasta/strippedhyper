import '../../widgets/finance/connections_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/batch_lot.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_item_history.dart';
import '../../models/serial_number.dart';
import '../../models/stock_movement.dart';
import '../../models/supplier.dart';
import '../../services/batch_lot_service.dart';
import '../../services/inventory_service.dart';
import '../../services/serial_number_service.dart';
import '../../services/stock_movement_service.dart';
import '../../services/supplier_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/shimmer_box.dart';

class InventoryItemDetailScreen extends StatelessWidget {
  const InventoryItemDetailScreen({super.key, required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: context.pal.bg,
        appBar: AppBar(
          backgroundColor: context.pal.surface1,
          foregroundColor: context.pal.text,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 4,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
              Text(item.sku,
                  style: AppTheme.monoXs.copyWith(color: context.pal.textMute, fontSize: 11)),
            ],
          ),
          // The stock trail: every LPO, payment, invoice, shipment and store movement behind this item.
          actions: [ConnectionsButton(type: 'inventory_item', id: item.id, compact: true), const SizedBox(width: 8)],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.teal,
            unselectedLabelColor: context.pal.textMute,
            indicatorColor: AppColors.teal,
            indicatorWeight: 2,
            labelStyle: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
            unselectedLabelStyle: AppTheme.bodySm,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Movements'),
              Tab(text: 'Batches'),
              Tab(text: 'Serials'),
              Tab(text: 'History'),
              Tab(text: 'Suppliers'),
              Tab(text: 'Barcode'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(item: item),
            _MovementsTab(item: item),
            _BatchesTab(item: item),
            _SerialsTab(item: item),
            _HistoryTab(item: item),
            _SuppliersTab(item: item),
            _BarcodeTab(item: item),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

// Categories are a real, admin-managed list now — item.category is already
// the resolved display name, so just show it and pick a stable color by
// hashing the name across a small fixed palette.
String _catLabel(String cat) => cat;

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130,
          child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

class _CertBadge extends StatelessWidget {
  const _CertBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.teal.withValues(alpha: 0.12),
      border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label,
        style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontWeight: FontWeight.w700, fontSize: 10.5)),
  );
}

// ── Overview tab ───────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final stockColor = item.isOutOfStock
        ? AppColors.coral
        : item.isLowStock
            ? AppColors.amber
            : AppColors.teal;
    final catLabel = _catLabel(item.category);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Stock status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stockColor.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(
                  item.isOutOfStock
                      ? Symbols.error
                      : item.isLowStock
                          ? Symbols.warning
                          : Symbols.check_circle,
                  size: 24,
                  color: stockColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item.stockQty} ${item.unitOfMeasure} in stock',
                        style: AppTheme.bodyStrong.copyWith(color: stockColor, fontSize: 14)),
                    Text(
                      item.isOutOfStock
                          ? 'Out of stock — reorder now'
                          : item.isLowStock
                              ? 'Below reorder level (${item.reorderLevel} ${item.unitOfMeasure})'
                              : 'Stock level OK — reorder at ${item.reorderLevel} ${item.unitOfMeasure}',
                      style: AppTheme.bodySub.copyWith(color: stockColor.withValues(alpha: 0.8)),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(costText(item.stockQty * item.unitCost, item.costCurrency),
                      style: AppTheme.bodyStrong.copyWith(fontSize: 15)),
                  Text('Stock value', style: AppTheme.bodySub.copyWith(fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),

            // Certifications
            if (item.hasCe || item.hasFda || item.hasTbs) ...[
              Text('CERTIFICATIONS', style: AppTheme.labelCaps),
              const SizedBox(height: 8),
              Row(children: [
                if (item.hasCe)  const _CertBadge('CE'),
                if (item.hasFda) const _CertBadge('FDA'),
                if (item.hasTbs) const _CertBadge('TBS'),
              ]),
              const SizedBox(height: 20),
            ],

            // Details + Pricing side-by-side
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _Section(
                  title: 'ITEM DETAILS',
                  child: Column(children: [
                    _InfoRow('SKU',          item.sku),
                    _InfoRow('Category',     catLabel),
                    _InfoRow('Unit',         item.unitOfMeasure),
                    if (item.manufacturer != null) _InfoRow('Manufacturer', item.manufacturer!),
                    if (item.description != null && item.description!.isNotEmpty)
                      _InfoRow('Description', item.description!),
                    if (item.supplier.isNotEmpty) _InfoRow('Supplier', item.supplier),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Section(
                  title: 'PRICING & STOCK',
                  child: Column(children: [
                    _InfoRow('Unit Cost',    costText(item.unitCost, item.costCurrency)),
                    _InfoRow('Currency',     item.currency),
                    _InfoRow('In Stock',     '${item.stockQty} ${item.unitOfMeasure}'),
                    _InfoRow('Reorder At',   '${item.reorderLevel} ${item.unitOfMeasure}'),
                    _InfoRow('Stock Value',  costText(item.stockQty * item.unitCost, item.costCurrency)),
                    _InfoRow('Category tag',
                        _catLabel(item.category)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Stock by location
            if (item.stockLevels.isNotEmpty) ...[
              _Section(
                title: 'STOCK BY LOCATION',
                child: Column(children: item.stockLevels.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(Symbols.location_on, size: 14, color: context.pal.textDim),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.locationName, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
                    if (l.quantityReserved > 0) ...[
                      Text('${l.quantityReserved.toStringAsFixed(0)} reserved',
                          style: AppTheme.bodySub.copyWith(fontSize: 11)),
                      const SizedBox(width: 10),
                    ],
                    Text('${l.quantityOnHand.toStringAsFixed(0)} ${item.unitOfMeasure}',
                        style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                  ]),
                )).toList()),
              ),
              const SizedBox(height: 16),
            ],

            // Specifications
            if (item.specifications.isNotEmpty) ...[
              _Section(
                title: 'SPECIFICATIONS',
                child: Wrap(
                  spacing: 16,
                  runSpacing: 0,
                  children: item.specifications.entries.map((e) {
                    final val = e.value?.toString() ?? '—';
                    return SizedBox(
                      width: 200,
                      child: _InfoRow(e.key, val),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTheme.labelCaps),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

// ── Movements tab ─────────────────────────────────────────────────────────────

class _MovementsTab extends StatefulWidget {
  const _MovementsTab({required this.item});
  final InventoryItem item;

  @override
  State<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<_MovementsTab>
    with AutomaticKeepAliveClientMixin {
  List<StockMovement>? _movements;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known movements for this item
    // immediately (if any) instead of blanking to a spinner on every
    // navigation.
    final cached = StockMovementService.cachedByItemId[widget.item.id];
    if (cached != null) { _movements = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_movements == null) _loading = true;
      _error = null;
    });
    try {
      final data = await StockMovementService.instance
          .list(inventoryItemId: widget.item.id);
      if (mounted) setState(() { _movements = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: shimmerList(count: 8),
      );
    }
    // A background refresh erroring while stale-but-valid cached data is
    // already showing shouldn't blow that away.
    if (_error != null && _movements == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    final movements = _movements ?? [];
    if (movements.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.swap_vert, size: 40, color: context.pal.textDim),
          const SizedBox(height: 12),
          Text('No movements recorded', style: AppTheme.bodySub),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: movements.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _MovementCard(m: movements[i]),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.m});
  final StockMovement m;

  Color get _typeColor => switch (m.type) {
    'receive'    => AppColors.green,
    'return'     => AppColors.teal,
    'issue'      => AppColors.amber,
    'transfer'   => AppColors.violet,
    'write_off'  => AppColors.coral,
    'adjustment' => AppColors.textMute,
    _            => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColor;
    final delta = m.quantity;
    final sign  = delta > 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.pal.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(m.typeLabel,
              style: AppTheme.monoXs.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 10.5)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$sign$delta ${m.itemSku != null ? '' : ''}',
                  style: AppTheme.bodyStrong.copyWith(
                      color: delta > 0 ? AppColors.green : AppColors.coral,
                      fontSize: 13)),
              Text('  ${m.quantityBefore} → ${m.quantityAfter}',
                  style: AppTheme.monoXs.copyWith(color: context.pal.textMute, fontSize: 11)),
            ]),
            if (m.notes != null && m.notes!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(m.notes!, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            ],
            if (m.batchNumber != null) ...[
              const SizedBox(height: 3),
              Text('Batch: ${m.batchNumber}',
                  style: AppTheme.monoXs.copyWith(color: context.pal.textDim, fontSize: 10.5)),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatDate(m.createdAt),
              style: AppTheme.bodySub.copyWith(fontSize: 11)),
          if (m.performedByName != null) ...[
            const SizedBox(height: 2),
            Text(m.performedByName!,
                style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
          ],
        ]),
      ]),
    );
  }
}

// ── Suppliers tab ─────────────────────────────────────────────────────────────

class _SuppliersTab extends StatefulWidget {
  const _SuppliersTab({required this.item});
  final InventoryItem item;

  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab>
    with AutomaticKeepAliveClientMixin {
  Supplier? _supplier;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final preferredId = widget.item.preferredSupplierId;
    if (preferredId != null) {
      // Stale-while-revalidate: show the last-known supplier immediately
      // (if any) instead of blanking to a spinner on every navigation.
      final cached = SupplierService.cachedById[preferredId];
      if (cached != null) _supplier = cached;
      _loadSupplier();
    }
  }

  Future<void> _loadSupplier() async {
    setState(() {
      if (_supplier == null) _loading = true;
      _error = null;
    });
    try {
      final s = await SupplierService.instance.get(widget.item.preferredSupplierId!);
      if (mounted) setState(() { _supplier = s; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Preferred supplier (full card)
            if (widget.item.preferredSupplierId != null) ...[
              Text('PREFERRED SUPPLIER', style: AppTheme.labelCaps),
              const SizedBox(height: 10),
              if (_loading) shimmerList(count: 1),
              // A background refresh erroring while stale-but-valid cached
              // data is already showing shouldn't cover it with an error
              // banner — only surface the error when there's nothing to show.
              if (_error != null && _supplier == null)
                ErrorView(message: _error!, onRetry: _loadSupplier, compact: true),
              if (_supplier != null) _SupplierCard(supplier: _supplier!),
              const SizedBox(height: 24),
            ],

            // Supplier string fallback
            if (widget.item.supplier.isNotEmpty &&
                (_supplier == null || !_loading)) ...[
              Text('SUPPLIER NAME', style: AppTheme.labelCaps),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.pal.surface1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.pal.border),
                ),
                child: Row(children: [
                  Icon(Symbols.business, size: 20, color: context.pal.textDim),
                  const SizedBox(width: 12),
                  Text(widget.item.supplier, style: AppTheme.bodyStrong),
                ]),
              ),
            ],

            if (widget.item.preferredSupplierId == null &&
                widget.item.supplier.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Symbols.business, size: 40, color: context.pal.textDim),
                    const SizedBox(height: 12),
                    Text('No supplier linked', style: AppTheme.bodySub),
                    const SizedBox(height: 6),
                    Text('Edit this item to assign a supplier.',
                        style: AppTheme.bodySub.copyWith(fontSize: 11)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(supplier.name, style: AppTheme.bodyStrong.copyWith(fontSize: 14)),
            const SizedBox(height: 2),
            Text(supplier.typeLabel, style: AppTheme.bodySub.copyWith(fontSize: 12)),
          ]),
        ),
        // Rating stars
        Row(children: List.generate(5, (i) => Icon(
          i < supplier.rating ? Symbols.star : Symbols.star_outline,
          size: 14,
          color: i < supplier.rating ? AppColors.amber : context.pal.textDim,
        ))),
      ]),
      Divider(height: 24, color: context.pal.divider),
      if (supplier.contactName != null)
        _InfoRow('Contact', supplier.contactName!),
      if (supplier.contactEmail != null)
        _InfoRow('Email', supplier.contactEmail!),
      if (supplier.contactPhone != null)
        _InfoRow('Phone', supplier.contactPhone!),
      if (supplier.location != '—')
        _InfoRow('Location', supplier.location),
      if (supplier.website != null)
        _InfoRow('Website', supplier.website!),
      _InfoRow('Currency', supplier.currency),
      if (supplier.paymentTerms != null)
        _InfoRow('Payment Terms', supplier.paymentTerms!),
      _InfoRow('Lead Time', '${supplier.leadTimeDays} day${supplier.leadTimeDays == 1 ? '' : 's'}'),
      if (supplier.notes != null && supplier.notes!.isNotEmpty)
        _InfoRow('Notes', supplier.notes!),
    ]),
  );
}

// ── Batches tab ───────────────────────────────────────────────────────────────

class _BatchesTab extends StatefulWidget {
  const _BatchesTab({required this.item});
  final InventoryItem item;

  @override
  State<_BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends State<_BatchesTab>
    with AutomaticKeepAliveClientMixin {
  List<BatchLot>? _lots;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known batches for this item
    // immediately (if any) instead of blanking to a spinner on every
    // navigation.
    final cached = BatchLotService.cachedByItemId[widget.item.id];
    if (cached != null) { _lots = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_lots == null) _loading = true;
      _error = null;
    });
    try {
      final data = await BatchLotService.instance.listForItem(widget.item.id);
      if (mounted) setState(() { _lots = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return Padding(padding: const EdgeInsets.all(24), child: shimmerList(count: 5));
    // A background refresh erroring while stale-but-valid cached data is
    // already showing shouldn't blow that away.
    if (_error != null && _lots == null) return ErrorView(message: _error!, onRetry: _load);

    final lots = _lots ?? [];
    if (lots.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.inventory_2, size: 40, color: context.pal.textDim),
          const SizedBox(height: 12),
          Text('No batches / lots recorded', style: AppTheme.bodySub),
          const SizedBox(height: 6),
          Text('Add batches when stock is received.',
              style: AppTheme.bodySub.copyWith(fontSize: 11)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: lots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BatchCard(lot: lots[i]),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.lot});
  final BatchLot lot;

  Color _statusColor() {
    if (lot.isExpired)      return AppColors.coral;
    if (lot.isExpiringSoon) return AppColors.amber;
    return AppColors.green;
  }

  String _statusLabel() {
    if (lot.isExpired)      return 'Expired';
    if (lot.isExpiringSoon) return 'Expiring soon';
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lot.isExpired ? AppColors.coral.withValues(alpha: 0.4) : context.pal.border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(lot.batchNumber,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
              if (lot.lotNumber != null) ...[
                const SizedBox(width: 8),
                Text('/ ${lot.lotNumber}',
                    style: AppTheme.monoXs.copyWith(color: context.pal.textMute)),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_statusLabel(),
                style: AppTheme.monoXs.copyWith(color: color, fontSize: 10.5)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Remaining', style: AppTheme.bodySub.copyWith(fontSize: 11)),
            Text('${lot.qtyRemaining} / ${lot.qtyReceived}',
                style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
          ])),
          if (lot.expiryDate != null)
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Expiry', style: AppTheme.bodySub.copyWith(fontSize: 11)),
              Text(formatDate(lot.expiryDate!),
                  style: AppTheme.bodyStrong.copyWith(
                      fontSize: 12.5,
                      color: lot.isExpired ? AppColors.coral
                          : lot.isExpiringSoon ? AppColors.amber : null)),
            ])),
          if (lot.receivedAt != null)
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Received', style: AppTheme.bodySub.copyWith(fontSize: 11)),
              Text(formatDate(lot.receivedAt!),
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12.5)),
            ])),
        ]),
        if (lot.supplierName != null || lot.unitCost > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (lot.supplierName != null) ...[
              Icon(Symbols.business, size: 12, color: context.pal.textDim),
              const SizedBox(width: 5),
              Text(lot.supplierName!,
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              const SizedBox(width: 16),
            ],
            if (lot.unitCost > 0)
              Text(tshFromDouble(lot.unitCost),
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          ]),
        ],
        if (lot.notes != null && lot.notes!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(lot.notes!, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        ],
      ]),
    );
  }
}

// ── Serials tab ────────────────────────────────────────────────────────────────

class _SerialsTab extends StatefulWidget {
  const _SerialsTab({required this.item});
  final InventoryItem item;

  @override
  State<_SerialsTab> createState() => _SerialsTabState();
}

class _SerialsTabState extends State<_SerialsTab>
    with AutomaticKeepAliveClientMixin {
  List<SerialNumber>? _serials;
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known serials for this item
    // immediately (if any) instead of blanking to a spinner on every
    // navigation. Only seeded
    // when starting on the unfiltered (All) view, matching how
    // SerialNumberService.cachedByItemId is populated.
    final cached = SerialNumberService.cachedByItemId[widget.item.id];
    if (cached != null && _statusFilter == null) { _serials = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_serials == null) _loading = true;
      _error = null;
    });
    try {
      final data = await SerialNumberService.instance
          .listForItem(widget.item.id, status: _statusFilter);
      if (mounted) setState(() { _serials = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  static const _statuses = [null, 'available', 'assigned', 'in_service', 'damaged', 'disposed'];
  static const _statusLabels = ['All', 'Available', 'Assigned', 'In Service', 'Damaged', 'Disposed'];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      // Filter chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(
          children: List.generate(_statuses.length, (i) {
            final selected = _statusFilter == _statuses[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _statusFilter = _statuses[i]);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.teal : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.teal : context.pal.border,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabels[i],
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

      Expanded(
        child: _loading
            ? Padding(padding: const EdgeInsets.all(24), child: shimmerList(count: 6))
            : _error != null && _serials == null
                ? ErrorView(message: _error!, onRetry: _load)
                : (_serials ?? []).isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Symbols.qr_code, size: 40, color: context.pal.textDim),
                          const SizedBox(height: 12),
                          Text('No serial numbers found', style: AppTheme.bodySub),
                        ]),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: (_serials ?? []).length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _SerialCard(serial: _serials![i]),
                      ),
      ),
    ]);
  }
}

class _SerialCard extends StatelessWidget {
  const _SerialCard({required this.serial});
  final SerialNumber serial;

  Color _statusColor() => switch (serial.status) {
    'available'  => AppColors.green,
    'assigned'   => AppColors.teal,
    'in_service' => AppColors.violet,
    'damaged'    => AppColors.amber,
    'disposed'   => AppColors.coral,
    _            => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.pal.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Symbols.qr_code_2, size: 18, color: context.pal.textDim),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(serial.serialNumber,
                style: AppTheme.monoSm.copyWith(
                    color: context.pal.text, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 14, children: [
              if (serial.locationName != null)
                _SerialMeta(Symbols.location_on, serial.locationName!),
              if (serial.warrantyExpiresAt != null)
                _SerialMeta(
                  Symbols.verified_user,
                  'Warranty ${serial.isWarrantyExpired ? 'expired' : 'until'} ${formatDate(serial.warrantyExpiresAt!)}',
                  color: serial.isWarrantyExpired ? AppColors.coral : null,
                ),
              if (serial.purchaseDate != null)
                _SerialMeta(Symbols.calendar_today, formatDate(serial.purchaseDate!)),
            ]),
            if (serial.notes != null && serial.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(serial.notes!, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(serial.statusLabel,
              style: AppTheme.monoXs.copyWith(color: color, fontSize: 10.5)),
        ),
      ]),
    );
  }
}

class _SerialMeta extends StatelessWidget {
  const _SerialMeta(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: color ?? context.pal.textDim),
    const SizedBox(width: 4),
    Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11, color: color)),
  ]);
}

// ── History tab ────────────────────────────────────────────────────────────────
// Per-serial chain of custody: received → sold / issued (which sale or
// reference) — one row per physical unit, oldest received first, until the count reaches zero. Distinct from the
// Movements tab (raw item-level stock ledger) and Serials tab (current
// snapshot only, no timeline).
class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.item});
  final InventoryItem item;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> with AutomaticKeepAliveClientMixin {
  List<SerialHistoryEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await InventoryService.instance.history(widget.item.id);
      if (mounted) setState(() { _entries = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return Padding(padding: const EdgeInsets.all(24), child: shimmerList(count: 6));
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if ((_entries ?? []).isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.history, size: 40, color: context.pal.textDim),
          const SizedBox(height: 12),
          Text('No individually tracked units for this item', style: AppTheme.bodySub),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _entries!.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _HistoryCard(entry: _entries![i]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});
  final SerialHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.qr_code_2, size: 16, color: context.pal.textDim),
          const SizedBox(width: 8),
          Text(entry.serialNumber, style: AppTheme.monoSm.copyWith(
              fontSize: 13, fontWeight: FontWeight.w600, color: context.pal.text)),
        ]),
        const SizedBox(height: 10),
        _HistoryStep(
          icon: Symbols.inventory_2,
          label: 'Received',
          done: true,
          detail: entry.receivedAt != null ? formatDate(entry.receivedAt!) : '—',
        ),
        _HistoryStep(
          icon: Symbols.sell,
          label: 'Sold / Issued',
          done: entry.sold != null,
          detail: entry.sold != null
              ? [entry.sold!.salesOrderNumber, if (entry.sold!.deliveredAt != null) formatDate(entry.sold!.deliveredAt!)]
                  .whereType<String>().join(' · ')
              : 'Still in stock',
          isLast: true,
        ),
      ]),
    );
  }
}

class _HistoryStep extends StatelessWidget {
  const _HistoryStep({
    required this.icon, required this.label, required this.done,
    required this.detail, this.isLast = false,
  });
  final IconData icon;
  final String label;
  final bool done;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.teal : context.pal.textDim;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(done ? Symbols.check_circle : icon, size: 15, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 78,
          child: Text(label, style: AppTheme.bodySm.copyWith(
              fontSize: 11.5, fontWeight: FontWeight.w600,
              color: done ? context.pal.text : context.pal.textMute)),
        ),
        Expanded(child: Text(detail, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
      ]),
    );
  }
}

// ── Barcode tab ────────────────────────────────────────────────────────────────

class _BarcodeTab extends StatelessWidget {
  const _BarcodeTab({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final barcode = item.barcode;
    if (barcode == null || barcode.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.barcode_reader, size: 48, color: context.pal.textDim),
          const SizedBox(height: 16),
          Text('No barcode registered', style: AppTheme.bodyStrong),
          const SizedBox(height: 6),
          Text('Edit this item to add a barcode or part number.',
              style: AppTheme.bodySub.copyWith(fontSize: 12)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(children: [
            // Item name header
            Text(item.name,
                style: AppTheme.bodyStrong.copyWith(fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(item.sku,
                style: AppTheme.monoXs.copyWith(color: context.pal.textMute),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),

            // Barcode visual
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.pal.border),
              ),
              child: Column(children: [
                CustomPaint(
                  size: const Size(double.infinity, 80),
                  painter: _BarcodePainter(barcode),
                ),
                const SizedBox(height: 12),
                Text(barcode,
                    style: AppTheme.monoSm.copyWith(
                      color: Colors.black87,
                      fontSize: 13,
                      letterSpacing: 3,
                    ),
                    textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 24),

            // Copy button
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: barcode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Barcode copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  border: Border.all(color: context.pal.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Symbols.content_copy, size: 16, color: context.pal.textMute),
                  const SizedBox(width: 8),
                  Text('Copy barcode', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  const _BarcodePainter(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Generate a deterministic bar pattern from the code string
    final bytes = code.codeUnits;
    final totalBars = 60;
    double x = 0;
    final unitW = size.width / totalBars;

    for (int i = 0; i < totalBars; i++) {
      final byte = bytes[i % bytes.length];
      final isBar = (byte + i) % 3 != 0;
      final thick = (byte + i) % 5 == 0;
      final w = thick ? unitW * 2 : unitW;
      if (isBar) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w - 0.8, size.height), paint);
      }
      x += w;
      if (x >= size.width) break;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.code != code;
}
