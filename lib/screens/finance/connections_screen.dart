import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/creditor.dart';
import '../../services/creditor_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';

/// Everything connected to one record — requisition, LPO, approvals,
/// payments (and the account they left), supplier invoice, shipment,
/// store receipt, sale, machine, customer invoice — with one timeline and
/// the ledger entries they posted. Tap any record to follow the web from it.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, required this.type, required this.id});
  final String type;
  final int id;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Connections? _web;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final w = await CreditorService.instance.connections(widget.type, widget.id);
      if (mounted) setState(() => _web = w);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _follow(ConnNode n) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConnectionsScreen(type: n.type, id: n.id)));

  static IconData _icon(String type) => switch (type) {
    'purchase_requisition' => Symbols.assignment,
    'purchase_order' => Symbols.shopping_cart,
    'supplier_payment' || 'payment' => Symbols.payments,
    'vendor_bill' || 'invoice' => Symbols.receipt_long,
    'supplier' || 'vendor' => Symbols.factory,
    'vendor_fee' => Symbols.local_shipping,
    'shipment' => Symbols.flight_land,
    'tender' => Symbols.gavel,
    'inventory_item' => Symbols.inventory_2,
    'serial_number' => Symbols.qr_code_2,
    'stock_movement' => Symbols.swap_vert,
    'location' => Symbols.warehouse,
    'sales_order' => Symbols.request_quote,
    'hospital' => Symbols.local_hospital,
    'delivery_job' => Symbols.local_shipping,
    'creditor_opening' => Symbols.account_balance,
    _ => Symbols.description,
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final w = _web;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: w == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              final pad = c.maxWidth < 560 ? 16.0 : 24.0;
              final header = _header(context, w);
              final records = _records(context, w);
              final timeline = _timeline(context, w);
              final ledger = w.ledger == null ? null : _ledger(context, w.ledger!);
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: EdgeInsets.all(pad), children: [
                  header,
                  const SizedBox(height: 16),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: records),
                      const SizedBox(width: 16),
                      Expanded(flex: 6, child: timeline),
                    ])
                  else ...[records, const SizedBox(height: 16), timeline],
                  if (ledger != null) ...[const SizedBox(height: 16), ledger],
                ]),
              );
            })),
    );
  }

  Widget _header(BuildContext context, Connections w) {
    final s = w.subject;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Back'))),
      Row(children: [
        Icon(_icon(s.type), size: 22, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${connectionTypeLabel(s.type)} · ${s.title}', style: AppTheme.pageTitle.copyWith(fontSize: 21), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (s.subtitle != null) Text(s.subtitle!, style: AppTheme.bodySub, maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
      const SizedBox(height: 6),
      Text('${w.nodes.length - 1} connected record${w.nodes.length == 2 ? '' : 's'} · ${w.timeline.length} events'
          '${w.truncated ? ' · showing the nearest records only' : ''}',
          style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim)),
    ]);
  }

  Widget _panel(BuildContext context, String title, IconData icon, Widget child) => Container(
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Row(children: [
        Icon(icon, size: 15, color: AppColors.teal),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5))),
      ])),
      child,
    ]),
  );

  Widget _records(BuildContext context, Connections w) {
    final rel = w.relations;
    final others = w.nodes.where((n) => n.depth > 0).toList()
      ..sort((a, b) => a.depth != b.depth ? a.depth.compareTo(b.depth) : a.type.compareTo(b.type));
    return _panel(context, 'Connected records', Symbols.hub, others.isEmpty
        ? Padding(padding: const EdgeInsets.all(16), child: Text('Nothing linked yet.', style: AppTheme.bodySub))
        : Column(children: [
            for (final n in others)
              InkWell(
                onTap: () => _follow(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
                  child: Row(children: [
                    SizedBox(width: 14.0 * (n.depth - 1).clamp(0, 3)),
                    Icon(_icon(n.type), size: 16, color: context.pal.textMute),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${connectionTypeLabel(n.type)} · ${n.title}', style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text([
                        if (rel[n.key] != null && rel[n.key]!.isNotEmpty) rel[n.key]!,
                        if (n.subtitle != null) n.subtitle!,
                        if (n.status != null) n.status!.replaceAll('_', ' '),
                        if (n.date != null) formatDate(n.date!),
                      ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ])),
                    if (n.amount != null && n.currency != null) ...[
                      const SizedBox(width: 8),
                      Text(money(n.amount!, n.currency!), style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.text)),
                    ],
                    const SizedBox(width: 4),
                    Icon(Symbols.chevron_right, size: 16, color: context.pal.textDim),
                  ]),
                ),
              ),
          ]));
  }

  Widget _timeline(BuildContext context, Connections w) {
    final byKey = {for (final n in w.nodes) n.key: n};
    return _panel(context, 'Timeline', Symbols.timeline, w.timeline.isEmpty
        ? Padding(padding: const EdgeInsets.all(16), child: Text('No recorded events yet.', style: AppTheme.bodySub))
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(children: [
              for (final (i, e) in w.timeline.indexed)
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: 18, child: Column(children: [
                    Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(color: AppColors.teal, shape: BoxShape.circle)),
                    if (i < w.timeline.length - 1) Expanded(child: Container(width: 1.5, color: context.pal.divider)),
                  ])),
                  const SizedBox(width: 8),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.action, style: AppTheme.bodySm.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text([
                        '${connectionTypeLabel(byKey[e.node]?.type ?? '')} ${e.title}',
                        if (e.actor != null) e.role != null ? '${e.actor} (${e.role!.replaceAll('_', ' ').toUpperCase()})' : e.actor!,
                        if (e.at != null) '${formatDate(e.at!)} ${formatTime(e.at!)}',
                      ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (e.detail != null && e.detail!.trim().isNotEmpty)
                        Text(e.detail!, style: AppTheme.bodySub.copyWith(fontSize: 11, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ]),
                  )),
                ])),
            ]),
          ));
  }

  Widget _ledger(BuildContext context, List<ConnLeg> legs) => _panel(context, 'In the books', Symbols.account_balance, legs.isEmpty
      ? Padding(padding: const EdgeInsets.all(16), child: Text('Nothing posted to the ledger yet.', style: AppTheme.bodySub))
      : Column(children: [
          for (final l in legs)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.pal.divider))),
              child: Row(children: [
                SizedBox(width: 86, child: Text(l.date == null ? '' : formatDate(l.date!), style: AppTheme.monoXs.copyWith(fontSize: 10.5))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.account, style: AppTheme.bodySm.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${l.reference}${l.description != null ? ' · ${l.description}' : ''}',
                      style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                SizedBox(width: 120, child: Text('${l.isDebit ? 'Dr' : 'Cr'} ${money(l.amount, 'TZS')}', textAlign: TextAlign.right,
                    style: AppTheme.monoXs.copyWith(fontSize: 11, color: l.isDebit ? context.pal.text : AppColors.teal))),
              ]),
            ),
        ]));
}
