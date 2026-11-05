import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/purchase_order.dart';
import '../../models/purchase_return.dart';
import '../../services/purchase_order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/sliver_table.dart';
import '../inventory/purchase_orders_screen.dart' show showPurchaseOrderDetail;
import '../procurement/tender_forms.dart' show ProcDialog;

/// List purchase returns — Clickhuduma's purchase-return list: goods sent
/// back to suppliers out of received purchases. Recording one takes the
/// stock out of the store and, when the purchase's supplier invoice is on
/// the books, credits the supplier's account.
class PurchaseReturnsScreen extends StatefulWidget {
  const PurchaseReturnsScreen({super.key});

  @override
  State<PurchaseReturnsScreen> createState() => _PurchaseReturnsScreenState();
}

typedef _Col = ({String label, int flex, bool num, double minWidth, String? sort});

const List<_Col> _cols = [
  (label: 'Date', flex: 8, num: false, minWidth: 0, sort: 'date'),
  (label: 'Reference No', flex: 10, num: false, minWidth: 0, sort: 'number'),
  (label: 'Parent Purchase', flex: 10, num: false, minWidth: 0, sort: 'purchase'),
  (label: 'Location', flex: 10, num: false, minWidth: 1100, sort: 'location'),
  (label: 'Supplier', flex: 16, num: false, minWidth: 0, sort: 'supplier'),
  (label: 'Items', flex: 5, num: true, minWidth: 1000, sort: 'items'),
  (label: 'Grand Total', flex: 11, num: true, minWidth: 0, sort: 'total'),
  (label: 'Supplier Account', flex: 10, num: false, minWidth: 850, sort: 'posted'),
  (label: 'Added By', flex: 10, num: false, minWidth: 1250, sort: 'addedBy'),
];

String _amount(String currency, num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  final cur = currency.toUpperCase() == 'TZS' ? 'TSh' : currency.toUpperCase();
  return '${n < 0 ? '-' : ''}$cur $b';
}

class _PurchaseReturnsScreenState extends State<PurchaseReturnsScreen> {
  Period _period = Period.defaultPeriod;
  List<PurchaseReturn> _all = [];
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String? _supplier;
  static const _batch = 100;
  int _showCount = _batch;
  String _sortKey = 'date';
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    final cached = PurchaseOrderService.cachedDefaultReturns;
    if (cached != null) { _all = cached; _loading = false; }
    _load();
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
      final data = await PurchaseOrderService.instance.returns(period: _period);
      if (mounted) setState(() { _all = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<PurchaseReturn> get _rows {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _all.where((r) {
      if (_supplier != null && r.supplierName != _supplier) return false;
      if (q.isNotEmpty &&
          !r.returnNumber.toLowerCase().contains(q) &&
          !(r.poNumber ?? '').toLowerCase().contains(q) &&
          !(r.supplierName ?? '').toLowerCase().contains(q) &&
          !(r.reason ?? '').toLowerCase().contains(q)) {
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
      _sortAsc = const {'number', 'purchase', 'location', 'supplier', 'posted', 'addedBy'}.contains(key);
    }
  });

  int _compare(PurchaseReturn a, PurchaseReturn b) {
    int t(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    final c = switch (_sortKey) {
      'number'   => t(a.returnNumber, b.returnNumber),
      'purchase' => t(a.poNumber ?? '', b.poNumber ?? ''),
      'location' => t(a.locationName ?? '', b.locationName ?? ''),
      'supplier' => t(a.supplierName ?? '', b.supplierName ?? ''),
      'items'    => a.totalItems.compareTo(b.totalItems),
      'total'    => a.totalAmount.compareTo(b.totalAmount),
      'posted'   => (a.posted ? 1 : 0).compareTo(b.posted ? 1 : 0),
      'addedBy'  => t(a.addedBy ?? '', b.addedBy ?? ''),
      _          => a.returnDate.compareTo(b.returnDate),
    };
    final r = c != 0 ? c : a.id.compareTo(b.id);
    return _sortAsc ? r : -r;
  }

  // ── Row actions ──────────────────────────────────────────────────────────

  Future<void> _openMenu(PurchaseReturn r, Offset global) async {
    PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(
      value: v,
      height: 36,
      child: Row(children: [
        Icon(icon, size: 16, color: context.pal.textMute),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 13, color: context.pal.text))),
      ]),
    );
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        item('view', Symbols.visibility, 'View'),
        item('print', Symbols.print, 'Print'),
        item('purchase', Symbols.shopping_cart, 'View parent purchase'),
      ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'view':
        await showDialog(context: context, builder: (_) => _ReturnDetailDialog(ret: r));
      case 'print':
        await downloadPdf(context, () => PurchaseOrderService.instance.returnPdfBytes(r.id), '${r.returnNumber}.pdf');
      case 'purchase':
        if (await showPurchaseOrderDetail(context, r.purchaseOrderId)) _load();
    }
  }

