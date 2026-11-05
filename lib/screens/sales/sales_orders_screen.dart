import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, hasSalesApprovalAuthority;
import '../../models/sales_order.dart';
import '../../services/invoice_service.dart';
import '../../services/sales_order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/sliver_table.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Color _statusColor(String status) => switch (status) {
  'pending'    => AppColors.textDim,
  'confirmed'  => AppColors.blue,
  'delivering' => AppColors.amber,
  'delivered'  => AppColors.teal,
  'cancelled'  => AppColors.coral,
  _            => AppColors.textDim,
};

String _fmtAmount(int tzs) {
  if (tzs >= 1000000) return 'TSh ${(tzs / 1e6).toStringAsFixed(1)}M';
  if (tzs >= 1000)    return 'TSh ${(tzs / 1000).toStringAsFixed(0)}K';
  return 'TSh $tzs';
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  List<SalesOrder> _all      = [];
  List<SalesOrder> _filtered = [];
  bool             _loading  = true;
  String?          _error;
  String?          _statusFilter;
  Period           _period = Period.defaultPeriod;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known order list immediately on
    // a return visit instead of blanking to a spinner, then quietly refresh
    // in the background — see MachineService for the full reasoning.
    final cached = SalesOrderService.cachedDefaultList;
    if (cached != null) {
      _all = cached;
      _loading = false;
      _applyFilter();
    }
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_all.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await SalesOrderService.instance.list(period: _period);
      if (!mounted) return;
      setState(() { _all = data; _loading = false; });
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((so) {
        final matchStatus = _statusFilter == null || so.status == _statusFilter;
        final matchSearch = q.isEmpty ||
            so.clientName.toLowerCase().contains(q) ||
            so.orderNumber.toLowerCase().contains(q);
        return matchStatus && matchSearch;
      }).toList();
    });
  }

  Future<void> _showDetailModal(SalesOrder so) async {
    SalesOrder full;
    try {
      full = so.items.isEmpty ? await SalesOrderService.instance.get(so.id) : so;
    } catch (e) {
      if (mounted) showErrorToast(context, e);
      return;
    }
    if (!mounted) return;
    final reload = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _SalesOrderDetailDialog(so: full),
    );
    if (reload == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      final phone = isPhoneWidth(cst.maxWidth);
      final cancelled = _all.where((o) => o.status == 'cancelled');
      final booked = _all.where((o) => o.status != 'cancelled').fold<int>(0, (s, o) => s + o.totalAmount);
      final cancelledTotal = cancelled.fold<int>(0, (s, o) => s + o.totalAmount);
      final chips = _StatusChips(
        current: _statusFilter,
        counts: {for (final s in ['pending', 'confirmed', 'delivering', 'delivered', 'cancelled']) s: _all.where((o) => o.status == s).length},
        total: _all.length,
        onChanged: (s) { setState(() { _statusFilter = s; _applyFilter(); }); },
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) PhonePageHeader(
          title: 'Sales Orders',
          subtitle: '${_all.length} orders · ${tshFromDouble(booked)} booked',
          primary: PageAction(label: 'New order', shortLabel: 'New', icon: Symbols.add,
              onPressed: () => widget.onNavigateTo?.call('sales_quotations')),
          search: SearchField(hint: 'Client or SO number…', controller: _searchCtrl),
          filters: [PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); })],
          bottom: SingleChildScrollView(scrollDirection: Axis.horizontal, child: chips),
        ) else Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sales Orders', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('${_all.length} orders · ${tshFromDouble(booked)} booked · ${_all.where((o) => o.status == 'pending').length} pending confirmation'
                  '${cancelled.isNotEmpty ? ' · ${cancelled.length} cancelled' : ''}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            const SizedBox(width: 12),
            SearchField(width: 240, hint: 'Client or SO number…', controller: _searchCtrl),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => widget.onNavigateTo?.call('sales_quotations'), icon: const Icon(Symbols.add, size: 16), label: const Text('New order')),
          ]),
        ),
        if (!phone) ...[
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(children: [
            chips,
            const Spacer(),
            Text('Showing ${_filtered.length} of ${_all.length}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            const SizedBox(width: 12),
            PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
          ]),
        ),
        ],
        const SizedBox(height: 12),
        // Everything below the filters scrolls as one; the table header pins.
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              // A background refresh failing while stale-but-valid cached
              // data is already showing shouldn't blow that away.
              : _error != null && _all.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load)
                  : Builder(builder: (context) {
                      final table = _OrderTable(items: _filtered, onSelect: _showDetailModal, booked: booked, cancelledTotal: cancelledTotal, cancelledCount: cancelled.length);
                      return CustomScrollView(slivers: phone ? table.phoneSlivers(context) : table.slivers(context, pad: pad));
                    }),
        ),
      ]);
    });
  }
}

