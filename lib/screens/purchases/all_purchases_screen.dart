import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/purchase_order.dart';
import '../../services/purchase_order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/period_filter.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/sliver_table.dart';
import '../inventory/purchase_orders_screen.dart' show showNewPurchaseOrder, showPurchaseOrderDetail, purchaseStatusColor;
import 'purchase_returns_screen.dart' show showPurchaseReturnDialog;

/// List purchases — Clickhuduma's purchase list: every purchase (a purchase
/// order here, Clickhuduma's own imported as CH-…) with its purchase and
/// payment status, grand total, what's still due and who added it, and the
/// row action menu (right-click a row, long-press on a phone).
class AllPurchasesScreen extends StatefulWidget {
  const AllPurchasesScreen({super.key, this.openNew = false});
  /// Purchases → Add purchase: open the new-purchase form straight away.
  final bool openNew;

  @override
  State<AllPurchasesScreen> createState() => _AllPurchasesScreenState();
}

// Columns fit the window (no sideways scroll): see AllSalesScreen.
typedef _Col = ({String label, int flex, bool num, double minWidth, String? sort});

const List<_Col> _cols = [
  (label: 'Date', flex: 8, num: false, minWidth: 0, sort: 'date'),
  (label: 'Reference No', flex: 10, num: false, minWidth: 0, sort: 'number'),
  (label: 'Location', flex: 10, num: false, minWidth: 1150, sort: 'location'),
  (label: 'Supplier', flex: 18, num: false, minWidth: 0, sort: 'supplier'),
  (label: 'Purchase Status', flex: 11, num: false, minWidth: 0, sort: 'status'),
  (label: 'Payment Status', flex: 8, num: false, minWidth: 860, sort: 'payment'),
  (label: 'Grand Total', flex: 11, num: true, minWidth: 0, sort: 'total'),
  (label: 'Payment Due', flex: 11, num: true, minWidth: 0, sort: 'due'),
  (label: 'Added By', flex: 10, num: false, minWidth: 980, sort: 'addedBy'),
];

// Purchase-status chips: Clickhuduma's ordered / pending / received, in
// this system's own steps (the approval chain sits between draft and sent).
const _stages = [
  ('draft', 'Draft', {'draft'}),
  ('approval', 'In approval', {'pending_sales_manager', 'pending_director_review', 'pending_payment_initiation', 'pending_director_final', 'approved'}),
  ('ordered', 'Ordered', {'sent', 'acknowledged'}),
  ('partial', 'Partly received', {'partially_received'}),
  ('received', 'Received', {'received'}),
  ('closed', 'Rejected / cancelled', {'rejected', 'cancelled'}),
];

String _stageOf(PurchaseOrder p) => _stages.firstWhere((s) => s.$3.contains(p.status), orElse: () => _stages.first).$1;

/// Clickhuduma's payment status: paid / partial / due ('—' once the order is off).
String? _payOf(PurchaseOrder p) {
  if (p.status == 'cancelled' || p.status == 'rejected') return null;
  return switch (p.paymentStatus) { 'paid' => 'paid', 'partial' => 'partial', _ => 'due' };
}

(String, Color) _payLabel(BuildContext context, String? s) => switch (s) {
  'paid'    => ('Paid', AppColors.green),
  'partial' => ('Partial', AppColors.blue),
  'due'     => ('Due', AppColors.amber),
  _         => ('—', context.pal.textDim),
};

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