  Future<void> _addReturn() async {
    final po = await showDialog<PurchaseOrder>(context: context, builder: (_) => const _PickPurchaseDialog());
    if (po == null || !mounted) return;
    final ret = await showPurchaseReturnDialog(context, po);
    if (ret == null || !mounted) return;
    showSuccessToast(context, '${ret.returnNumber} recorded — stock taken out of ${ret.locationName ?? 'the store'}.');
    _load();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final suppliers = {for (final r in _all) ?r.supplierName}.toList()..sort();

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 24.0;
      final phone = isPhoneWidth(cst.maxWidth);
      final tableW = cst.maxWidth - 2 * pad;
      final cols = [for (final c in _cols) if (tableW >= c.minWidth) c];
      final supplierFilter = SizedBox(width: 190, child: DropdownFieldBox<String?>(
        value: suppliers.contains(_supplier) ? _supplier : null,
        active: _supplier != null,
        items: [null, ...suppliers].map((v) => DropdownMenuItem(value: v, child: Text(v ?? 'All suppliers', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { _supplier = v; _resetPage(); },
      ));
      final period = PeriodSelector(value: _period, onChanged: (p) { setState(() { _period = p; _showCount = _batch; }); _load(); });
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) PhonePageHeader(
          title: 'Purchase returns',
          subtitle: 'Goods sent back to suppliers · long-press for actions',
          primary: PageAction(label: 'Add return', shortLabel: 'Add', icon: Symbols.add, onPressed: _addReturn),
          search: SearchField(hint: 'Return, purchase, supplier…', controller: _searchCtrl, onChanged: (_) => _resetPage()),
          filters: [period, supplierFilter],
        )
        else Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Purchase returns', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('Goods sent back to suppliers · right-click a return for its actions', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              DenseFields(child: SearchField(width: 240, hint: 'Return, purchase, supplier…', controller: _searchCtrl, onChanged: (_) => _resetPage())),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _addReturn, icon: const Icon(Symbols.add, size: 16), label: const Text('Add return')),
            ]),
            const SizedBox(height: 12),
            DenseFields(child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              period,
              supplierFilter,
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
                            child: Center(child: Text('No purchase returns found', style: AppTheme.bodySub)))),
                      SliverList(delegate: SliverChildBuilderDelegate(
                        (ctx, n) => _card(ctx, rows[n]),
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
                      itemBuilder: (ctx, n) => _row(ctx, cols, rows[n]),
                      emptyText: 'No purchase returns found',
                      totalCount: rows.length,
                      loadStep: _batch,
                      onLoadMore: () => setState(() => _showCount += _batch),
                    ),
                  ])),
      ]);
    });
  }

  Widget _card(BuildContext context, PurchaseReturn r) => GestureDetector(
    onLongPressStart: (d) => _openMenu(r, d.globalPosition),
    child: PhoneRecordCard(
      title: r.supplierName ?? '—',
      subtitle: '${r.returnNumber} · ${formatDate(r.returnDate)}',
      badge: PhonePill(r.posted ? 'Credited' : 'Stock only', r.posted ? AppColors.green : AppColors.blue),
      meta: [if (r.poNumber != null) r.poNumber!, '${r.totalItems} item${r.totalItems == 1 ? '' : 's'}', if (r.addedBy != null) 'by ${r.addedBy}'],
      amount: _amount(r.currency, r.totalAmount),
      onTap: () => showDialog(context: context, builder: (_) => _ReturnDetailDialog(ret: r)),
    ),
  );

  Widget _summary(BuildContext context, List<PurchaseReturn> rows, {bool phone = false}) {
    final tzs = rows.where((r) => r.currency.toUpperCase() == 'TZS').fold<double>(0, (s, r) => s + r.totalAmount);
    final foreign = <String, double>{};
    for (final r in rows.where((r) => r.currency.toUpperCase() != 'TZS')) {
      foreign[r.currency] = (foreign[r.currency] ?? 0) + r.totalAmount;
    }
    final credited = rows.where((r) => r.posted).length;
    final items = rows.fold<int>(0, (s, r) => s + r.totalItems);
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
    final kpis = [
      kpi('TOTAL RETURNED', _amount('TZS', tzs), AppColors.coral,
          [ '${rows.length} return${rows.length == 1 ? '' : 's'} · ${_period.label}',
            for (final e in foreign.entries) _amount(e.key, e.value)].join(' · ')),
      const SizedBox(width: 12),
      kpi('UNITS SENT BACK', '$items', context.pal.text, 'across every return listed'),
      const SizedBox(width: 12),
      kpi('ON SUPPLIER ACCOUNT', '$credited of ${rows.length}', AppColors.green, 'credited against their invoice'),
    ];
    if (phone) {
      return PhoneStatGrid(spacing: 10, children: [
        for (final k in kpis) if (k is Expanded) k.child,
      ]);
    }
    return Row(children: kpis);
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

  Widget _row(BuildContext context, List<_Col> cols, PurchaseReturn r) {
    final cell = AppTheme.bodySm.copyWith(fontSize: 12.5);
    final money = AppTheme.monoSm.copyWith(fontSize: 12);
    Text t(String? s, {TextStyle? style}) => Text(s == null || s.trim().isEmpty ? '—' : s,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? cell);
    final color = r.posted ? AppColors.green : AppColors.blue;

    Widget cellFor(_Col c) => switch (c.label) {
      'Date' => t(formatDate(r.returnDate)),
      'Reference No' => t(r.returnNumber, style: money.copyWith(fontWeight: FontWeight.w600)),
      'Parent Purchase' => t(r.poNumber, style: money),
      'Location' => t(r.locationName),
      'Supplier' => Tooltip(message: r.supplierName ?? '', child: t(r.supplierName)),
      'Items' => t('${r.totalItems}', style: money),
      'Grand Total' => t(_amount(r.currency, r.totalAmount), style: money.copyWith(color: AppColors.coral)),
      'Supplier Account' => Tooltip(
          message: r.posted ? 'Credited against the purchase’s supplier invoice' : 'The purchase had no supplier invoice yet — only the stock went back',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
            child: Text(r.posted ? 'Credited' : 'Stock only', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          )),
      'Added By' => t(r.addedBy),
      _ => const SizedBox(),
    };

    return GestureDetector(
      onSecondaryTapDown: (d) => _openMenu(r, d.globalPosition),
      onLongPressStart: (d) => _openMenu(r, d.globalPosition),
      child: InkWell(
        onTap: () => showDialog(context: context, builder: (_) => _ReturnDetailDialog(ret: r)),
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
    );
  }
}

// ── View a return ───────────────────────────────────────────────────────────
class _ReturnDetailDialog extends StatelessWidget {
  const _ReturnDetailDialog({required this.ret});
  final PurchaseReturn ret;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: AppTheme.bodySub.copyWith(fontSize: 12))),
        Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
      ]),
    );
    return ProcDialog(
      title: 'Purchase return · ${ret.returnNumber}',
      icon: Symbols.undo,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('Supplier', ret.supplierName ?? '—'),
        row('Purchase', ret.poNumber ?? '—'),
        row('Date', formatDate(ret.returnDate)),
        row('From store', ret.locationName ?? '—'),
        row('Supplier account', ret.posted ? 'Credited against their invoice' : 'Not on their account — the purchase had no supplier invoice yet'),
        if (ret.addedBy != null) row('Added by', ret.addedBy!),
        if ((ret.reason ?? '').isNotEmpty) row('Reason', ret.reason!),
        const SizedBox(height: 12),
        for (final l in ret.lines)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(l.itemName ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 12.5))),
              const SizedBox(width: 8),
              Text('${l.quantity} × ${_amount(ret.currency, l.unitCost)}', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
              const SizedBox(width: 10),
              Text(_amount(ret.currency, l.total), style: AppTheme.monoSm.copyWith(fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 6),
        Row(children: [
          Text('Total returned', style: AppTheme.bodySub),
          const Spacer(),
          Text(_amount(ret.currency, ret.totalAmount), style: AppTheme.monoSm.copyWith(fontSize: 15, color: AppColors.coral)),
        ]),
      ]),
      actions: [
        OutlinedButton.icon(
          onPressed: () => downloadPdf(context, () => PurchaseOrderService.instance.returnPdfBytes(ret.id), '${ret.returnNumber}.pdf'),
          icon: const Icon(Symbols.print, size: 16), label: const Text('Print'),
        ),
      ],
    );
  }
}

