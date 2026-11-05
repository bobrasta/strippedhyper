import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/invoice.dart';
import '../../services/invoice_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/sliver_table.dart';
import '../procurement/tender_forms.dart' show ProcDialog;
import 'invoice_builder_screen.dart';
import 'invoices_screen.dart' show showInvoiceDetail, showRecordPayment, showCreditNotes;

/// All sales — Clickhuduma's sell list: every sale with its payment status,
/// method, totals and who added it, a filtered footer total, and the row
/// action menu (right-click a row, or its Actions button). Drafts and
/// proformas are listed on their own tabs.
class AllSalesScreen extends StatefulWidget {
  const AllSalesScreen({super.key, this.initialKind = 'final'});
  // final | draft | proforma — "List drafts" in the sidebar opens on draft.
  final String initialKind;

  @override
  State<AllSalesScreen> createState() => _AllSalesScreenState();
}

// Columns fit the window (no sideways scroll): proportional widths, and
// the less essential ones drop out on narrower windows. [minWidth] is the
// narrowest table width that still shows the column; [sort] is its sort
// key (null = not sortable).
typedef _Col = ({String label, int flex, bool num, double minWidth, String? sort});

const List<_Col> _cols = [
  (label: 'Date', flex: 8, num: false, minWidth: 0, sort: 'date'),
  (label: 'Invoice No.', flex: 9, num: false, minWidth: 0, sort: 'number'),
  (label: 'Customer', flex: 20, num: false, minWidth: 0, sort: 'customer'),
  (label: 'Status', flex: 8, num: false, minWidth: 0, sort: 'status'),
  (label: 'Method', flex: 9, num: false, minWidth: 1050, sort: 'method'),
  (label: 'Total Amount', flex: 11, num: true, minWidth: 0, sort: 'total'),
  (label: 'Total Paid', flex: 11, num: true, minWidth: 760, sort: 'paid'),
  (label: 'Sell Due', flex: 11, num: true, minWidth: 0, sort: 'due'),
  (label: 'Items', flex: 5, num: true, minWidth: 1250, sort: 'items'),
  (label: 'Added By', flex: 10, num: false, minWidth: 950, sort: 'addedBy'),
  (label: 'Shipping', flex: 8, num: false, minWidth: 1350, sort: 'shipping'),
  (label: 'Sell note', flex: 13, num: false, minWidth: 1150, sort: null),
];

const _shipStatuses = {'ordered': 'Ordered', 'packed': 'Packed', 'shipped': 'Shipped', 'delivered': 'Delivered', 'cancelled': 'Cancelled'};

String _money(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}TSh $b';
}

String _date(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : formatDate(d);
}

String _qty(double? q) => q == null ? '—' : (q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2));

String _methods(Invoice i) => i.paymentMethods.isEmpty
    ? '—'
    : i.paymentMethods.length > 1 ? 'Multiple' : Invoice.methodLabelOf(i.paymentMethods.first);

(String, Color) _payStatusOf(BuildContext context, Invoice i) => switch (i.chPaymentStatus) {
  'paid'      => ('Paid', AppColors.green),
  'partial'   => ('Partial', AppColors.blue),
  'overdue'   => ('Overdue', AppColors.coral),
  'due'       => ('Due', AppColors.amber),
  'cancelled' => ('Cancelled', context.pal.textDim),
  'waived'    => ('Waived', context.pal.textDim),
  'proforma'  => ('Proforma', AppColors.violet),
  'draft'     => ('Draft', context.pal.textMute),
  final s     => (s, context.pal.textMute),
};

