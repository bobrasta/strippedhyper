import '../../models/creditor.dart' show money;
import '../../widgets/finance/connections_button.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/purchase_order.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../services/supplier_service.dart';
import '../../services/location_service.dart';
import '../../services/inventory_service.dart';
import '../../models/supplier.dart';
import '../../models/location.dart';
import '../../models/inventory_item.dart';
import '../../services/purchase_order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/shimmer_box.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';

/// Colour of an order's status pill — shared with Purchases → List purchases.
Color purchaseStatusColor(String status) => _PurchaseOrdersScreenState._statusColor(status);

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  String? _statusFilter;
  PurchaseOrder? _selected;
  bool _showGrn = false;

  List<PurchaseOrder> _orders = [];
  bool   _loading = true;
  String? _error;
  Period _period = Period.defaultPeriod;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known list immediately (if any)
    // instead of blanking to a spinner on every navigation — see
    // MachineService for the full reasoning.
    final cached = PurchaseOrderService.cachedDefaultList;
    if (cached != null) { _orders = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_orders.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await PurchaseOrderService.instance.list(status: _statusFilter, period: _period);
      if (mounted) setState(() { _orders = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _newOrder() async {
    final created = await showNewPurchaseOrder(context);
    if (created == null || !mounted) return;
    showSuccessToast(context, 'Purchase order ${created.poNumber} created as a draft.');
    _load();
    _loadDetail(created.id);
  }

  Future<void> _loadDetail(int id) async {
    // Show a cached full record instantly (if we have one) rather than
    // leaving the panel on the list row's summary fields until the fetch
    // resolves.
    final cached = PurchaseOrderService.cachedById[id];
    if (cached != null && mounted) setState(() => _selected = cached);
    try {
      final full = await PurchaseOrderService.instance.get(id);
      if (mounted) setState(() => _selected = full);
    } catch (_) {}
  }

  Future<void> _doAction(Future<PurchaseOrder> Function() fn, String msg) async {
    try {
      final updated = await fn();
      if (mounted) { setState(() { _selected = updated; _showGrn = false; }); _load(); }
      if (mounted) showSuccessToast(context, msg);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  static Color _statusColor(String s) => switch (s) {
    'draft'                      => AppColors.textDim,
    'pending_sales_manager'      => AppColors.amber,
    'pending_director_review'    => AppColors.amber,
    'pending_payment_initiation' => AppColors.amber,
    'pending_director_final'     => AppColors.amber,
    'approved'                   => AppColors.violet,
    'rejected'                   => AppColors.coral,
    'sent'                       => AppColors.blue,
    'acknowledged'               => AppColors.violet,
    'partially_received'         => AppColors.amber,
    'received'                   => AppColors.teal,
    'cancelled'                  => AppColors.coral,
    _                            => AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    const statuses = ['draft', 'sent', 'acknowledged', 'partially_received', 'received', 'cancelled'];
    const sLabels  = ['Draft', 'Sent', 'Acknowledged', 'Partial GRN', 'Received', 'Cancelled'];

    return LayoutBuilder(builder: (context, cst) {
    // Phones show the list, or one order in its place; back closes it.
    final phone       = isPhoneWidth(cst.maxWidth);
    final phoneDetail = phone && _selected != null;
    return PopScope(
      canPop: !phoneDetail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && phoneDetail) setState(() => _selected = null);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Header ──
      if (phoneDetail) const SizedBox.shrink()
      else if (phone) PhonePageHeader(
        title: 'Purchase Orders',
        subtitle: 'Track orders to suppliers',
        primary: PageAction(label: 'New Order', shortLabel: 'New', icon: Symbols.add, onPressed: _newOrder),
        filters: [
          PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
          _StatusChip(label: 'All', active: _statusFilter == null,
              onTap: () { setState(() => _statusFilter = null); _load(); }),
          for (final (i, st) in statuses.indexed)
            _StatusChip(label: sLabels[i], color: _statusColor(st), active: _statusFilter == st,
                onTap: () { setState(() => _statusFilter = _statusFilter == st ? null : st); _load(); }),
        ],
      ) else Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Purchase Orders', style: AppTheme.pageTitle),
            const SizedBox(height: 2),
            Text('Track orders to suppliers', style: AppTheme.bodySub),
          ]),
          const SizedBox(width: 20),
          Wrap(spacing: 6, children: [
            _StatusChip(label: 'All', active: _statusFilter == null,
                onTap: () { setState(() => _statusFilter = null); _load(); }),
            ...statuses.asMap().entries.map((e) => _StatusChip(
              label: sLabels[e.key], color: _statusColor(e.value),
              active: _statusFilter == e.value,
              onTap: () {
                setState(() => _statusFilter = _statusFilter == e.value ? null : e.value);
                _load();
              },
            )),
          ]),
          const Spacer(),
          PeriodSelector(value: _period, onChanged: (p) { setState(() => _period = p); _load(); }),
          const SizedBox(width: 8),
          AppButton(label: 'New Order', icon: Symbols.add, variant: BtnVariant.primary,
              onPressed: _newOrder),
        ]),
      ),
      Expanded(child: Stack(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // List
          if (!phoneDetail) Expanded(flex: 3, child: RefreshIndicator(
            onRefresh: _load,
            child: Column(children: [
              if (phone) const SizedBox(height: 10) else Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
                child: Row(children: [
                  _Th('PO Number', flex: 2), _Th('Supplier', flex: 3),
                  _Th('Status', flex: 2), _Th('Total', flex: 2), _Th('Date', flex: 2),
                ]),
              ),
              Expanded(child: _loading
                ? shimmerTable(count: 8, cols: 5)
                : _error != null && _orders.isEmpty
                  ? ErrorView(message: _error!, onRetry: _load, compact: true)
                  : _orders.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.receipt_long, size: 36, color: context.pal.textDim),
                        const SizedBox(height: 10),
                        Text('No purchase orders', style: AppTheme.bodySub),
                      ]))
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _orders.length,
                        itemBuilder: (_, i) {
                          final po = _orders[i];
                          if (phone) {
                            return PhoneRecordCard(
                              title: po.supplierName ?? '—',
                              subtitle: po.poNumber,
                              badge: PhonePill(po.statusLabel, _statusColor(po.status)),
                              meta: [formatDate(po.createdAt)],
                              amount: '${po.currency} ${po.totalAmount.toStringAsFixed(0)}',
                              onTap: () {
                                setState(() => _selected = po);
                                _loadDetail(po.id);
                              },
                            );
                          }
                          return _PORow(
                            po: po, selected: _selected?.id == po.id,
                            statusColor: _statusColor(po.status),
                            onTap: () {
                              setState(() => _selected = po);
                              _loadDetail(po.id);
                            },
                          );
                        },
                      )),
            ]),
          )),
          // Detail
          if (_selected != null) ...[
            if (!phone) Container(width: 1, color: context.pal.border),
            Expanded(flex: 2, child: _PODetailPanel(
              po: _selected!,
              statusColor: _statusColor(_selected!.status),
              onClose:  () => setState(() => _selected = null),
              onSubmitForApproval: () => _doAction(
                () => PurchaseOrderService.instance.submitForApproval(_selected!.id),
                'Submitted for approval'),
              onSend:   () => _doAction(
                () => PurchaseOrderService.instance.send(_selected!.id), 'PO sent to supplier'),
              onCancel: () => _doAction(
                () => PurchaseOrderService.instance.cancel(_selected!.id), 'PO cancelled'),
              onReceive: () => setState(() => _showGrn = true),
              onEdit: () async {
                final saved = await showNewPurchaseOrder(context, editing: _selected);
                if (saved != null && mounted) {
                  setState(() => _selected = saved);
                  _load();
                }
              },
            )),
          ],
        ]),
        // GRN modal overlay
        if (_showGrn && _selected != null)
          _GrnModal(
            po: _selected!,
            onClose: () => setState(() => _showGrn = false),
            onReceived: (data) => _doAction(
              () => PurchaseOrderService.instance.receive(_selected!.id, data),
              'Goods received — stock updated'),
          ),
      ])),
    ]));
    });
  }
}