// ── Add return: pick the purchase ─────────────────────────────────────────
class _PickPurchaseDialog extends StatefulWidget {
  const _PickPurchaseDialog();
  @override
  State<_PickPurchaseDialog> createState() => _PickPurchaseDialogState();
}

class _PickPurchaseDialogState extends State<_PickPurchaseDialog> {
  List<PurchaseOrder> _received = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    PurchaseOrderService.instance.list(period: Period.of(PeriodPreset.allTime)).then((all) {
      if (mounted) setState(() { _received = all.where((p) => p.canReturn).toList(); _loading = false; });
    }).catchError((Object e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: 'Add purchase return',
    icon: Symbols.undo,
    width: 520,
    body: _loading
        ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        : _error != null
            ? ErrorView(message: _error!, compact: true)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Goods go back out of a purchase that was received. Choose it:', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                const SizedBox(height: 12),
                AppSearchableSelectField<int>(
                  label: 'Purchase',
                  hint: _received.isEmpty ? 'No received purchases' : 'Search reference or supplier…',
                  selectedLabel: null,
                  items: [for (final p in _received) AppSelectItem(value: p.id,
                      label: '${p.poNumber} · ${p.supplierName ?? '—'} · ${formatDate(p.createdAt)}')],
                  onSelected: (sel) {
                    if (sel == null) return;
                    Navigator.pop(context, _received.firstWhere((p) => p.id == sel.value));
                  },
                ),
              ]),
  );
}