class _AllSalesScreenState extends State<AllSalesScreen> {
  // final | draft | proforma
  String _kind = 'final';
  Period _period = Period.defaultPeriod;
  List<Invoice> _all = [];
  Timer? _hoverTimer;
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String? _payStatus, _addedBy, _shipStatus;
  // Rows are built 100 at a time ("Load 100 more").
  static const _batch = 100;
  int _showCount = _batch;
  String _sortKey = 'date';
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    final cached = _kind == 'final' ? InvoiceService.cachedDefaultList : null;
    if (cached != null) {
      _all = cached;
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_all.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await InvoiceService.instance.list(
          period: _period, saleStatus: _kind == 'final' ? null : _kind);
      // Drop prefetched copies the reload shows are out of date (edited,
      // paid, cancelled) so View never opens on old figures.
      for (final i in data) {
        final c = InvoiceService.cachedById[i.id];
        if (c != null && (c.total != i.total || c.amountPaid != i.amountPaid || c.status != i.status
            || c.invoiceNumber != i.invoiceNumber || c.issueDate != i.issueDate)) {
          InvoiceService.cachedById.remove(i.id);
        }
      }
      if (mounted) setState(() { _all = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _setKind(String k) {
    if (k == _kind) return;
    setState(() { _kind = k; _all = []; _showCount = _batch; _payStatus = null; });
    _load();
  }

  List<Invoice> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _all.where((i) {
      if (_addedBy != null && i.addedBy != _addedBy) return false;
      if (_shipStatus != null && i.shippingStatus != _shipStatus) return false;
      // Matches the status chips one-to-one (each sale has one status).
      if (_payStatus != null && i.chPaymentStatus != _payStatus) return false;
      if (q.isNotEmpty &&
          !i.invoiceNumber.toLowerCase().contains(q) &&
          !i.displayName.toLowerCase().contains(q) &&
          !(i.contactPhone ?? '').toLowerCase().contains(q) &&
          !(i.notes ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort(_compare);
  }

  void _resetPage() => setState(() => _showCount = _batch);

  void _sortBy(String key) => setState(() {
    if (_sortKey == key) {
      _sortAsc = !_sortAsc;
    } else {
      _sortKey = key;
      // Text columns start A→Z, dates and money start biggest/newest first.
      _sortAsc = const {'number', 'customer', 'status', 'method', 'addedBy', 'shipping'}.contains(key);
    }
  });

  int _compare(Invoice a, Invoice b) {
    int t(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    final c = switch (_sortKey) {
      'number'   => t(a.invoiceNumber, b.invoiceNumber),
      'customer' => t(a.displayName, b.displayName),
      'status'   => t(a.chPaymentStatus, b.chPaymentStatus),
      'method'   => t(_methods(a), _methods(b)),
      'total'    => a.total.compareTo(b.total),
      'paid'     => a.amountPaid.compareTo(b.amountPaid),
      'due'      => a.balanceDue.compareTo(b.balanceDue),
      'items'    => (a.totalItems ?? 0).compareTo(b.totalItems ?? 0),
      'addedBy'  => t(a.addedBy ?? '', b.addedBy ?? ''),
      'shipping' => t(a.shippingStatus ?? '', b.shippingStatus ?? ''),
      _          => a.issueDate.compareTo(b.issueDate),
    };
    final r = c != 0 ? c : a.id.compareTo(b.id);
    return _sortAsc ? r : -r;
  }

  // ── Row actions (Clickhuduma's menu) ─────────────────────────────────────

  Future<Invoice?> _full(Invoice i) async {
    try {
      return await InvoiceService.instance.get(i.id);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
      return null;
    }
  }

  List<PopupMenuEntry<String>> _menuItems(Invoice i) {
    PopupMenuItem<String> item(String v, IconData icon, String label, {bool enabled = true}) => PopupMenuItem(
      value: v,
      enabled: enabled,
      height: 36,
      child: Row(children: [
        Icon(icon, size: 16, color: enabled ? context.pal.textMute : context.pal.textDim),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(fontSize: 13, color: enabled ? context.pal.text : context.pal.textDim))),
      ]),
    );
    final fin = i.isFinal;
    return [
      item('view', Symbols.visibility, 'View'),
      item('edit', Symbols.edit_square, 'Edit', enabled: i.status != PaymentStatus.cancelled),
      item('delete', Symbols.delete, 'Delete'),
      item('shipping', Symbols.local_shipping, 'Edit Shipping'),
      item('print', Symbols.print, 'Print Invoice'),
      item('delivery', Symbols.description, 'Delivery Note'),
      const PopupMenuDivider(),
      item('pay', Symbols.payments, 'Add payment', enabled: i.canPay),
      item('payments', Symbols.receipt_long, 'View Payments', enabled: fin),
      item('duplicate', Symbols.content_copy, 'Duplicate Sell'),
      item('return', Symbols.undo, 'Sell Return', enabled: fin && i.status != PaymentStatus.cancelled),
      item('url', Symbols.visibility, 'Invoice URL'),
      item('notify', Symbols.mail, 'New Sale Notification'),
    ];
  }

  Future<void> _openMenu(Invoice i, Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: _menuItems(i),
    );
    if (v != null && mounted) _run(v, i);
  }

  Future<void> _run(String action, Invoice i) async {
    switch (action) {
      case 'view':
        if (await showInvoiceDetail(context, i.id, preview: i)) _load();
      case 'edit':
      case 'duplicate':
        final full = await _full(i);
        if (full == null || !mounted) return;
        final saved = await Navigator.push<Invoice>(context, MaterialPageRoute(
          builder: (_) => action == 'edit' ? InvoiceBuilderScreen(editing: full) : InvoiceBuilderScreen(duplicateFrom: full),
        ));
        if (saved != null && mounted) {
          showSuccessToast(context, action == 'edit' ? '${saved.invoiceNumber} saved.' : 'New sale ${saved.invoiceNumber} saved.');
        }
        _load();
      case 'delete':
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text('Delete ${i.invoiceNumber}?'),
          content: Text(i.isFinal
              ? 'The sale and its payments are removed and the accounts reversed. This cannot be undone.'
              : 'This ${i.saleStatus} will be removed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
          ],
        ));
        if (ok != true) return;
        try {
          await InvoiceService.instance.delete(i.id);
          if (mounted) showSuccessToast(context, '${i.invoiceNumber} deleted.');
          _load();
        } catch (e) {
          if (mounted) showErrorToast(context, e);
        }
      case 'shipping':
        final saved = await showDialog<bool>(context: context, builder: (_) => _ShippingDialog(invoice: i));
        if (saved == true) _load();
      case 'print':
        await downloadPdf(context, () => InvoiceService.instance.pdfBytes(i.id), '${i.invoiceNumber}.pdf');
      case 'delivery':
        await downloadPdf(context, () => InvoiceService.instance.deliveryNoteBytes(i.id), 'DN-${i.invoiceNumber}.pdf');
      case 'pay':
        final full = await _full(i);
        if (full != null && mounted && await showRecordPayment(context, full)) _load();
      case 'payments':
        final full = await _full(i);
        if (full != null && mounted) await showDialog(context: context, builder: (_) => _PaymentsDialog(invoice: full));
      case 'return':
        final full = await _full(i);
        if (full != null && mounted && await showCreditNotes(context, full)) _load();
      case 'url':
        await _showInvoiceUrl(i);
      case 'notify':
        await showDialog(context: context, builder: (_) => _NotifyDialog(invoice: i));
    }
  }

  Future<void> _showInvoiceUrl(Invoice i) async {
    try {
      final url = await InvoiceService.instance.shareLink(i.id);
      if (!mounted) return;
      await showDialog(context: context, builder: (c) => ProcDialog(
        title: 'Invoice URL · ${i.invoiceNumber}',
        icon: Symbols.link,
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Anyone with this link can open the invoice PDF for the next 7 days.', style: AppTheme.bodySub),
          const SizedBox(height: 12),
          SelectableText(url, style: AppTheme.monoSm.copyWith(fontSize: 12)),
        ]),
        actions: [
          FilledButton.icon(
            icon: const Icon(Symbols.content_copy, size: 15),
            label: const Text('Copy link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
              showSuccessToast(context, 'Link copied.');
            },
          ),
        ],
      ));
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  // Server-side limit for a PDF (SalesExportService::PDF_MAX_ROWS).
  static const _pdfMaxRows = 2000;
  bool _exporting = false;

  Future<void> _export(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final format = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'xlsx', height: 38, child: Row(children: [
          Icon(Symbols.table_view, size: 16, color: AppColors.green), const SizedBox(width: 10), const Text('Excel (.xlsx)')])),
        PopupMenuItem(value: 'pdf', height: 38, child: Row(children: [
          Icon(Symbols.picture_as_pdf, size: 16, color: AppColors.coral), const SizedBox(width: 10), const Text('PDF')])),
      ],
    );
    if (format == null || !mounted) return;
    final rows = _filtered;
    if (rows.isEmpty) return showErrorToast(context, 'No sales to export.');
    if (format == 'pdf' && rows.length > _pdfMaxRows) {
      return showErrorToast(context, '${rows.length} sales is too many for a PDF (max $_pdfMaxRows). Narrow the filters or export to Excel.');
    }
    setState(() => _exporting = true);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final kind = _kind == 'final' ? 'sales' : '${_kind}s';
    await downloadPdf(context, () => InvoiceService.instance.exportBytes(format, [for (final i in rows) i.id],
        saleStatus: _kind == 'final' ? null : _kind), 'all-$kind-$stamp.$format');
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _addSale() async {
    final saved = await Navigator.push<Invoice>(context, MaterialPageRoute(builder: (_) => const InvoiceBuilderScreen()));
    if (saved != null && mounted) showSuccessToast(context, '${saved.invoiceNumber} saved.');
    _load();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final users = {for (final i in _all) ?i.addedBy}.toList()..sort();

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 24.0;
      final phone = isPhoneWidth(cst.maxWidth);
      final tableW = cst.maxWidth - 2 * pad;
      final cols = [for (final c in _cols) if (tableW >= c.minWidth) c];
      final userFilter = SizedBox(width: 170, child: DropdownFieldBox<String?>(
        value: users.contains(_addedBy) ? _addedBy : null,
        active: _addedBy != null,
        items: [null, ...users].map((u) => DropdownMenuItem(value: u, child: Text(u ?? 'All users', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { _addedBy = v; _resetPage(); },
      ));
      final shipFilter = SizedBox(width: 160, child: DropdownFieldBox<String?>(
        value: _shipStatus,
        active: _shipStatus != null,
        items: [null, ..._shipStatuses.keys].map((v) => DropdownMenuItem(value: v, child: Text(v == null ? 'Any shipping' : _shipStatuses[v]!))).toList(),
        onChanged: (v) { _shipStatus = v; _resetPage(); },
      ));
      final period = PeriodSelector(value: _period, onChanged: (p) { setState(() { _period = p; _showCount = _batch; }); _load(); });
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) PhonePageHeader(
          title: 'All sales',
          subtitle: 'Tap a sale to open it · long-press for its actions',
          primary: PageAction(label: 'Add sale', shortLabel: 'Add', icon: Symbols.add, onPressed: _addSale),
          secondary: [PageAction(label: 'Export as…', icon: Symbols.download,
              onPressed: _exporting || _loading ? null
                  : () => _export(Offset(cst.maxWidth - 16, 120)))],
          search: SearchField(hint: 'Invoice, customer, phone…', controller: _searchCtrl, onChanged: (_) => _resetPage()),
          filters: [period, userFilter, shipFilter],
          bottom: PhoneScrollRow(spacing: 8, children: _statusChips(context, rows)),
        )
        // Fixed: head, status chips and filters. The summary and table scroll together.
        else Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All sales', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('Right-click a sale for its actions · click a column to sort', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              DenseFields(child: SearchField(width: 240, hint: 'Invoice, customer, phone…', controller: _searchCtrl, onChanged: (_) => _resetPage())),
              const SizedBox(width: 8),
              Builder(builder: (b) => OutlinedButton.icon(
                onPressed: _exporting || _loading ? null : () {
                  final box = b.findRenderObject() as RenderBox;
                  _export(box.localToGlobal(Offset(0, box.size.height + 4)));
                },
                icon: _exporting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Symbols.download, size: 16),
                label: const Text('Export as'),
              )),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _addSale, icon: const Icon(Symbols.add, size: 16), label: const Text('Add sale')),
            ]),
            const SizedBox(height: 12),
            // Filter selects are 28px, like the search box above.
            DenseFields(child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ..._statusChips(context, rows),
              const SizedBox(width: 6),
              period,
              userFilter,
              shipFilter,
            ])),
          ]),
        ),
        SizedBox(height: phone ? 12 : 14),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null && _all.isEmpty
                ? ErrorView(message: _error!, onRetry: _load)
                : CustomScrollView(slivers: [
                    SliverToBoxAdapter(child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 14),
                      child: _summary(context, rows, phone: phone),
                    )),
                    if (phone) ...[
                      if (rows.isEmpty)
                        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: Text('No sales found', style: AppTheme.bodySub)))),
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (ctx, n) => _saleCard(ctx, rows[n]),
                        childCount: rows.length < _showCount ? rows.length : _showCount,
                      )),
                      if (rows.length > _showCount)
                        SliverToBoxAdapter(child: LoadMoreRow(shown: _showCount, total: rows.length,
                            step: _batch, onTap: () => setState(() => _showCount += _batch))),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ] else ...sliverTable(
                      context,
                      pad: pad,
                      headerHeight: 40,
                      header: _header(context, cols),
                      itemCount: rows.length < _showCount ? rows.length : _showCount,
                      itemBuilder: (ctx, n) => _saleRow(ctx, cols, rows[n]),
                      emptyText: 'No sales found',
                      totalCount: rows.length,
                      loadStep: _batch,
                      onLoadMore: () => setState(() => _showCount += _batch),
                    ),
                  ])),
      ]);
    });
  }

  // Summary above the table: the money, then the payment-status chips
  // (they filter the table) and the payment-method mix.
  /// Phone row: customer, invoice number, status, what's due; tap opens
  /// the sale, long-press opens the same actions menu as right-click.
  Widget _saleCard(BuildContext context, Invoice i) {
    final (label, color) = _payStatusOf(context, i);
    return GestureDetector(
      onLongPressStart: (d) { InvoiceService.instance.prefetch(i.id); _openMenu(i, d.globalPosition); },
      child: PhoneRecordCard(
        title: i.displayName,
        subtitle: '${i.invoiceNumber} · ${_date(i.issueDate)}',
        badge: PhonePill(label, color),
        meta: [_methods(i), if (i.addedBy != null) 'by ${i.addedBy}',
            if (i.balanceDue > 0) 'due ${_money(i.balanceDue)}'],
        amount: _money(i.total),
        onTap: () => showInvoiceDetail(context, i.id, preview: i).then((changed) { if (changed) _load(); }),
      ),
    );
  }

  Widget _summary(BuildContext context, List<Invoice> rows, {bool phone = false}) {
    // Counts and money ignore the status filter, so the chips keep their numbers.
    final base = _payStatus == null ? rows : _withoutStatusFilter();
    final total = base.fold<int>(0, (s, i) => s + i.total);
    final paid = base.fold<int>(0, (s, i) => s + i.amountPaid);
    final due = base.fold<int>(0, (s, i) => s + i.balanceDue);
    final methods = <String, int>{};
    for (final i in base) {
      final m = _methods(i);
      if (m != '—') methods[m] = (methods[m] ?? 0) + 1;
    }
    Widget kpi(String label, String value, Color color, String sub) => Expanded(child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.kpiValue.copyWith(fontSize: 20, color: color)),
        const SizedBox(height: 3),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 11)),
      ]),
    ));
    final rate = total > 0 ? (paid * 100 / total).round() : 0;
    final overdueDue = base.where((i) => i.chPaymentStatus == 'overdue').fold<int>(0, (s, i) => s + i.balanceDue);

    final kpis = [
        kpi('TOTAL SALES', tshFromDouble(total), context.pal.text, '${base.length} sale${base.length == 1 ? '' : 's'} · ${_period.label}'),
        const SizedBox(width: 12),
        kpi('TOTAL PAID', tshFromDouble(paid), AppColors.green, '$rate% collected'),
        const SizedBox(width: 12),
        kpi('SELL DUE', tshFromDouble(due), AppColors.amber, overdueDue > 0 ? '${tshFromDouble(overdueDue)} overdue' : 'nothing overdue'),
        const SizedBox(width: 12),
        kpi('PAID BY', methods.isEmpty ? '—' : (methods.entries.toList()..sort((a, b) => b.value - a.value)).first.key,
            context.pal.text, methods.entries.map((e) => '${e.key} ${e.value}').join(' · ')),
    ];
    // Phones: the four tiles two to a row (kpi() wraps each in Expanded).
    if (phone) {
      return PhoneStatGrid(spacing: 10, children: [
        for (final k in kpis) if (k is Expanded) k.child,
      ]);
    }
    return Row(children: kpis);
  }

  // Payment-status chips (they filter the table), then Drafts and
  // Proformas, which load those unfinished sales instead.
  List<Widget> _statusChips(BuildContext context, List<Invoice> rows) {
    final sales = _kind == 'final';
    final base = !sales ? const <Invoice>[] : _payStatus == null ? rows : _withoutStatusFilter();
    final counts = <String, int>{};
    for (final i in base) {
      counts[i.chPaymentStatus] = (counts[i.chPaymentStatus] ?? 0) + 1;
    }
    void pick(String? status) {
      if (!sales) {
        _setKind('final');
        setState(() => _payStatus = status);
        return;
      }
      _payStatus = _payStatus == status ? null : status;
      _resetPage();
    }
    return [
      _Chip(label: 'All', count: sales ? base.length : null, active: sales && _payStatus == null, color: AppColors.teal,
          onTap: () => pick(null)),
      for (final (k, l, c) in [('paid', 'Paid', AppColors.green), ('due', 'Due', AppColors.amber),
                                ('partial', 'Partial', AppColors.blue), ('overdue', 'Overdue', AppColors.coral),
                                ('cancelled', 'Cancelled', context.pal.textDim)])
        if (!sales || (counts[k] ?? 0) > 0 || _payStatus == k)
          _Chip(label: l, count: sales ? counts[k] ?? 0 : null, active: sales && _payStatus == k, color: c,
              onTap: () => pick(k)),
      for (final (k, l) in const [('draft', 'Drafts'), ('proforma', 'Proformas')])
        _Chip(label: l, count: _kind == k ? rows.length : null, active: _kind == k, color: AppColors.violet,
            onTap: () => _setKind(_kind == k ? 'final' : k)),
    ];
  }

  List<Invoice> _withoutStatusFilter() {
    final keep = _payStatus;
    _payStatus = null;
    final r = _filtered;
    _payStatus = keep;
    return r;
  }

  Widget _header(BuildContext context, List<_Col> cols) => SizedBox(
    height: 40,
    child: Row(children: [
      for (final c in cols)
        Expanded(flex: c.flex, child: InkWell(
          onTap: c.sort == null ? null : () => _sortBy(c.sort!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: c.num ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Flexible(child: Text(c.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelCaps.copyWith(fontSize: 9.5,
                        color: _sortKey == c.sort ? AppColors.teal : null))),
                if (c.sort != null && _sortKey == c.sort)
                  Icon(_sortAsc ? Symbols.arrow_upward : Symbols.arrow_downward, size: 12, color: AppColors.teal),
              ],
            ),
          ),
        )),
    ]),
  );

  Widget _saleRow(BuildContext context, List<_Col> cols, Invoice i) {
    final (label, color) = _payStatusOf(context, i);
    final cell = AppTheme.bodySm.copyWith(fontSize: 12.5);
    final money = AppTheme.monoSm.copyWith(fontSize: 12);
    final sub = AppTheme.bodySub.copyWith(fontSize: 11);
    Text t(String? s, {TextStyle? style}) => Text(s == null || s.trim().isEmpty ? '—' : s,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? cell);

    Widget cellFor(_Col c) => switch (c.label) {
      'Date' => t(_date(i.issueDate)),
      'Invoice No.' => t(i.invoiceNumber, style: money.copyWith(fontWeight: FontWeight.w600)),
      'Customer' => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Tooltip(message: i.displayName, child: t(i.displayName)),
          if ((i.contactPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').length >= 7) t(i.contactPhone, style: sub),
        ]),
      'Status' => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      'Method' => t(_methods(i)),
      'Total Amount' => Tooltip(message: _money(i.total), child: t(_money(i.total), style: money)),
      'Total Paid' => t(_money(i.amountPaid), style: money.copyWith(color: AppColors.green)),
      'Sell Due' => t(_money(i.balanceDue), style: money.copyWith(color: i.balanceDue > 0 ? AppColors.amber : context.pal.textDim)),
      'Items' => t(_qty(i.totalItems), style: money),
      'Added By' => t(i.addedBy),
      'Shipping' => t(_shipStatuses[i.shippingStatus]),
      'Sell note' => Tooltip(message: i.notes ?? '', child: t(i.notes)),
      _ => const SizedBox(),
    };

    // Resting the pointer on a row starts fetching the full sale, so View
    // opens with its line items and payments already loaded.
    return MouseRegion(
      onEnter: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 150), () => InvoiceService.instance.prefetch(i.id));
      },
      onExit: (_) => _hoverTimer?.cancel(),
      child: GestureDetector(
        onSecondaryTapDown: (d) { InvoiceService.instance.prefetch(i.id); _openMenu(i, d.globalPosition); },
        onLongPressStart: (d) { InvoiceService.instance.prefetch(i.id); _openMenu(i, d.globalPosition); },
        child: InkWell(
          onTap: () => showInvoiceDetail(context, i.id, preview: i).then((changed) { if (changed) _load(); }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                for (final c in cols)
                  Expanded(flex: c.flex, child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(alignment: c.num ? Alignment.centerRight : Alignment.centerLeft, child: cellFor(c)),
                  )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.count, required this.active, required this.color, required this.onTap});
  final String label; final int? count; final bool active; final Color color; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.14) : context.pal.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? color : context.pal.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count', style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textMute)),
        ],
      ]),
    ),
  );
}

