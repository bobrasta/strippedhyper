// Home for the storekeeper (main Dashboard, UnifiedDashboardScreen's role
// delegation): stock at a glance, what is waiting on the store, recent
// movements and where the stock value sits — one call to GET
// /dashboard/store. Built from the same pieces as the Tendering & Logistics
// dashboard (ProcPageHeader, KpiStrip, NeedsActionPanel, ProcPanel).

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userNameNotifier;
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/procurement/proc_widgets.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;
  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  // Kept for the session so a revisit opens instantly, then refreshes.
  static Map<String, dynamic>? _cached;
  Map<String, dynamic>? _d = _cached;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/dashboard/store');
      final d = Map<String, dynamic>.from(ApiClient.unwrap(res) as Map);
      _cached = d;
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _go(String key) => widget.onNavigateTo?.call(key);

  Map<String, dynamic> _map(String k) => Map<String, dynamic>.from(_d?[k] as Map? ?? const {});
  List<Map<String, dynamic>> _list(String k) =>
      [for (final r in (_d?[k] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final first = userNameNotifier.value.trim().split(' ').first;
    final needs = _needs();
    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: first.isEmpty ? 'Store' : 'Hello, $first',
          subtitle: 'Store · ${formatDate(DateTime.now())} · '
              '${_d == null ? 'loading' : needs.isEmpty ? 'nothing needs action' : '${needs.length} item${needs.length == 1 ? '' : 's'} need${needs.length == 1 ? 's' : ''} action'}',
          accent: AppColors.teal,
          actions: [
            ProcButton(label: 'Purchase orders', icon: Symbols.receipt_long, onPressed: () => _go('inventory_orders')),
            ProcButton(label: 'Record movement', icon: Symbols.swap_vert, tone: ProcTone.green, onPressed: () => _go('inventory_movements')),
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(builder: (context, box) {
            final pad = box.maxWidth < 600 ? 16.0 : 24.0;
            return ListView(padding: EdgeInsets.fromLTRB(pad, 14, pad, 24), children: [
              if (_error != null && _d == null) _errorBox(context)
              else if (_d == null) const Padding(padding: EdgeInsets.all(40),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
              else ...[
                KpiStrip(_kpis()),
                if (needs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  NeedsActionPanel(needs.take(8).toList(), subtitle: 'stock-out requests, purchase orders to receive and empty shelves'),
                ],
                const SizedBox(height: 14),
                _columns(box.maxWidth, [
                  _lowStockPanel(context),
                  _receivePanel(context),
                  _movementsPanel(context),
                  _valuePanel(context),
                  _categoryPanel(context),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (key, icon, label) in const [
                    ('inventory_items', Symbols.list_alt, 'Items'),
                    ('inventory_movements', Symbols.swap_vert, 'Movements'),
                    ('inventory_requisitions', Symbols.assignment, 'Requisitions'),
                    ('inventory_orders', Symbols.receipt_long, 'Purchase Orders'),
                    ('inventory_locations', Symbols.warehouse, 'Locations'),
                  ])
                    ProcButton(label: label, icon: icon, onPressed: () => _go(key)),
                ]),
              ],
            ]);
          }),
        )),
      ]),
    );
  }

  Widget _errorBox(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      Text(_error!, textAlign: TextAlign.center, style: AppTheme.bodySub),
      const SizedBox(height: 10),
      ProcButton(label: 'Try again', icon: Symbols.refresh, onPressed: _load),
    ]),
  );

  List<KpiStripItem> _kpis() {
    final k = _map('kpis'), w = _map('waiting');
    final low = _int(k['low_stock']), out = _int(k['out_of_stock']);
    return [
      KpiStripItem(Symbols.inventory_2, ProcTone.teal, 'Stock value', tshShort(_int(k['stock_value'])),
          '${_fmtInt(_int(k['units']))} units at cost'),
      KpiStripItem(Symbols.list_alt, ProcTone.green, 'Items in stock', _fmtInt(_int(k['in_stock'])),
          '$out out of stock · ${_fmtInt(_int(k['items']))} items'),
      KpiStripItem(Symbols.warning, ProcTone.coral, 'Low stock', '$low',
          'at or below reorder level · ${_int(w['requisitions_open'])} open requisition${_int(w['requisitions_open']) == 1 ? '' : 's'}',
          alarm: low > 0),
      KpiStripItem(Symbols.local_shipping, ProcTone.amber, 'To receive', '${_int(w['pos_to_receive'])}',
          '${_int(w['stock_out_pending'])} stock-out request${_int(w['stock_out_pending']) == 1 ? '' : 's'} pending',
          alarm: _int(w['stock_out_pending']) > 0),
    ];
  }

  List<NeedsActionItem> _needs() {
    if (_d == null) return const [];
    final coral = <NeedsActionItem>[], amber = <NeedsActionItem>[];
    for (final s in _list('stock_out_pending')) {
      amber.add(NeedsActionItem(
        ref: s['type'] == 'write_off' ? 'Write-off' : 'Stock out',
        text: '${s['qty']} × ${s['item'] ?? 'item'} — requested by ${s['requested_by'] ?? '—'}'
            '${s['location'] == null ? '' : ' · ${s['location']}'}',
        cta: 'Movements',
        onTap: () => _go('inventory_movements'),
      ));
    }
    final today = DateUtils.dateOnly(DateTime.now());
    for (final p in _list('pos_to_receive')) {
      final exp = DateTime.tryParse('${p['expected'] ?? ''}');
      final late = exp != null && exp.isBefore(today);
      (late ? coral : amber).add(NeedsActionItem(
        when: exp == null ? null : late ? '${today.difference(exp).inDays} d late' : formatDate(exp),
        ref: '${p['po_number']}',
        tone: late ? ProcTone.coral : ProcTone.amber,
        text: 'Receive ${p['lines']} line${p['lines'] == 1 ? '' : 's'} from ${p['supplier'] ?? 'supplier'}',
        cta: 'Receive',
        onTap: () => _go('inventory_orders'),
      ));
    }
    // Empty shelves after the store's own work (POs, stock-out requests);
    // the Low stock panel lists the rest.
    final empty = <NeedsActionItem>[];
    for (final i in _list('low_stock').where((i) => _int(i['qty']) <= 0).take(3)) {
      empty.add(NeedsActionItem(
        ref: '${i['sku']}',
        tone: ProcTone.coral,
        text: '${i['name']} is out of stock (reorder level ${i['reorder_level']})',
        cta: 'Requisition',
        onTap: () => _go('inventory_requisitions'),
      ));
    }
    return [...coral, ...amber, ...empty];
  }

  // ── Panels ────────────────────────────────────────────────────────────────

  Widget _columns(double width, List<Widget> panels) {
    if (width < 900) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < panels.length; i++) ...[if (i > 0) const SizedBox(height: 12), panels[i]],
      ]);
    }
    Widget col(List<Widget> l) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < l.length; i++) ...[if (i > 0) const SizedBox(height: 12), l[i]],
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: col([for (var i = 0; i < panels.length; i += 2) panels[i]])),
      const SizedBox(width: 12),
      Expanded(child: col([for (var i = 1; i < panels.length; i += 2) panels[i]])),
    ]);
  }

  Widget _more(String label, String key) => InkWell(
    onTap: () => _go(key),
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.cyan)),
        const SizedBox(width: 4),
        const Icon(Symbols.arrow_forward, size: 12, color: AppColors.cyan),
      ]),
    ),
  );

  Widget _empty(BuildContext context, String s) => Padding(padding: const EdgeInsets.all(16),
      child: Text(s, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim)));

  Widget _row(BuildContext context, {required String title, required String right, String? sub,
      Color? rightColor, VoidCallback? onTap}) {
    final pal = context.pal;
    return InkWell(
      onTap: onTap,
      hoverColor: pal.surface2.withValues(alpha: 0.5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 10),
            Text(right, style: procMono(context, color: rightColor ?? pal.text)),
          ]),
          if (sub != null && sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
        ]),
      ),
    );
  }

  Widget _lowStockPanel(BuildContext context) {
    final rows = _list('low_stock');
    return ProcPanel(
      title: 'Low stock', icon: Symbols.warning, iconColor: AppColors.coral,
      trailing: _more('Items', 'inventory_items'),
      child: rows.isEmpty
          ? _empty(context, 'Nothing is at or below its reorder level.')
          : Column(children: [
              for (final i in rows) _row(context,
                  title: '${i['name']}',
                  right: '${i['qty']} / ${i['reorder_level']}${(i['uom'] ?? '') == '' ? '' : ' ${i['uom']}'}',
                  rightColor: _int(i['qty']) <= 0 ? AppColors.coral : AppColors.amber,
                  sub: '${i['sku']}',
                  onTap: () => _go('inventory_items')),
            ]),
    );
  }

  Widget _receivePanel(BuildContext context) {
    final rows = _list('pos_to_receive');
    return ProcPanel(
      title: 'Purchase orders to receive', icon: Symbols.local_shipping, iconColor: AppColors.amber,
      trailing: _more('All', 'inventory_orders'),
      child: rows.isEmpty
          ? _empty(context, 'No purchase order is waiting to be received.')
          : Column(children: [
              for (final p in rows) _row(context,
                  title: '${p['po_number']} · ${p['supplier'] ?? '—'}',
                  right: p['expected'] == null ? '—' : formatDate(DateTime.parse('${p['expected']}')),
                  sub: '${p['lines']} line${p['lines'] == 1 ? '' : 's'} · ${'${p['status']}'.replaceAll('_', ' ')}',
                  onTap: () => _go('inventory_orders')),
            ]),
    );
  }

  Widget _movementsPanel(BuildContext context) {
    final rows = _list('recent_movements');
    return ProcPanel(
      title: 'Recent stock movements', icon: Symbols.swap_vert,
      trailing: _more('All', 'inventory_movements'),
      child: rows.isEmpty
          ? _empty(context, 'No stock has moved yet.')
          : Column(children: [
              for (final m in rows) _row(context,
                  title: '${m['item'] ?? '—'}',
                  right: '${_int(m['qty']) > 0 ? '+' : ''}${_fmtInt(_int(m['qty']))}',
                  rightColor: _int(m['qty']) < 0 ? AppColors.coral : AppColors.green,
                  sub: [
                    '${m['type']}'.replaceAll('_', ' '),
                    if (m['location'] != null) '${m['location']}',
                    if (m['by'] != null) '${m['by']}',
                    if (DateTime.tryParse('${m['at']}') != null) formatDate(DateTime.parse('${m['at']}').toLocal()),
                  ].join(' · '),
                  onTap: () => _go('inventory_movements')),
            ]),
    );
  }

  Widget _valuePanel(BuildContext context) {
    final rows = _list('top_value');
    return ProcPanel(
      title: 'Biggest stock values', icon: Symbols.payments,
      trailing: _more('Items', 'inventory_items'),
      footer: const ProcNote('Check these counts first — a wrong count here moves the stock value the most.', icon: Symbols.fact_check),
      child: rows.isEmpty
          ? _empty(context, 'No stock on hand.')
          : Column(children: [
              for (final i in rows) _row(context,
                  title: '${i['name']}',
                  right: tshShort(_int(i['value'])),
                  sub: '${_fmtInt(_int(i['qty']))} × ${tshShort(_int(i['unit_cost']))}',
                  onTap: () => _go('inventory_items')),
            ]),
    );
  }

  Widget _categoryPanel(BuildContext context) {
    final rows = _list('by_category');
    final total = rows.fold<int>(0, (s, c) => s + _int(c['value']));
    final pal = context.pal;
    return ProcPanel(
      title: 'Stock value by category', icon: Symbols.category,
      child: rows.isEmpty
          ? _empty(context, 'No categories yet.')
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(children: [
                for (final c in rows) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${c['name']}', style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Text(tshShort(_int(c['value'])), style: procMono(context, color: pal.text)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total <= 0 ? 0 : _int(c['value']) / total,
                        minHeight: 5,
                        backgroundColor: pal.surface2,
                        color: AppColors.teal,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
    );
  }

  static String _fmtInt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