// ── The return itself ──────────────────────────────────────────────────────

/// Records goods sent back to the supplier out of [po] (Purchase Return on
/// a purchase's menu, or Add return). Resolves with the saved return.
Future<PurchaseReturn?> showPurchaseReturnDialog(BuildContext context, PurchaseOrder po) =>
    showDialog<PurchaseReturn>(context: context, builder: (_) => _ReturnDialog(po: po));

class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog({required this.po});
  final PurchaseOrder po;
  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  PurchaseOrder? _po;
  final Map<int, TextEditingController> _qty = {};
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The full order carries each line's returned quantity.
    PurchaseOrderService.instance.get(widget.po.id).then((full) {
      if (!mounted) return;
      setState(() {
        _po = full;
        for (final i in full.items) {
          _qty[i.id] = TextEditingController(text: '0');
        }
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = friendlyError(e));
    });
  }

  @override
  void dispose() {
    for (final c in _qty.values) { c.dispose(); }
    _reason.dispose();
    super.dispose();
  }

  int _q(int id) => int.tryParse(_qty[id]?.text.trim() ?? '') ?? 0;

  double get _total => (_po?.items ?? const <PurchaseOrderItem>[]).fold(0, (s, i) => s + _q(i.id) * i.unitCost);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date,
        firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final po = _po!;
    final lines = {for (final i in po.items) if (_q(i.id) > 0) i.id: _q(i.id)};
    final over = po.items.where((i) => _q(i.id) > i.returnable).toList();
    final problem = lines.isEmpty ? 'Enter how many of at least one item go back.'
        : over.isNotEmpty ? 'Only ${over.first.returnable} of ${over.first.itemName ?? 'that item'} can go back.'
        : null;
    if (problem != null) { setState(() => _error = problem); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final ret = await PurchaseOrderService.instance.createReturn(po.id, lines,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(), date: _date);
      PurchaseOrderService.cachedById.remove(po.id);
      if (mounted) Navigator.pop(context, ret);
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final po = _po;
    return ProcDialog(
      title: 'Purchase return · ${widget.po.poNumber}',
      icon: Symbols.undo,
      width: 600,
      body: po == null
          ? (_error != null
              ? Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5))
              : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${po.supplierName ?? 'Supplier'} · goods leave ${po.locationName ?? 'the store'} now. '
                  'If this purchase’s supplier invoice is already entered, the supplier’s account is credited too.',
                  style: AppTheme.bodySub.copyWith(fontSize: 12)),
              const SizedBox(height: 14),
              for (final i in po.items)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.itemName ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
                      Text('Received ${i.quantityReceived} · returned ${i.quantityReturned} · ${_amount(po.currency, i.unitCost)} each',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                    ])),
                    const SizedBox(width: 12),
                    SizedBox(width: 80, child: i.returnable > 0
                        ? CellField(controller: _qty[i.id]!, hint: 'Qty', keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))
                        : Text('Nothing left', textAlign: TextAlign.right, style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
                  ]),
                ),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 190, child: LabeledDateField(label: 'Return date', date: _date, onTap: _pickDate)),
                const SizedBox(width: 12),
                Expanded(child: LabeledTextField(label: 'Reason (optional)', controller: _reason, hint: 'Damaged, expired, wrong item…')),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Text('Total returned  ', style: AppTheme.bodySub),
                Text(_amount(po.currency, _total), style: AppTheme.monoSm.copyWith(fontSize: 15, color: context.pal.text)),
              ]),
            ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || po == null ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Record return'),
        ),
      ],
    );
  }
}