// ── Edit Shipping ───────────────────────────────────────────────────────────
class _ShippingDialog extends StatefulWidget {
  const _ShippingDialog({required this.invoice});
  final Invoice invoice;
  @override
  State<_ShippingDialog> createState() => _ShippingDialogState();
}

class _ShippingDialogState extends State<_ShippingDialog> {
  late final _details = TextEditingController(text: widget.invoice.shippingDetails ?? '');
  late final _address = TextEditingController(text: widget.invoice.shippingAddress ?? '');
  late final _charges = TextEditingController(text: widget.invoice.shippingCharges > 0 ? '${widget.invoice.shippingCharges}' : '');
  late final _deliveredTo = TextEditingController(text: widget.invoice.deliveredTo ?? '');
  late String? _status = widget.invoice.shippingStatus;
  bool _saving = false;

  @override
  void dispose() {
    _details.dispose(); _address.dispose(); _charges.dispose(); _deliveredTo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final charges = _charges.text.trim().isEmpty ? 0 : int.tryParse(_charges.text.replaceAll(',', '').trim());
    if (charges == null) {
      showErrorToast(context, Exception('Enter the shipping charge as a number.'));
      return;
    }
    setState(() => _saving = true);
    try {
      String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await InvoiceService.instance.updateShipping(widget.invoice.id, {
        'shipping_details': v(_details),
        'shipping_address': v(_address),
        'shipping_charges': charges,
        'shipping_status':  _status,
        'delivered_to':     v(_deliveredTo),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'Edit Shipping · ${widget.invoice.invoiceNumber}',
    icon: Symbols.local_shipping,
    width: 560,
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'Shipping details', controller: _details, maxLines: 2, hint: 'Vehicle, courier, tracking no.…'),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Shipping address', controller: _address, maxLines: 2, hint: 'Where the goods go'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: LabeledTextField(label: 'Shipping charges', controller: _charges, hint: '0',
            keyboardType: TextInputType.number)),
        const SizedBox(width: 12),
        Expanded(child: LabeledDropdown<String?>(
          label: 'Shipping status', value: _status,
          items: [null, ..._shipStatuses.keys],
          displayBuilder: (v) => v == null ? 'Please select' : _shipStatuses[v]!,
          onChanged: (v) => setState(() => _status = v),
        )),
      ]),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Delivered to', controller: _deliveredTo, hint: 'Name of the person who received it'),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Update')),
    ],
  );
}