// ── Status chips ───────────────────────────────────────────────────────────────

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.current, required this.counts, required this.total, required this.onChanged});
  final String? current;
  final Map<String, int> counts;
  final int total;
  final ValueChanged<String?> onChanged;

  static const _statuses = [
    ('pending', 'Pending'), ('confirmed', 'Confirmed'),
    ('delivering', 'Delivering'), ('delivered', 'Delivered'), ('cancelled', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    _chip(context, null, 'All', total),
    ...(_statuses.map((s) => _chip(context, s.$1, s.$2, counts[s.$1] ?? 0))),
  ]);

  Widget _chip(BuildContext ctx, String? value, String label, int count) {
    final active = current == value;
    return GestureDetector(
      onTap: () => onChanged(active ? null : value),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.green.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? AppColors.green.withValues(alpha: 0.5) : ctx.pal.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12, color: active ? AppColors.green : ctx.pal.textMute)),
          const SizedBox(width: 6),
          Text('$count', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: active ? AppColors.green : ctx.pal.textDim)),
        ]),
      ),
    );
  }
}

// ── Order table ────────────────────────────────────────────────────────────────

const _fulfilmentLabels = ['Raised', 'Confirmed', 'Delivering', 'Delivered'];

int _fulfilmentStep(SalesOrder so) => switch (so.status) {
  'pending' => 1, 'confirmed' => 2, 'delivering' => 3, 'delivered' => 4, _ => 0,
};

class _OrderTable {
  const _OrderTable({required this.items, required this.onSelect, required this.booked, required this.cancelledTotal, required this.cancelledCount});
  final List<SalesOrder> items;
  final ValueChanged<SalesOrder> onSelect;
  final int booked;
  final int cancelledTotal;
  final int cancelledCount;