// ── PO row ─────────────────────────────────────────────────────────────────────

class _PORow extends StatelessWidget {
  const _PORow({required this.po, required this.selected,
      required this.statusColor, required this.onTap});
  final PurchaseOrder po;
  final bool selected;
  final Color statusColor;
  final VoidCallback onTap;

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
        Expanded(flex: 2, child: Text(po.poNumber,
            style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 12))),
        Expanded(flex: 3, child: Text(po.supplierName ?? '—',
            style: AppTheme.bodyStrong.copyWith(fontSize: 13), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(po.statusLabel, style: AppTheme.monoXs.copyWith(
              color: statusColor, fontSize: 11), overflow: TextOverflow.ellipsis),
        ))),
        Expanded(flex: 2, child: Text('${po.currency} ${po.totalAmount.toStringAsFixed(0)}',
            style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
        Expanded(flex: 2, child: Text(formatDate(po.createdAt),
            style: AppTheme.bodySub.copyWith(fontSize: 12))),
      ]),
    ),
  );
}

// ── PO detail panel ────────────────────────────────────────────────────────────

class _PODetailPanel extends StatelessWidget {
  const _PODetailPanel({
    required this.po, required this.statusColor, required this.onClose,
    this.onSubmitForApproval, this.onSend, this.onCancel, this.onReceive, this.onEdit,
  });
  final PurchaseOrder po;
  final Color statusColor;
  final VoidCallback onClose;
  final VoidCallback? onSubmitForApproval, onSend, onCancel, onReceive, onEdit;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(po.poNumber,
            style: AppTheme.monoXs.copyWith(color: AppColors.teal, fontSize: 13))),
        ConnectionsButton(type: 'purchase_order', id: po.id, compact: true),
        const SizedBox(width: 4),
        GestureDetector(onTap: onClose,
            child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Text(po.statusLabel, style: AppTheme.bodyStrong.copyWith(
            color: statusColor, fontSize: 12.5)),
      ),
      const SizedBox(height: 14),
      if (po.supplierName != null) _Row('Supplier', po.supplierName!),
      _Row('Currency', po.currency),
      _Row('Total', '${po.currency} ${po.totalAmount.toStringAsFixed(2)}'),
      if (po.returnedAmount > 0) _Row('Returned', '${po.currency} ${po.returnedAmount.toStringAsFixed(0)} sent back'),
      if (po.orderedByName != null) _Row('Ordered By', po.orderedByName!),
      if (po.expectedDeliveryDate != null)
        _Row('Expected', formatDate(po.expectedDeliveryDate!)),
      if (po.sentAt != null) _Row('Sent At', formatDate(po.sentAt!)),
      _Row('Created', formatDate(po.createdAt)),
      if (po.salesApprovedByName != null) _Row('Sales Approved By', po.salesApprovedByName!),
      if (po.directorReviewedByName != null) _Row('Director Reviewed By', po.directorReviewedByName!),
      if (po.paymentInitiatedByName != null) _Row('Payment Initiated By', po.paymentInitiatedByName!),
      if (po.directorApprovedByName != null) _Row('Final Approval By', po.directorApprovedByName!),
      if (po.rejectedByName != null) _Row('Rejected By', po.rejectedByName!),
      if (po.rejectionReason != null) _Row('Rejection Reason', po.rejectionReason!),
      // How it's paid: on credit, or each payment and the account it left.
      _Row('Payment', po.onCredit && po.payments.isEmpty
          ? 'On credit from ${po.supplierName ?? 'the supplier'}'
          : '${po.paymentStatus[0].toUpperCase()}${po.paymentStatus.substring(1)} · ${po.currency} ${po.amountPaid.toStringAsFixed(0)} paid'),
      for (final p in po.payments)
        _Row(p['payment_number'] as String? ?? 'Payment',
            '${money(num.tryParse('${p['amount']}') ?? 0, '${p['currency']}')} · '
            '${(p['paid_from'] as Map?)?['name'] ?? 'bank'} · '
            '${switch (p['status']) { 'paid' => 'paid', 'rejected' => 'rejected', _ => 'awaiting Director' }}'),
      for (final b in po.invoices)
        _Row('Supplier invoice', '${b['supplier_reference'] ?? b['bill_number']} · ${b['currency']} ${b['total']} · ${b['status']}'),
      if (po.notes != null) ...[
        const SizedBox(height: 10),
        Text(po.notes!, style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
      ],
      if (po.items.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Items (${po.items.length})', style: AppTheme.cardTitle.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        ...po.items.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.pal.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.itemName ?? '—',
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
              Text('${item.currency} ${_costInput(item.unitCost)} each',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Text('Ordered: ', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              Text('${item.quantityOrdered}', style: AppTheme.bodyStrong.copyWith(fontSize: 12)),
              const SizedBox(width: 12),
              Text('Received: ', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              Text('${item.quantityReceived}',
                  style: AppTheme.bodyStrong.copyWith(
                      fontSize: 12,
                      color: item.isFullyReceived ? AppColors.teal : null)),
              if (item.quantityReturned > 0) ...[
                const SizedBox(width: 12),
                Text('Returned: ', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                Text('${item.quantityReturned}', style: AppTheme.bodyStrong.copyWith(fontSize: 12, color: AppColors.coral)),
              ],
            ]),
          ]),
        )),
      ],
      const SizedBox(height: 20),
      // Action buttons
      if (onEdit != null && const {'draft', 'rejected'}.contains(po.status)) ...[
        _ActionBtn(label: po.status == 'rejected' ? 'Edit and fix' : 'Edit order', color: AppColors.blue,
            icon: Symbols.edit, onTap: onEdit),
        const SizedBox(height: 8),
      ],
      if (po.status == 'draft') ...[
        _ActionBtn(label: 'Submit for Approval', color: AppColors.blue,
            icon: Symbols.send, onTap: onSubmitForApproval),
        const SizedBox(height: 8),
      ],
      if (const {
        'pending_sales_manager', 'pending_director_review',
        'pending_payment_initiation', 'pending_director_final',
      }.contains(po.status)) ...[
        Text('Review this order from the Approvals screen — the right stage owner needs to act on it there.',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
      ],
      if (po.status == 'approved')
        _ActionBtn(label: 'Send to Supplier', color: AppColors.blue,
            icon: Symbols.send, onTap: onSend),
      if (onReceive != null && ['sent', 'acknowledged', 'partially_received'].contains(po.status)) ...[
        _ActionBtn(label: 'Receive Goods (GRN)', color: AppColors.teal,
            icon: Symbols.move_to_inbox, onTap: onReceive),
        const SizedBox(height: 8),
      ],
      // The order on the Hypermed letterhead — to send the supplier or file.
      const SizedBox(height: 4),
      _ActionBtn(label: 'Purchase order PDF', color: AppColors.blue, icon: Symbols.picture_as_pdf,
          onTap: () => downloadPdf(context, () => PurchaseOrderService.instance.pdfBytes(po.id), '${po.poNumber}.pdf')),
      if (onCancel != null && !['received', 'cancelled'].contains(po.status)) ...[
        const SizedBox(height: 8),
        _ActionBtn(label: 'Cancel Order', color: AppColors.coral,
            icon: Symbols.cancel, onTap: onCancel),
      ],
    ]),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
      Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, required this.icon, this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.bodyStrong.copyWith(color: color, fontSize: 13)),
        ]),
      ),
    ),
  );
}