// ── View Payments ───────────────────────────────────────────────────────────
class _PaymentsDialog extends StatelessWidget {
  const _PaymentsDialog({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final head = AppTheme.labelCaps.copyWith(fontSize: 10);
    final cell = AppTheme.bodySm.copyWith(fontSize: 12.5);
    return ProcDialog(
      title: 'Payments · ${invoice.invoiceNumber}',
      icon: Symbols.receipt_long,
      width: 720,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${invoice.displayName} · total ${_money(invoice.total)} · paid ${_money(invoice.amountPaid)} · due ${_money(invoice.balanceDue)}',
            style: AppTheme.bodySub),
        const SizedBox(height: 12),
        if (invoice.payments.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No payments yet.', style: AppTheme.bodySub)))
        else ...[
          Row(children: [
            Expanded(flex: 2, child: Text('DATE', style: head)),
            Expanded(flex: 3, child: Text('REFERENCE NO', style: head)),
            Expanded(flex: 3, child: Text('AMOUNT', style: head)),
            Expanded(flex: 3, child: Text('PAYMENT METHOD', style: head)),
            Expanded(flex: 3, child: Text('NOTE', style: head)),
          ]),
          const Divider(),
          for (final p in invoice.payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(flex: 2, child: Text(_date(p.paidAt.length >= 10 ? p.paidAt.substring(0, 10) : p.paidAt), style: cell)),
                Expanded(flex: 3, child: Text([p.paymentNumber, ?p.reference].join(' · '), style: cell)),
                Expanded(flex: 3, child: Text(_money(p.amount), style: AppTheme.monoSm.copyWith(fontSize: 12))),
                Expanded(flex: 3, child: Text(p.methodLabel, style: cell)),
                Expanded(flex: 3, child: Text(p.notes ?? '—', style: cell)),
              ]),
            ),
        ],
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// ── New Sale Notification ───────────────────────────────────────────────────
class _NotifyDialog extends StatefulWidget {
  const _NotifyDialog({required this.invoice});
  final Invoice invoice;
  @override
  State<_NotifyDialog> createState() => _NotifyDialogState();
}

class _NotifyDialogState extends State<_NotifyDialog> {
  late final Invoice i = widget.invoice;
  late final _to = TextEditingController(text: i.clientEmail ?? '');
  late final _subject = TextEditingController(text: 'Invoice ${i.invoiceNumber} from Hypermed Healthcare');
  late final _message = TextEditingController(text:
      'Dear ${i.displayName},\n\n'
      'Your invoice number is ${i.invoiceNumber}.\n'
      'Total amount: ${_money(i.total)}\n'
      'Paid amount: ${_money(i.amountPaid)}\n'
      'Balance due: ${_money(i.balanceDue)}\n\n'
      'The invoice is attached.\n\n'
      'Thank you for your business.\n'
      'Hypermed Healthcare Ltd');
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose(); _subject.dispose(); _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_to.text.trim())) {
      showErrorToast(context, Exception('Enter the customer’s email address.'));
      return;
    }
    setState(() => _sending = true);
    try {
      final msg = await InvoiceService.instance.notify(i.id,
          to: _to.text.trim(), subject: _subject.text.trim(), message: _message.text);
      if (mounted) { Navigator.pop(context); showSuccessToast(context, msg); }
    } catch (e) {
      if (mounted) { setState(() => _sending = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'New Sale Notification · ${i.invoiceNumber}',
    icon: Symbols.mail,
    width: 620,
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledTextField(label: 'To', controller: _to, hint: 'customer@example.com', keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Subject', controller: _subject),
      const SizedBox(height: 12),
      LabeledTextField(label: 'Message', controller: _message, maxLines: 11),
      const SizedBox(height: 8),
      Text('The invoice PDF is attached. Replies come to you.', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton.icon(onPressed: _sending ? null : _send, icon: const Icon(Symbols.send, size: 15),
          label: Text(_sending ? 'Sending…' : 'Send')),
    ],
  );
}