  // Slivers for the page's single scroll view: pinned column header, lazy
  // rows, footer at the end (see sliverTable).
  /// Phone list: a card per order with its fulfilment step.
  List<Widget> phoneSlivers(BuildContext context) {
    if (items.isEmpty) {
      return [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('No sales orders found', style: AppTheme.bodySub))))];
    }
    return [
      SliverList(delegate: SliverChildBuilderDelegate((context, i) {
        final so = items[i];
        final step = _fulfilmentStep(so);
        return PhoneRecordCard(
          title: so.clientName,
          subtitle: '${so.orderNumber} · ${so.quotationNumber != null ? 'from ${so.quotationNumber}' : 'direct order'}',
          badge: _StatusBadge(so.status, so.statusLabel),
          lead: so.needsApproval ? Icon(Symbols.hourglass_top, size: 18, color: AppColors.amber) : null,
          meta: [
            so.createdAt.length >= 10 ? so.createdAt.substring(0, 10) : so.createdAt,
            if (step > 0) '${_fulfilmentLabels[step - 1]} ($step/4)',
          ],
          amount: tshFromDouble(so.totalAmount),
          onTap: () => onSelect(so),
        );
      }, childCount: items.length)),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Text('${tshFromDouble(booked)} booked'
            '${cancelledCount > 0 ? ' · $cancelledCount cancelled (${tshFromDouble(cancelledTotal)})' : ''}',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
      )),
    ];
  }

  List<Widget> slivers(BuildContext context, {required double pad}) {
    return sliverTable(
      context,
      pad: pad,
      headerHeight: 38,
      header: Container(
          height: 38, padding: const EdgeInsets.symmetric(horizontal: 16),
          color: context.pal.surface2,
          child: Row(children: [
            SizedBox(width: 122, child: Text('SO NUMBER', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 3, child: Text('CLIENT', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('FULFILMENT', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('AMOUNT', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('STATUS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('CREATED', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(child: Text('INVOICE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
          ]),
        ),
      itemCount: items.length,
      emptyText: 'No sales orders found',
      itemBuilder: (context, i) {
                  final so = items[i];
                  final color = _statusColor(so.status);
                  final step = _fulfilmentStep(so);
                  final cancelled = so.status == 'cancelled';
                  return GestureDetector(
                    onTap: () => onSelect(so),
                    child: Container(
                      height: 52, padding: const EdgeInsets.symmetric(horizontal: 16),
                      color: cancelled ? Colors.white.withValues(alpha: 0.01) : null,
                      child: Row(children: [
                        SizedBox(width: 122, child: Row(children: [
                          Container(width: 3, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 9),
                          Expanded(child: Text(so.orderNumber, style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.textMute))),
                        ])),
                        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            if (so.needsApproval) ...[Icon(Symbols.hourglass_top, size: 12, color: AppColors.amber), const SizedBox(width: 4)],
                            Flexible(child: Text(so.clientName, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                          Text(so.quotationNumber != null ? 'From ${so.quotationNumber}' : 'Direct order', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
                        ])),
                        Expanded(flex: 2, child: cancelled
                            ? Text('Cancelled by client', style: AppTheme.bodySub.copyWith(fontSize: 10.5))
                            : Row(children: [
                                ...List.generate(4, (n) => Expanded(child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                  child: Container(height: 4, decoration: BoxDecoration(color: n < step ? color : context.pal.surface3, borderRadius: BorderRadius.circular(2))),
                                ))),
                                const SizedBox(width: 8),
                                SizedBox(width: 66, child: Text(_fulfilmentLabels[step - 1], style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: color))),
                              ])),
                        Expanded(child: Text(tshFromDouble(so.totalAmount), textAlign: TextAlign.right, style: AppTheme.monoSm.copyWith(fontSize: 12.5, color: cancelled ? context.pal.textDim : null))),
                        Expanded(child: Align(alignment: Alignment.centerRight, child: _StatusBadge(so.status, so.statusLabel))),
                        Expanded(child: Text(so.createdAt.length >= 10 ? so.createdAt.substring(0, 10) : so.createdAt, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textDim))),
                        Expanded(child: Text('—', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textDim))),
                      ]),
                    ),
                  );
      },
      footer: Container(
          height: 46, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: context.pal.surface2, border: Border(top: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            SizedBox(width: 122, child: Text('BOOKED', style: AppTheme.labelCaps.copyWith(fontSize: 10))),
            Expanded(flex: 3, child: Text(cancelledCount > 0 ? 'Excludes $cancelledCount cancelled order${cancelledCount == 1 ? '' : 's'} of ${tshFromDouble(cancelledTotal)}' : '', style: AppTheme.bodySub.copyWith(fontSize: 11))),
            const Expanded(flex: 2, child: SizedBox()),
            Expanded(child: Text(tshFromDouble(booked), textAlign: TextAlign.right, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
            const Expanded(child: SizedBox()), const Expanded(child: SizedBox()), const Expanded(child: SizedBox()),
          ]),
        ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status, this.label);
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Sales order detail dialog ──────────────────────────────────────────────────

class _SalesOrderDetailDialog extends StatefulWidget {
  const _SalesOrderDetailDialog({required this.so});
  final SalesOrder so;

  @override
  State<_SalesOrderDetailDialog> createState() =>
      _SalesOrderDetailDialogState();
}

class _SalesOrderDetailDialogState extends State<_SalesOrderDetailDialog> {
  bool _acting = false;

  Future<void> _act(Future<dynamic> Function() fn) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await fn();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _acting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _deliver() async {
    final machinesCreated = await showDialog<int>(
      context: context,
      builder: (_) => _DeliverModal(order: widget.so),
    );
    if (machinesCreated == null || !mounted) return;
    if (machinesCreated > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Delivery recorded — $machinesCreated new machine${machinesCreated == 1 ? '' : 's'} registered for Service'),
      ));
    }
    Navigator.pop(context, true);
  }

  Future<void> _generateInvoice() async {
    setState(() => _acting = true);
    try {
      await InvoiceService.instance.fromSalesOrder(widget.so.id);
      if (mounted) Navigator.pop(context, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Invoice created — view it under Sales → Invoices')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _acting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final so = widget.so;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 560,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.pal.borderStrong),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55000000), blurRadius: 60, offset: Offset(0, 20))
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              Icon(Symbols.shopping_cart, size: 18, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(so.orderNumber,
                      style: AppTheme.pageTitle.copyWith(fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(children: [
                    _StatusBadge(so.status, so.statusLabel),
                    if (so.quotationNumber != null) ...[
                      const SizedBox(width: 8),
                      Icon(Symbols.request_quote,
                          size: 13, color: context.pal.textDim),
                      const SizedBox(width: 4),
                      Text('From ${so.quotationNumber}',
                          style:
                              AppTheme.bodySub.copyWith(fontSize: 11)),
                    ],
                  ]),
                ]),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: context.pal.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Symbols.close,
                      size: 15, color: context.pal.textDim),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.pal.border),

          // ── Scrollable body ──
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (so.approvalStatus != 'not_required')
                  _ApprovalBanner(
                    status: so.approvalStatus,
                    reason: so.approvalStatus == 'rejected' ? so.rejectionReason : so.approvalReason,
                    approvedByName: so.approvedByName,
                    onApprove: () => _act(() => SalesOrderService.instance.approve(so.id)),
                    onReject: () => _act(() => SalesOrderService.instance.rejectApproval(so.id)),
                  ),
                // Info 2-col grid
                Wrap(children: [
                  _infoTile('Client', so.clientName),
                  if (so.clientContact != null)
                    _infoTile('Contact', so.clientContact!),
                  if (so.locationName != null)
                    _infoTile('Ship From', so.locationName!),
                  if (so.expectedDeliveryDate != null)
                    _infoTile('Expected Delivery', so.expectedDeliveryDate!),
                  _infoTile('Currency', so.currency),
                  if (so.createdByName != null)
                    _infoTile('Created By', so.createdByName!),
                  if (so.confirmedByName != null)
                    _infoTile('Confirmed By', so.confirmedByName!),
                  if (so.deliveredByName != null)
                    _infoTile('Delivered By', so.deliveredByName!),
                  if (so.commissionAmount != null)
                    _infoTile('Commission',
                        '${_fmtAmount(so.commissionAmount!)} (${so.commissionPercent?.toStringAsFixed(1)}% — ${so.commissionAgentName ?? '—'})'),
                ]),
                const SizedBox(height: 16),

                // Financials
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.pal.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.pal.border),
                  ),
                  child: Column(children: [
                    _finRow('Subtotal', so.subtotal),
                    if (so.discountAmount > 0)
                      _finRow('Discount', -so.discountAmount, isDiscount: true),
                    if (so.taxAmount > 0) _finRow('Tax', so.taxAmount),
                    const Divider(height: 16),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: AppTheme.bodyStrong),
                          Text(_fmtAmount(so.totalAmount),
                              style: AppTheme.bodyStrong.copyWith(
                                  color: AppColors.amber, fontSize: 15)),
                        ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // Line items
                if (so.items.isNotEmpty) ...[
                  Text('Line Items', style: AppTheme.bodyStrong),
                  const SizedBox(height: 8),
                  ...so.items.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.pal.surface2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.pal.border),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item.description,
                                  style: AppTheme.bodySm.copyWith(
                                      fontWeight: FontWeight.w500)),
                              if (item.itemSku != null)
                                Text(item.itemSku!,
                                    style: AppTheme.monoXs.copyWith(
                                        color: context.pal.textDim)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                            Text(
                                '${item.quantityDelivered} / ${item.quantityOrdered} ${item.unitOfMeasure}',
                                style:
                                    AppTheme.bodySub.copyWith(fontSize: 11)),
                            if (item.isFullyDelivered)
                              Text('Delivered',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.teal))
                            else
                              Text('${item.quantityRemaining} remaining',
                                  style: AppTheme.bodySub.copyWith(
                                      fontSize: 10, color: AppColors.amber)),
                            if (item.quantityInvoiced < item.quantityDelivered)
                              Text('${item.quantityDelivered - item.quantityInvoiced} to invoice',
                                  style: AppTheme.bodySub.copyWith(
                                      fontSize: 9.5, color: AppColors.violet))
                            else if (item.quantityInvoiced > 0)
                              Text('Invoiced',
                                  style: AppTheme.bodySub.copyWith(
                                      fontSize: 9.5, color: context.pal.textDim)),
                          ]),
                          const SizedBox(width: 12),
                          Text(_fmtAmount(item.totalPrice),
                              style: AppTheme.bodySm.copyWith(
                                  color: AppColors.amber,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      )),
                ],

                if (so.notes != null) ...[
                  const SizedBox(height: 16),
                  Text('Notes', style: AppTheme.bodyStrong),
                  const SizedBox(height: 4),
                  Text(so.notes!, style: AppTheme.bodySub),
                ],
              ]),
            ),
          ),

          // ── Action footer ──
          if (so.canConfirm || so.canDeliver ||
              so.status == 'delivered' || so.canCancel) ...[
            Divider(height: 1, color: context.pal.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _acting
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      if (so.canConfirm)
                        AppButton(
                          label: 'Confirm Order',
                          icon: Symbols.check_circle,
                          variant: BtnVariant.primary,
                          onPressed: () => _act(
                              () => SalesOrderService.instance.confirm(so.id)),
                        ),
                      if (so.canDeliver)
                        AppButton(
                          label: 'Record Delivery',
                          icon: Symbols.local_shipping,
                          variant: BtnVariant.primary,
                          onPressed: _deliver,
                        ),
                      if (so.status == 'delivered' || so.status == 'delivering')
                        AppButton(
                          label: 'Generate Invoice',
                          icon: Symbols.receipt_long,
                          variant: BtnVariant.primary,
                          onPressed: _generateInvoice,
                        ),
                      if (so.canCancel)
                        AppButton(
                          label: 'Cancel Order',
                          icon: Symbols.cancel,
                          variant: BtnVariant.ghost,
                          onPressed: () => _act(
                              () => SalesOrderService.instance.cancel(so.id)),
                        ),
                    ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _infoTile(String label, String value) => SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: AppTheme.labelCaps),
            const SizedBox(height: 2),
            Text(value,
                style: AppTheme.bodySm, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _finRow(String label, int amount, {bool isDiscount = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: AppTheme.bodySub),
          Text(
            isDiscount ? '-${_fmtAmount(-amount)}' : _fmtAmount(amount),
            style: AppTheme.bodySub
                .copyWith(color: isDiscount ? AppColors.coral : null),
          ),
        ]),
      );
}