// ── GRN modal ─────────────────────────────────────────────────────────────────

class _GrnModal extends StatefulWidget {
  const _GrnModal({required this.po, required this.onClose, required this.onReceived});
  final PurchaseOrder po;
  final VoidCallback onClose;
  final ValueChanged<Map<String, dynamic>> onReceived;

  @override
  State<_GrnModal> createState() => _GrnModalState();
}

class _GrnModalState extends State<_GrnModal> {
  late final List<TextEditingController> _qtyCtrl;
  // Lot number + expiry per line: a lot number makes the received stock
  // pickable by lot in the sale / invoice product search.
  late final List<TextEditingController> _lotCtrl;
  late final List<DateTime?> _expiry;
  final _rateCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = widget.po.items.map((item) =>
      TextEditingController(text: '${item.quantityOrdered - item.quantityReceived}')
    ).toList();
    _lotCtrl = widget.po.items.map((_) => TextEditingController()).toList();
    _expiry = List<DateTime?>.filled(widget.po.items.length, null);
  }

  @override
  void dispose() {
    for (final c in _qtyCtrl) { c.dispose(); }
    for (final c in _lotCtrl) { c.dispose(); }
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      final items = widget.po.items.asMap().entries.map((e) => {
        'purchase_order_item_id': e.value.id,
        'quantity_received': int.tryParse(_qtyCtrl[e.key].text) ?? 0,
        if (_lotCtrl[e.key].text.trim().isNotEmpty) 'batch_number': _lotCtrl[e.key].text.trim(),
        if (_expiry[e.key] != null)
          'expiry_date': _expiry[e.key]!.toIso8601String().substring(0, 10),
      }).where((i) => (i['quantity_received'] as int) > 0).toList();

      if (items.isEmpty) {
        setState(() { _saving = false; _error = 'Enter at least one received quantity.'; });
        return;
      }

      final rate = double.tryParse(_rateCtrl.text.replaceAll(',', ''));
      widget.onReceived({'items': items, 'exchange_rate': ?rate});
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
          width: 500,
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          decoration: BoxDecoration(
            color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.move_to_inbox, size: 18, color: AppColors.teal),
                const SizedBox(width: 10),
                Expanded(child: Text('Goods Received — ${widget.po.poNumber}',
                    style: AppTheme.bodyStrong, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose,
                    child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(children: [
                if (widget.po.currency.toUpperCase() != 'TZS') ...[
                  LabeledTextField(label: 'Exchange rate for stock value (TZS per ${widget.po.currency})', controller: _rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      hint: 'Blank = the average rate this order was paid at'),
                  const SizedBox(height: 12),
                ],
                ...widget.po.items.asMap().entries.map((e) {
                  final item = e.value;
                  final remaining = item.quantityOrdered - item.quantityReceived;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.pal.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.itemName ?? '—', style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                          Text('Ordered: ${item.quantityOrdered}  ·  '
                              'Already received: ${item.quantityReceived}  ·  '
                              'Remaining: $remaining',
                              style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                        ])),
                        const SizedBox(width: 12),
                        SizedBox(width: 80, child: CellField(controller: _qtyCtrl[e.key], hint: 'Qty', keyboardType: TextInputType.number)),
                      ]),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: LabeledTextField(label: 'Lot number', controller: _lotCtrl[e.key], hint: 'Optional')),
                        const SizedBox(width: 10),
                        Expanded(child: LabeledDateField(
                          label: 'Expiry date', date: _expiry[e.key], placeholder: 'Optional',
                          onClear: () => setState(() => _expiry[e.key] = null),
                          onTap: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(context: context,
                                initialDate: _expiry[e.key] ?? DateTime(now.year + 1, now.month, now.day),
                                firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 15));
                            if (d != null) setState(() => _expiry[e.key] = d);
                          })),
                      ]),
                    ]),
                  );
                }),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ],
              ]),
            )),
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
                      : Text('Confirm Receipt', style: AppTheme.bodyStrong.copyWith(
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

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active, required this.onTap, this.color});
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