class _AllPurchasesScreenState extends State<AllPurchasesScreen> {
  Period _period = Period.defaultPeriod;
  List<PurchaseOrder> _all = [];
  Timer? _hoverTimer;
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String? _stage, _pay, _supplier, _location;
  static const _batch = 100;
  int _showCount = _batch;
  String _sortKey = 'date';
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    final cached = PurchaseOrderService.cachedDefaultList;
    if (cached != null) {
      _all = cached;
      _loading = false;
    }
    _load();
    if (widget.openNew) WidgetsBinding.instance.addPostFrameCallback((_) => _addPurchase());
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
      final data = await PurchaseOrderService.instance.list(period: _period);
      // Drop cached full orders the reload shows are out of date.
      for (final p in data) {
        final c = PurchaseOrderService.cachedById[p.id];
        if (c != null && (c.status != p.status || c.amountPaid != p.amountPaid || c.totalAmount != p.totalAmount)) {
          PurchaseOrderService.cachedById.remove(p.id);
        }
      }
      if (mounted) setState(() { _all = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<PurchaseOrder> _rows({bool withStage = true}) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _all.where((p) {
      if (withStage && _stage != null && _stageOf(p) != _stage) return false;
      if (_pay != null && _payOf(p) != _pay) return false;
      if (_supplier != null && p.supplierName != _supplier) return false;
      if (_location != null && p.locationName != _location) return false;
      if (q.isNotEmpty &&
          !p.poNumber.toLowerCase().contains(q) &&
          !(p.supplierName ?? '').toLowerCase().contains(q) &&
          !(p.notes ?? '').toLowerCase().contains(q)) {
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
      _sortAsc = const {'number', 'location', 'supplier', 'status', 'payment', 'addedBy'}.contains(key);
    }
  });

  int _compare(PurchaseOrder a, PurchaseOrder b) {
    int t(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
    final c = switch (_sortKey) {
      'number'   => t(a.poNumber, b.poNumber),
      'location' => t(a.locationName ?? '', b.locationName ?? ''),
      'supplier' => t(a.supplierName ?? '', b.supplierName ?? ''),
      'status'   => t(a.statusLabel, b.statusLabel),
      'payment'  => t(_payOf(a) ?? '', _payOf(b) ?? ''),
      'total'    => a.totalAmount.compareTo(b.totalAmount),
      'due'      => a.paymentDue.compareTo(b.paymentDue),
      'addedBy'  => t(a.orderedByName ?? '', b.orderedByName ?? ''),
      _          => a.createdAt.compareTo(b.createdAt),
    };
    final r = c != 0 ? c : a.id.compareTo(b.id);
    return _sortAsc ? r : -r;
  }

  // ── Row actions (Clickhuduma's menu) ─────────────────────────────────────

  List<PopupMenuEntry<String>> _menuItems(PurchaseOrder p) {
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
    return [
      item('view', Symbols.visibility, 'View'),
      item('print', Symbols.print, 'Print'),
      item('edit', Symbols.edit, 'Edit', enabled: p.status == 'draft' || p.status == 'rejected'),
      item('submit', Symbols.send, 'Submit for approval', enabled: p.status == 'draft'),
      item('cancel', Symbols.cancel, 'Cancel purchase', enabled: !const {'received', 'cancelled', 'rejected'}.contains(p.status)),
      const PopupMenuDivider(),
      item('return', Symbols.undo, 'Purchase Return', enabled: p.canReturn),
    ];
  }

  Future<void> _openMenu(PurchaseOrder p, Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<String>(
      context: context,
      color: context.pal.surface1,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: _menuItems(p),
    );
    if (v != null && mounted) _run(v, p);
  }

  Future<void> _view(PurchaseOrder p) async {
    if (await showPurchaseOrderDetail(context, p.id, preview: p)) _load();
  }

  Future<void> _run(String action, PurchaseOrder p) async {
    switch (action) {
      case 'view':
        await _view(p);
      case 'edit':
        final full = await PurchaseOrderService.instance.get(p.id);
        if (!mounted) return;
        if (await showNewPurchaseOrder(context, editing: full) != null) _load();
      case 'print':
        await downloadPdf(context, () => PurchaseOrderService.instance.pdfBytes(p.id), '${p.poNumber}.pdf');
      case 'submit':
        try {
          await PurchaseOrderService.instance.submitForApproval(p.id);
          if (mounted) showSuccessToast(context, '${p.poNumber} sent for approval.');
          _load();
        } catch (e) {
          if (mounted) showErrorToast(context, e);
        }
      case 'cancel':
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text('Cancel ${p.poNumber}?'),
          content: const Text('The purchase is marked cancelled and stays on the list.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => Navigator.pop(c, true), child: const Text('Cancel purchase')),
          ],
        ));
        if (ok != true) return;
        try {
          await PurchaseOrderService.instance.cancel(p.id);
          if (mounted) showSuccessToast(context, '${p.poNumber} cancelled.');
          _load();
        } catch (e) {
          if (mounted) showErrorToast(context, e);
        }
      case 'return':
        final ret = await showPurchaseReturnDialog(context, p);
        if (ret == null || !mounted) return;
        showSuccessToast(context, '${ret.returnNumber} recorded — stock taken out of ${ret.locationName ?? 'the store'}.');
        _load();
    }
  }

  Future<void> _addPurchase() async {
    final created = await showNewPurchaseOrder(context);
    if (created == null || !mounted) return;
    showSuccessToast(context, 'Purchase ${created.poNumber} saved as a draft — submit it for approval.');
    await _load();
    if (mounted) _view(created);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final suppliers = {for (final p in _all) ?p.supplierName}.toList()..sort();
    final locations = {for (final p in _all) ?p.locationName}.toList()..sort();

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 24.0;
      final phone = isPhoneWidth(cst.maxWidth);
      final tableW = cst.maxWidth - 2 * pad;
      final cols = [for (final c in _cols) if (tableW >= c.minWidth) c];
      Widget select(String? value, List<String> options, String all, double width, ValueChanged<String?> onChanged) => SizedBox(
        width: width,
        child: DropdownFieldBox<String?>(
          value: options.contains(value) ? value : null,
          active: value != null,
          items: [null, ...options].map((v) => DropdownMenuItem(value: v, child: Text(v ?? all, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { onChanged(v); _resetPage(); },
        ),
      );
      final supplierFilter = select(_supplier, suppliers, 'All suppliers', 190, (v) => _supplier = v);
      final locationFilter = select(_location, locations, 'All locations', 160, (v) => _location = v);
      final payFilter = SizedBox(width: 150, child: DropdownFieldBox<String?>(
        value: _pay,
        active: _pay != null,
        items: [null, 'paid', 'partial', 'due'].map((v) => DropdownMenuItem(value: v,
            child: Text(v == null ? 'Any payment' : _payLabel(context, v).$1))).toList(),
        onChanged: (v) { _pay = v; _resetPage(); },
      ));
      final period = PeriodSelector(value: _period, onChanged: (p) { setState(() { _period = p; _showCount = _batch; }); _load(); });
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) PhonePageHeader(
          title: 'Purchases',
          subtitle: 'Tap a purchase to open it · long-press for its actions',
          primary: PageAction(label: 'Add purchase', shortLabel: 'Add', icon: Symbols.add, onPressed: _addPurchase),
          search: SearchField(hint: 'Reference, supplier, note…', controller: _searchCtrl, onChanged: (_) => _resetPage()),
          filters: [period, supplierFilter, locationFilter, payFilter],
          bottom: PhoneScrollRow(spacing: 8, children: _stageChips(context)),
        )
        else Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Purchases', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('Right-click a purchase for its actions · click a column to sort', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              DenseFields(child: SearchField(width: 240, hint: 'Reference, supplier, note…', controller: _searchCtrl, onChanged: (_) => _resetPage())),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _addPurchase, icon: const Icon(Symbols.add, size: 16), label: const Text('Add purchase')),
            ]),
            const SizedBox(height: 12),
            DenseFields(child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ..._stageChips(context),
              const SizedBox(width: 6),
              period,
              supplierFilter,
              locationFilter,
              payFilter,
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
                            child: Center(child: Text('No purchases found', style: AppTheme.bodySub)))),
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
                      emptyText: 'No purchases found',
                      totalCount: rows.length,
                      loadStep: _batch,
                      onLoadMore: () => setState(() => _showCount += _batch),
                    ),
                  ])),
      ]);
    });
  }

  Widget _card(BuildContext context, PurchaseOrder p) {
    final (pay, payColor) = _payLabel(context, _payOf(p));
    return GestureDetector(
      onLongPressStart: (d) => _openMenu(p, d.globalPosition),
      child: PhoneRecordCard(
        title: p.supplierName ?? '—',
        subtitle: '${p.poNumber} · ${formatDate(p.createdAt)}',
        badge: PhonePill(p.statusLabel, purchaseStatusColor(p.status)),
        meta: [if (_payOf(p) != null) pay, if (p.orderedByName != null) 'by ${p.orderedByName}',
            if (p.paymentDue > 0 && _payOf(p) != null) 'due ${_amount(p.currency, p.paymentDue)}'],
        amount: _amount(p.currency, p.totalAmount),
        onTap: () => _view(p),
      ),
    );
  }

  // Totals by currency: shillings lead, any foreign-currency purchases follow.
  Widget _summary(BuildContext context, List<PurchaseOrder> rows, {bool phone = false}) {
    final live = rows.where((p) => _payOf(p) != null).toList();
    Map<String, double> sum(double Function(PurchaseOrder) f) {
      final m = <String, double>{};
      for (final p in live) {
        final c = p.currency.toUpperCase();
        m[c] = (m[c] ?? 0) + f(p);
      }
      return m;
    }
    String lead(Map<String, double> m) => _amount('TZS', m['TZS'] ?? 0);
    String others(Map<String, double> m) => [for (final e in m.entries) if (e.key != 'TZS' && e.value != 0) _amount(e.key, e.value)].join(' · ');
    final total = sum((p) => p.totalAmount), paid = sum((p) => p.amountPaid),
        due = sum((p) => p.paymentDue), returned = sum((p) => p.returnedAmount);
    final returnedCount = live.where((p) => p.returnedAmount > 0).length;

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
      kpi('TOTAL PURCHASES', lead(total), context.pal.text,
          [ '${live.length} purchase${live.length == 1 ? '' : 's'} · ${_period.label}', if (others(total).isNotEmpty) others(total)].join(' · ')),
      const SizedBox(width: 12),
      kpi('TOTAL PAID', lead(paid), AppColors.green, others(paid).isEmpty ? 'paid to suppliers' : others(paid)),
      const SizedBox(width: 12),
      kpi('PAYMENT DUE', lead(due), AppColors.amber, others(due).isEmpty ? 'still to pay suppliers' : others(due)),
      const SizedBox(width: 12),
      kpi('PURCHASE RETURNS', lead(returned), AppColors.coral,
          returnedCount == 0 ? 'nothing sent back' : '$returnedCount purchase${returnedCount == 1 ? '' : 's'} with returns'),
    ];
    if (phone) {
      return PhoneStatGrid(spacing: 10, children: [
        for (final k in kpis) if (k is Expanded) k.child,
      ]);
    }
    return Row(children: kpis);
  }

  // Purchase-status chips (they filter the table); counts ignore the chip itself.
  List<Widget> _stageChips(BuildContext context) {
    final base = _rows(withStage: false);
    final counts = <String, int>{};
    for (final p in base) {
      final s = _stageOf(p);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    Color colorOf(String stage) => switch (stage) {
      'draft' => context.pal.textMute,
      'approval' => AppColors.amber,
      'ordered' => AppColors.blue,
      'partial' => AppColors.violet,
      'received' => AppColors.green,
      _ => context.pal.textDim,
    };
    void pick(String? s) { _stage = _stage == s ? null : s; _resetPage(); }
    return [
      _Chip(label: 'All', count: base.length, active: _stage == null, color: AppColors.teal, onTap: () => pick(null)),
      for (final (k, l, _) in _stages)
        if ((counts[k] ?? 0) > 0 || _stage == k)
          _Chip(label: l, count: counts[k] ?? 0, active: _stage == k, color: colorOf(k), onTap: () => pick(k)),
    ];
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

  Widget _row(BuildContext context, List<_Col> cols, PurchaseOrder p) {
    final statusColor = purchaseStatusColor(p.status);
    final (pay, payColor) = _payLabel(context, _payOf(p));
    final cell = AppTheme.bodySm.copyWith(fontSize: 12.5);
    final money = AppTheme.monoSm.copyWith(fontSize: 12);
    Text t(String? s, {TextStyle? style}) => Text(s == null || s.trim().isEmpty ? '—' : s,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? cell);
    Widget pill(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppTheme.bodySub.copyWith(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );

    Widget cellFor(_Col c) => switch (c.label) {
      'Date' => t(formatDate(p.createdAt)),
      'Reference No' => t(p.poNumber, style: money.copyWith(fontWeight: FontWeight.w600)),
      'Location' => t(p.locationName),
      'Supplier' => Tooltip(message: p.supplierName ?? '', child: t(p.supplierName)),
      'Purchase Status' => pill(p.statusLabel, statusColor),
      'Payment Status' => _payOf(p) == null ? t(null) : pill(pay, payColor),
      'Grand Total' => Tooltip(
          message: p.returnedAmount > 0 ? '${_amount(p.currency, p.returnedAmount)} returned' : _amount(p.currency, p.totalAmount),
          child: t(_amount(p.currency, p.totalAmount), style: money)),
      'Payment Due' => t(_payOf(p) == null ? null : _amount(p.currency, p.paymentDue),
          style: money.copyWith(color: p.paymentDue > 0 ? AppColors.amber : context.pal.textDim)),
      'Added By' => t(p.orderedByName),
      _ => const SizedBox(),
    };

    // Resting the pointer on a row starts fetching the full order, so View
    // opens with its lines and payments already loaded.
    return MouseRegion(
      onEnter: (_) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 150), () {
          if (!PurchaseOrderService.cachedById.containsKey(p.id)) PurchaseOrderService.instance.get(p.id).ignore();
        });
      },
      onExit: (_) => _hoverTimer?.cancel(),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _openMenu(p, d.globalPosition),
        onLongPressStart: (d) => _openMenu(p, d.globalPosition),
        child: InkWell(
          onTap: () => _view(p),
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