// ── Approval banner ──────────────────────────────────────────────────────────

class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({
    required this.status, required this.reason, required this.approvedByName,
    required this.onApprove, required this.onReject,
  });
  final String status;
  final String? reason;
  final String? approvedByName;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'pending'  => AppColors.amber,
      'approved' => AppColors.teal,
      'rejected' => AppColors.coral,
      _          => context.pal.textDim,
    };
    final label = switch (status) {
      'pending'  => 'Awaiting Manager Approval',
      'approved' => 'Approved${approvedByName != null ? ' by $approvedByName' : ''}',
      'rejected' => 'Rejected${approvedByName != null ? ' by $approvedByName' : ''}',
      _          => status,
    };
    final isAdmin = hasSalesApprovalAuthority(userRoleNotifier.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(status == 'pending' ? Symbols.hourglass_top
              : status == 'approved' ? Symbols.check_circle : Symbols.cancel,
              size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.bodyStrong.copyWith(color: color, fontSize: 12.5)),
        ]),
        if (reason != null) ...[
          const SizedBox(height: 4),
          Text(reason!, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
        ],
        if (status == 'pending' && isAdmin) ...[
          const SizedBox(height: 10),
          Row(children: [
            AppButton(label: 'Approve', icon: Symbols.check, variant: BtnVariant.primary, onPressed: onApprove),
            const SizedBox(width: 8),
            AppButton(label: 'Reject', icon: Symbols.close, variant: BtnVariant.ghost, onPressed: onReject),
          ]),
        ],
      ]),
    );
  }
}