// ── Order detail as a dialog ─────────────────────────────────────────────────
// Purchases → List purchases opens an order here (View): the same panel as
// this screen's, with submit / send / cancel. Goods are received from
// Inventory → Purchase Orders (stores). Resolves true when the order changed.

Future<bool> showPurchaseOrderDetail(BuildContext context, int id, {PurchaseOrder? preview}) async {
  final changed = await showDialog<bool>(context: context, builder: (_) => _PODetailDialog(id: id, preview: preview));
  return changed == true;
}

class _PODetailDialog extends StatefulWidget {
  const _PODetailDialog({required this.id, this.preview});
  final int id;
  final PurchaseOrder? preview;
  @override
  State<_PODetailDialog> createState() => _PODetailDialogState();
}

class _PODetailDialogState extends State<_PODetailDialog> {
  PurchaseOrder? _po;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _po = PurchaseOrderService.cachedById[widget.id] ?? widget.preview;
    PurchaseOrderService.instance.get(widget.id).then((full) {
      if (mounted) setState(() => _po = full);
    }).catchError((Object e) {
      if (mounted) showErrorToast(context, e);
    });
  }

  Future<void> _act(Future<PurchaseOrder> Function() fn, String msg) async {
    try {
      final updated = await fn();
      if (!mounted) return;
      setState(() { _po = updated; _changed = true; });
      showSuccessToast(context, msg);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final po = _po;
    // Every way out (close, Esc, a tap outside) reports whether it changed.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) Navigator.pop(context, _changed); },
      child: Dialog(
      backgroundColor: context.pal.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: po == null
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : _PODetailPanel(
                po: po,
                statusColor: _PurchaseOrdersScreenState._statusColor(po.status),
                onClose: () => Navigator.pop(context, _changed),
                onSubmitForApproval: () => _act(() => PurchaseOrderService.instance.submitForApproval(po.id), 'Submitted for approval'),
                onSend: () => _act(() => PurchaseOrderService.instance.send(po.id), 'PO sent to supplier'),
                onCancel: () => _act(() => PurchaseOrderService.instance.cancel(po.id), 'PO cancelled'),
                onEdit: () async {
                  final saved = await showNewPurchaseOrder(context, editing: po);
                  if (saved != null && mounted) setState(() { _po = saved; _changed = true; });
                },
              ),
      ),
    ));
  }
}