// ── Delivery modal ─────────────────────────────────────────────────────────────

class _DeliverModal extends StatefulWidget {
  const _DeliverModal({required this.order});
  final SalesOrder order;

  @override
  State<_DeliverModal> createState() => _DeliverModalState();
}

class _DeliverModalState extends State<_DeliverModal> {
  late final List<TextEditingController> _qtyCtrls;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrls = widget.order.items.map((item) =>
      TextEditingController(text: item.quantityRemaining.toString())
    ).toList();
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls) { c.dispose(); }
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final (_, machinesCreated) = await SalesOrderService.instance.deliver(
        widget.order.id,
        items: widget.order.items.asMap().entries.map((e) => {
          'sales_order_item_id': e.value.id,
          'quantity_delivered':  int.tryParse(_qtyCtrls[e.key].text) ?? 0,
        }).where((m) => (m['quantity_delivered'] as int) > 0).toList(),
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );
      if (mounted) Navigator.pop(context, machinesCreated);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pal.surface1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Container(
      width: 520,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Symbols.local_shipping, size: 18, color: AppColors.teal),
          const SizedBox(width: 10),
          Expanded(child: Text('Record Delivery — ${widget.order.orderNumber}',
              style: AppTheme.bodyStrong)),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Symbols.close, size: 18, color: context.pal.textDim),
          ),
        ]),
        const SizedBox(height: 20),

        // Per-item qty inputs
        ...widget.order.items.asMap().entries.map((e) {
          final item = e.value;
          if (item.isFullyDelivered) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.pal.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.pal.border),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.description,
                    style: AppTheme.bodySm.copyWith(fontWeight: FontWeight.w500)),
                Text('Remaining: ${item.quantityRemaining} ${item.unitOfMeasure}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11)),
              ])),
              SizedBox(
                width: 80,
                child: CellField(controller: _qtyCtrls[e.key], keyboardType: TextInputType.number),
              ),
            ]),
          );
        }),

        // Notes
        LabeledTextField(label: '', controller: _notesCtrl, maxLines: 3, hint: 'Delivery notes (optional)…'),
        const SizedBox(height: 16),

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
                : Text('Confirm Delivery', style: AppTheme.bodyStrong.copyWith(
                    color: const Color(0xFF06120F), fontSize: 13)))),
          )),
        ]),
      ]),
    ),
  );
}