// ── New purchase order ────────────────────────────────────────────────────────
// Supplier + receiving location + lines (catalogue item, qty, unit cost).
// Saved as a draft; the approval chain starts from the PO detail panel.
// Also Purchases → Add purchase.

/// New order, or [editing] a draft / rejected one (same form, pre-filled).
Future<PurchaseOrder?> showNewPurchaseOrder(BuildContext context, {PurchaseOrder? editing}) =>
    showDialog<PurchaseOrder>(context: context, builder: (_) => _NewPurchaseOrderDialog(editing: editing));

/// A unit cost as typed: whole numbers plain, otherwise up to 4 decimals (0.115, 5.75).
String _costInput(double c) {
  if (c == c.roundToDouble()) return c.toStringAsFixed(0);
  var t = c.toStringAsFixed(4);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

class _PoLine {
  _PoLine(this.currency);
  InventoryItem? item;
  /// The unit cost's currency — each line has its own.
  String currency;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  int get quantity => int.tryParse(qty.text.trim()) ?? 0;
  // Cents allowed (USD 12.50).
  double get unitCost => double.tryParse(cost.text.replaceAll(',', '').trim()) ?? 0;
  void dispose() { qty.dispose(); cost.dispose(); }
}

class _NewPurchaseOrderDialog extends StatefulWidget {
  const _NewPurchaseOrderDialog({this.editing});
  final PurchaseOrder? editing;
  @override
  State<_NewPurchaseOrderDialog> createState() => _NewPurchaseOrderDialogState();
}

class _NewPurchaseOrderDialogState extends State<_NewPurchaseOrderDialog> {
  List<Supplier> _suppliers = SupplierService.cachedDefaultList ?? [];
  List<Location> _locations = LocationService.cachedDefaultList ?? [];
  List<InventoryItem> _items = InventoryService.cachedDefaultList ?? [];
  int? _supplierId;
  int? _locationId;
  DateTime? _expected;
  final _notes = TextEditingController();
  final List<_PoLine> _lines = [_PoLine('TZS')];
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final po = widget.editing;
    if (po != null) {
      _supplierId = po.supplierId;
      _locationId = po.locationId;
      _expected = po.expectedDeliveryDate;
      _notes.text = po.notes ?? '';
      _lines
        ..clear()
        ..addAll(po.items.map((it) {
          final l = _PoLine((it.currency.isNotEmpty ? it.currency : po.currency).toUpperCase());
          l.item = InventoryItem.fromJson({'id': it.inventoryItemId, 'sku': it.itemSku ?? '', 'name': it.itemName ?? ''});
          l.qty.text = '${it.quantityOrdered}';
          l.cost.text = _costInput(it.unitCost);
          return l;
        }));
      if (_lines.isEmpty) _lines.add(_PoLine(po.currency.toUpperCase()));
    }
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final r = await Future.wait([
        SupplierService.instance.list(),
        LocationService.instance.list(),
        InventoryService.instance.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _suppliers = r[0] as List<Supplier>;
        _locations = r[1] as List<Location>;
        _items = r[2] as List<InventoryItem>;
        _locationId ??= _locations.isNotEmpty ? _locations.first.id : null;
        // Edited lines link to the loaded catalogue entry when there is one.
        for (final l in _lines) {
          final id = l.item?.id;
          if (id != null) l.item = _items.where((it) => it.id == id).firstOrNull ?? l.item;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  /// A new line starts in the supplier's currency (TZS until one is chosen).
  String get _defaultCurrency {
    final s = _suppliers.where((s) => s.id == _supplierId).firstOrNull;
    final c = s?.currency.toUpperCase();
    return c != null && kCostCurrencies.contains(c) ? c : 'TZS';
  }

  /// Totals per currency, in the order the lines use them.
  Map<String, double> get _totals {
    final t = <String, double>{};
    for (final l in _lines) {
      t[l.currency] = (t[l.currency] ?? 0) + l.quantity * l.unitCost;
    }
    return t;
  }

  /// Currencies of the lines that will be saved — one draft order per currency.
  List<String> get _orderCurrencies => {for (final l in _lines) if (l.item != null) l.currency}.toList();

  /// "USD 37.50", "TZS 400,000" — cents only when there are any (or not shillings).
  static String _amount(String ccy, double v) {
    final cents = ccy != 'TZS' || v != v.roundToDouble();
    final parts = v.toStringAsFixed(cents ? 2 : 0).split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '$ccy $whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _expected ?? now.add(const Duration(days: 14)),
        firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 730)));
    if (d != null) setState(() => _expected = d);
  }

  Future<void> _save() async {
    final lines = _lines.where((l) => l.item != null).toList();
    final problem = _supplierId == null ? 'Choose a supplier.'
        : _locationId == null ? 'Choose where the goods will be received.'
        : lines.isEmpty ? 'Add at least one item.'
        : lines.any((l) => l.quantity < 1) ? 'Every line needs a quantity of at least 1.'
        : null;
    if (problem != null) { setState(() => _error = problem); return; }
    setState(() { _saving = true; _error = null; });
    try {
      // An order is paid, valued and posted in one currency, so lines in
      // different currencies become one draft order per currency.
      PurchaseOrder? first;
      final editing = widget.editing;
      // Editing: the order keeps the lines in its own currency (or the first
      // one used); lines in any other currency become new draft orders.
      final ccys = _orderCurrencies;
      final keep = editing == null ? null
          : (ccys.contains(editing.currency.toUpperCase()) ? editing.currency.toUpperCase() : ccys.first);
      for (final ccy in ccys) {
        Map<String, dynamic> body() => {
          'supplier_id': _supplierId,
          'location_id': _locationId,
          'currency': ccy,
          'expected_delivery_date': _expected?.toIso8601String().substring(0, 10),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          'items': [
            for (final l in lines.where((l) => l.currency == ccy))
              {'inventory_item_id': l.item!.id, 'quantity_ordered': l.quantity, 'unit_cost': l.unitCost, 'currency': ccy},
          ],
        };
        if (editing != null && ccy == keep) {
          first = await PurchaseOrderService.instance.update(editing.id, body());
          continue;
        }
        final po = await PurchaseOrderService.instance.create({
          'supplier_id': _supplierId,
          'location_id': _locationId,
          'currency': ccy,
          if (_expected != null) 'expected_delivery_date': _expected!.toIso8601String().substring(0, 10),
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
          'items': [
            for (final l in lines.where((l) => l.currency == ccy))
              {'inventory_item_id': l.item!.id, 'quantity_ordered': l.quantity, 'unit_cost': l.unitCost, 'currency': ccy},
          ],
        });
        first ??= po;
      }
      if (mounted) Navigator.pop(context, first);
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  Widget _lineRow(_PoLine l, int i, {bool phone = false}) {
    final item = AppSearchableSelectField<int>(
        label: i == 0 ? 'Item' : null,
        hint: 'Search catalogue…',
        selectedLabel: l.item == null ? null : '${l.item!.sku} · ${l.item!.name}',
        items: [for (final it in _items) AppSelectItem(value: it.id, label: '${it.sku} · ${it.name}')],
        onSelected: (sel) => setState(() {
          l.item = sel == null ? null : _items.firstWhere((it) => it.id == sel.value);
          if (l.item != null && l.cost.text.trim().isEmpty && l.item!.unitCost > 0) {
            l.cost.text = _costInput(l.item!.unitCost);
            if (kCostCurrencies.contains(l.item!.costCurrency)) l.currency = l.item!.costCurrency;
          }
        }),
        // Not in inventory yet: add it as a new product (flagged for the
        // store to complete) and put it on this line.
        createNewLabel: (q) => 'Add new product: "$q"',
        onCreateNew: (name) async {
          try {
            final created = await InventoryService.instance.quickCreate(name.trim(), costCurrency: l.currency);
            if (!mounted) return;
            setState(() { _items = [..._items, created]; l.item = created; _error = null; });
          } catch (e) {
            if (mounted) setState(() => _error = friendlyError(e));
          }
        },
      );
    final qty = LabeledTextField(label: i == 0 || phone ? 'Qty' : '', controller: l.qty,
        keyboardType: TextInputType.number, onChanged: (_) => setState(() {}));
    final cost = LabeledTextField(label: i == 0 || phone ? 'Unit cost' : '', controller: l.cost,
        keyboardType: const TextInputType.numberWithOptions(decimal: true), hint: '0', onChanged: (_) => setState(() {}));
    final ccy = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (i == 0 || phone) ...[Text('Currency', style: AppTheme.fieldLabel), const SizedBox(height: 6)],
      DropdownFieldBox<String>(
        value: l.currency,
        items: [for (final c in kCostCurrencies) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) { if (v != null) setState(() => l.currency = v); },
      ),
    ]);
    final remove = SizedBox(width: 32, height: fieldHeightOf(context), child: _lines.length > 1
        ? IconButton(
            tooltip: 'Remove line',
            icon: Icon(Symbols.close, size: 16, color: context.pal.textDim),
            onPressed: () => setState(() { _lines.removeAt(i).dispose(); }),
          )
        : null);
    // Phones: the item on its own row, quantity and cost under it.
    if (phone) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          item,
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(flex: 2, child: qty),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: cost),
            const SizedBox(width: 6),
            SizedBox(width: 92, child: ccy),
            const SizedBox(width: 6),
            remove,
          ]),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(flex: 5, child: item),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: qty),
        const SizedBox(width: 10),
        SizedBox(width: 130, child: cost),
        const SizedBox(width: 6),
        SizedBox(width: 92, child: ccy),
        const SizedBox(width: 6),
        remove,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pal.surface1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _loading
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : LayoutBuilder(builder: (context, cst) {
              final phone = isPhoneWidth(cst.maxWidth);
              final totals = _totals.entries.map((e) => _amount(e.key, e.value));
              final total = Text(totals.join(' + '), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoSm.copyWith(fontSize: 15, color: context.pal.text));
              final split = _orderCurrencies.length;
              final buttons = [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.editing != null ? (split > 1 ? 'Save + ${split - 1} new draft${split > 2 ? 's' : ''}' : 'Save changes')
                          : split > 1 ? 'Create $split drafts' : 'Create draft'),
                ),
              ];
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Symbols.shopping_cart, size: 18, color: AppColors.teal),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.editing == null ? 'New purchase order' : 'Edit ${widget.editing!.poNumber}', style: AppTheme.bodyStrong)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
                ]),
                Text(widget.editing?.status == 'rejected'
                    ? 'Saving puts it back to draft — submit it for approval again from the order panel.'
                    : 'Saved as a draft — send it for approval from the order panel.', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                const SizedBox(height: 16),
                Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: AppSearchableSelectField<int>(
                      label: 'Supplier',
                      hint: 'Search suppliers…',
                      selectedLabel: _supplierId == null ? null : _suppliers.firstWhere((s) => s.id == _supplierId).name,
                      items: [for (final s in _suppliers) AppSelectItem(value: s.id, label: s.name)],
                      onSelected: (sel) => setState(() {
                        _supplierId = sel?.value;
                        // Lines with no cost typed yet follow the supplier's currency.
                        for (final l in _lines) {
                          if (l.cost.text.trim().isEmpty) l.currency = _defaultCurrency;
                        }
                      }),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: LabeledDropdown<int?>(
                      label: 'Receive at',
                      value: _locationId,
                      items: [null, for (final l in _locations) l.id],
                      displayBuilder: (id) => id == null ? 'Choose location' : _locations.firstWhere((l) => l.id == id).name,
                      onChanged: (v) => setState(() => _locationId = v),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: LabeledDateField(label: 'Expected delivery (optional)', date: _expected, onTap: _pickDate,
                        onClear: () => setState(() => _expected = null))),
                  ]),
                  const SizedBox(height: 18),
                  Text('ITEMS', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _lines.length; i++) _lineRow(_lines[i], i, phone: phone),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_PoLine(_lines.isNotEmpty ? _lines.last.currency : _defaultCurrency))),
                    icon: const Icon(Symbols.add, size: 16), label: const Text('Add item'),
                  )),
                  const SizedBox(height: 8),
                  LabeledTextField(label: 'Notes (optional)', controller: _notes, maxLines: 3),
                ]))),
                if (split > 1) ...[
                  const SizedBox(height: 10),
                  Text('Lines are in $split currencies, so this creates $split draft orders, one per currency '
                      '(${_orderCurrencies.join(', ')}). Each goes through approval on its own.',
                      style: AppTheme.bodySub.copyWith(fontSize: 12)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                if (phone) ...[
                  Row(children: [Text('Total  ', style: AppTheme.bodySub), Flexible(child: total)]),
                  const SizedBox(height: 10),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [buttons.first, buttons.last]),
                ] else Row(children: [
                  Text('Total  ', style: AppTheme.bodySub),
                  Expanded(child: total),
                  ...buttons,
                ]),
              ]);
            }),
      ),
    ),
  );
}
