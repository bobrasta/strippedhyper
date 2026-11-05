// Home for the Tendering & Logistics department (procurement manager and
// logistics officers). Built from the same pieces as their own pages —
// ProcPageHeader, KpiStrip, NeedsActionPanel, StepBar, NeST tender rows —
// so the dashboard reads like a summary of Shipments, NeST Tenders,
// Tenders & Contracts, Device Registrations, stock and vendor fees.
//
// Each source loads on its own and only when the user's role can open that
// page, so one failing request (or a page they don't have) leaves the rest
// of the dashboard working.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userNameNotifier, userRoleNotifier, allowedScreenKeys;
import '../../models/inventory_item.dart';
import '../../models/nest_tender.dart';
import '../../models/shipment.dart';
import '../../models/tender.dart';
import '../../models/vendor.dart';
import '../../services/inventory_service.dart';
import '../../services/nest_service.dart';
import '../../services/shipment_service.dart';
import '../../services/tender_service.dart';
import '../../services/vendor_fee_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/procurement/nest_widgets.dart';
import '../../widgets/procurement/proc_widgets.dart';
import '../procurement/nest_tender_detail_screen.dart';
import '../procurement/shipment_detail_screen.dart';
import '../procurement/shipment_forms.dart';
import '../procurement/shipments_screen.dart' show shipmentFlagColor, directionIcon;
import '../procurement/tender_detail_screen.dart';
import '../procurement/tender_forms.dart';
import '../procurement/tenders_screen.dart' show deadlineColor;

class ProcurementDashboardScreen extends StatefulWidget {
  const ProcurementDashboardScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;
  @override
  State<ProcurementDashboardScreen> createState() => _ProcurementDashboardScreenState();
}

class _ProcurementDashboardScreenState extends State<ProcurementDashboardScreen> {
  // Seeded from the list screens' caches so a revisit opens instantly.
  ShipmentList? _shipments = ShipmentService.cachedList;
  TenderList? _tenders = TenderService.cachedList;
  NestDashboard? _nest = NestService.cachedDashboard;
  List<NestTender>? _nestClosing;
  List<DeviceRegistration>? _devices;
  List<InventoryItem>? _lowStock;
  List<VendorFee>? _fees;

  late final Set<String>? _allowed = allowedScreenKeys(userRoleNotifier.value);
  bool _has(String key) => _allowed == null || _allowed.contains(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      if (_has('shipments')) ShipmentService.instance.list().then((v) {
        if (mounted) setState(() => _shipments = v);
      }).catchError((_) {}),
      if (_has('tenders')) ...[
        TenderService.instance.list().then((v) {
          if (mounted) setState(() => _tenders = v);
        }).catchError((_) {}),
        // peek: looking at the dashboard must not reset "new since last visit".
        NestService.instance.dashboard(peek: true).then((v) {
          if (mounted) setState(() => _nest = v);
        }).catchError((_) {}),
        NestService.instance.list(const NestFilter(closingWithin: 7)).then((v) {
          if (mounted) setState(() => _nestClosing = v.rows);
        }).catchError((_) {}),
        TenderService.instance.devices().then((v) {
          if (mounted) setState(() => _devices = v.$1);
        }).catchError((_) {}),
      ],
      if (_has('inventory')) InventoryService.instance.list(lowStock: true).then((v) {
        if (mounted) setState(() => _lowStock = v.where((i) => i.isActive).toList());
      }).catchError((_) {}),
      if (_has('vendor_fees')) VendorFeeService.instance.fees().then((v) {
        if (mounted) setState(() => _fees = v);
      }).catchError((_) {}),
    ]);
  }

  void _go(String key) => widget.onNavigateTo?.call(key);

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _newShipment() async {
    final s = await showShipmentForm(context);
    if (s != null) _push(ShipmentDetailScreen(shipmentId: s.id));
  }

  Future<void> _newTender() async {
    final t = await showTenderForm(context);
    if (t != null) _push(TenderDetailScreen(tenderId: t.id));
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  List<Shipment> get _activeShipments => [...?_shipments?.shipments.where((s) => !s.isDone)]
    ..sort((a, b) {
      int rank(Shipment s) => switch (s.flag) { ShipmentFlag.blocked => 0, ShipmentFlag.action => 1, _ => 2 };
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (b.updatedAt ?? DateTime(2000)).compareTo(a.updatedAt ?? DateTime(2000));
    });

  List<Shipment> get _shipmentAttention =>
      _activeShipments.where((s) => s.flag == ShipmentFlag.action || s.flag == ShipmentFlag.blocked).toList();

  List<Tender> get _openTenders => [...?_tenders?.tenders.where((t) => !t.isClosedOrLost)]
    ..sort((a, b) {
      if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
      final da = a.nextDeadline?.due, db = b.nextDeadline?.due;
      if (da == null) return db == null ? b.id.compareTo(a.id) : 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

  List<Tender> get _tendersThisWeek => _openTenders.where((t) {
    final d = t.nextDeadline?.daysLeft;
    return d != null && d >= 0 && d <= 7;
  }).toList();

  /// Registrations that stop imports soon: expired, renewal due, or a renewal
  /// deadline the API already marks as soon / overdue.
  List<DeviceRegistration> get _devicesDue => [...?_devices?.where((d) =>
      d.status == 'expired' || d.status == 'renewal_due' ||
      d.renewal?.state == DeadlineState.overdue || d.renewal?.state == DeadlineState.soon ||
      d.renewal?.state == DeadlineState.dueToday)]
    ..sort((a, b) => (a.renewal?.daysLeft ?? -999).compareTo(b.renewal?.daysLeft ?? -999));

  List<VendorFee> get _feesOpen => [...?_fees?.where((f) =>
      f.status == VendorFeeStatus.pendingManager || f.status == VendorFeeStatus.pendingReceipt || f.status == VendorFeeStatus.rejected)];

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final now = DateTime.now();
    final first = userNameNotifier.value.trim().split(' ').first;
    final needs = _needsActionItems(context);

    final panels = <Widget>[
      if (_has('tenders')) _nestPanel(context),
      if (_has('tenders')) _tendersPanel(context),
      if (_has('shipments')) _shipmentsPanel(context),
      if (_has('tenders')) _devicesPanel(context),
      if (_has('inventory')) _stockPanel(context),
      if (_has('vendor_fees')) _feesPanel(context),
    ];

    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: first.isEmpty ? 'Tendering & Logistics' : 'Hello, $first',
          subtitle: 'Tendering & Logistics · ${formatDate(now)} · '
              '${needs.isEmpty ? 'nothing needs action' : '${needs.length} item${needs.length == 1 ? '' : 's'} need${needs.length == 1 ? 's' : ''} action'}',
          accent: AppColors.green,
          actions: [
            if (_has('tenders')) ProcButton(label: 'NeST tenders', icon: Symbols.travel_explore, onPressed: () => _go('nest_tenders')),
            if (_tenders?.canManage == true) ProcButton(label: 'New tender', icon: Symbols.add, onPressed: _newTender),
            if (_shipments?.canManage == true)
              ProcButton(label: 'New shipment', icon: Symbols.add, tone: ProcTone.green, onPressed: _newShipment),
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(builder: (context, box) {
            final pad = box.maxWidth < 600 ? 16.0 : 24.0;
            return ListView(padding: EdgeInsets.fromLTRB(pad, 14, pad, 24), children: [
              KpiStrip(_kpis(context)),
              if (needs.isNotEmpty) ...[
                const SizedBox(height: 14),
                NeedsActionPanel(needs.take(8).toList(), subtitle: 'most urgent first, across tenders, shipments and registrations'),
              ],
              const SizedBox(height: 14),
              _columns(box.maxWidth, panels),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (key, icon, label) in const [
                  ('shipments', Symbols.flight_land, 'Shipments'),
                  ('nest_tenders', Symbols.travel_explore, 'NeST Tenders'),
                  ('tenders', Symbols.gavel, 'Tenders & Contracts'),
                  ('tender_devices', Symbols.verified, 'Device Registrations'),
                  ('tmda_permits', Symbols.verified_user, 'TMDA Permits'),
                  ('clearing_fees', Symbols.receipt_long, 'Clearing Fees'),
                  ('vendor_fees', Symbols.local_shipping, 'Vendors & Delivery'),
                  ('inventory', Symbols.inventory_2, 'Inventory'),
                ])
                  if (_has(_gate(key))) ProcButton(label: label, icon: icon, onPressed: () => _go(key)),
              ]),
            ]);
          }),
        )),
      ]),
    );
  }

  /// Sub-pages share their parent's gate (see AppShell._gatedKey).
  static String _gate(String key) => switch (key) {
    'nest_tenders' || 'tender_devices' => 'tenders',
    'tmda_permits' || 'clearing_fees' => 'shipments',
    _ => key,
  };

  Widget _columns(double width, List<Widget> panels) {
    if (panels.isEmpty) return const SizedBox.shrink();
    if (width < 900) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < panels.length; i++) ...[if (i > 0) const SizedBox(height: 12), panels[i]],
      ]);
    }
    final left = [for (var i = 0; i < panels.length; i += 2) panels[i]];
    final right = [for (var i = 1; i < panels.length; i += 2) panels[i]];
    Widget col(List<Widget> l) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < l.length; i++) ...[if (i > 0) const SizedBox(height: 12), l[i]],
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: col(left)),
      const SizedBox(width: 12),
      Expanded(child: col(right)),
    ]);
  }

  List<KpiStripItem> _kpis(BuildContext context) {
    final nest = _nest;
    final active = _activeShipments;
    final attention = _shipmentAttention;
    final flagged = _openTenders.where((t) => t.flagged).toList();
    final week = _tendersThisWeek;
    return [
      if (_has('tenders')) KpiStripItem(Symbols.travel_explore, ProcTone.green, 'NeST closing ≤ 3 days',
          nest == null ? '—' : '${nest.closing3}', nest == null ? '' : '${nest.openRelevant} open relevant',
          alarm: (nest?.closing3 ?? 0) > 0),
      if (_has('tenders')) KpiStripItem(Symbols.alarm, ProcTone.amber, 'Tender deadlines',
          _tenders == null ? '—' : '${week.length}',
          flagged.isNotEmpty ? '${flagged.length} flagged overdue' : 'in the next 7 days', alarm: flagged.isNotEmpty),
      if (_has('shipments')) KpiStripItem(Symbols.local_shipping, ProcTone.teal, 'Shipments active',
          _shipments == null ? '—' : '${active.length}',
          attention.isEmpty ? 'nothing blocked' : '${attention.length} need${attention.length == 1 ? 's' : ''} action',
          alarm: attention.any((s) => s.flag == ShipmentFlag.blocked)),
      if (_has('tenders')) KpiStripItem(Symbols.verified, ProcTone.violet, 'Registrations due',
          _devices == null ? '—' : '${_devicesDue.length}', _devices == null ? '' : '${_devices!.where((d) => d.status == 'registered').length} registered',
          alarm: _devicesDue.any((d) => d.status == 'expired')),
      if (_has('inventory')) KpiStripItem(Symbols.inventory_2, ProcTone.coral, 'Low stock',
          _lowStock == null ? '—' : '${_lowStock!.length}', 'at or below reorder level'),
      if (!_has('inventory') && _has('vendor_fees')) KpiStripItem(Symbols.receipt_long, ProcTone.amber, 'Fees need receipts',
          _fees == null ? '—' : '${_feesOpen.length}', 'vendors & delivery'),
    ];
  }

  List<NeedsActionItem> _needsActionItems(BuildContext context) {
    final coral = <NeedsActionItem>[], amber = <NeedsActionItem>[];
    for (final t in _tenders?.needsAction ?? const <Tender>[]) {
      final d = t.nextDeadline;
      final hot = t.flagged || d?.state == DeadlineState.overdue;
      (hot ? coral : amber).add(NeedsActionItem(
        when: d?.relative.replaceAll(' overdue', ' over'),
        ref: t.tenderNumber,
        tone: hot ? ProcTone.coral : ProcTone.amber,
        text: t.flagged
            ? 'Performance security or contract signing is overdue — ${t.title}'
            : d == null ? t.title : '${d.label} — ${t.title}',
        cta: 'Open tender',
        onTap: () => _push(TenderDetailScreen(tenderId: t.id)),
      ));
    }
    for (final s in _shipmentAttention) {
      final hot = s.flag == ShipmentFlag.blocked;
      (hot ? coral : amber).add(NeedsActionItem(
        when: hot ? 'blocked' : 'action',
        ref: s.reference,
        tone: hot ? ProcTone.coral : ProcTone.amber,
        text: '${s.description} — ${s.flagReason ?? s.statusLabel}',
        cta: s.flag == ShipmentFlag.action ? 'Add documents' : 'Open shipment',
        onTap: () => _push(ShipmentDetailScreen(shipmentId: s.id)),
      ));
    }
    for (final d in _devicesDue) {
      final hot = d.status == 'expired' || d.renewal?.state == DeadlineState.overdue;
      (hot ? coral : amber).add(NeedsActionItem(
        when: d.renewal?.relative.replaceAll(' overdue', ' over'),
        ref: d.registrationNumber ?? d.brandName,
        tone: hot ? ProcTone.coral : ProcTone.amber,
        text: 'TMDA registration ${d.statusLabel.toLowerCase()} — ${[d.brandName, d.model].whereType<String>().join(' ')}',
        cta: 'Registrations',
        onTap: () => _go('tender_devices'),
      ));
    }
    return [...coral, ...amber];
  }

  // ── Panels ────────────────────────────────────────────────────────────────

  Widget _loading() => const Padding(padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));

  Widget _empty(BuildContext context, String s) => Padding(padding: const EdgeInsets.all(16),
      child: Text(s, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim)));

  /// "All →" link in a panel header, like the Needs-action row links.
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

  Widget _nestPanel(BuildContext context) {
    final pal = context.pal;
    final rows = _nestClosing;
    final d = _nest;
    return ProcPanel(
      title: 'NeST · closing this week', icon: Symbols.travel_explore, iconColor: AppColors.green,
      trailing: _more('All', 'nest_tenders'),
      footer: d == null ? null : Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Pipeline', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        for (final p in nestPipeline.where((p) => p != 'skipped' && p != 'new'))
          ProcTag('${nestPipelineLabel(p)} · ${d.byPipeline[p] ?? 0}', tone: nestPipelineTone(p), small: true),
        if (d.newSinceVisit > 0) ProcTag('${d.newSinceVisit} new since last visit', tone: ProcTone.teal, small: true),
      ]),
      child: rows == null
          ? _loading()
          : rows.isEmpty
              ? _empty(context, 'No relevant NeST tender closes in the next 7 days.')
              : Column(children: [
                  for (final t in rows.take(5))
                    NestTenderRow(tender: t, onTap: () => _push(NestTenderDetailScreen(tenderId: t.id))),
                ]),
    );
  }

  Widget _tendersPanel(BuildContext context) {
    final pal = context.pal;
    final rows = _openTenders;
    return ProcPanel(
      title: 'Tenders & contracts', icon: Symbols.gavel,
      trailing: _more('All', 'tenders'),
      child: _tenders == null
          ? _loading()
          : rows.isEmpty
              ? _empty(context, 'No open tenders.')
              : Column(children: [
                  for (final t in rows.take(5)) Builder(builder: (context) {
                    final nd = t.nextDeadline;
                    final cur = t.flagged ? AppColors.coral
                        : t.status == 'preparing_bid' ? AppColors.amber
                        : t.status == 'delivered' ? AppColors.green : AppColors.cyan;
                    return _row(
                      context,
                      highlight: t.flagged,
                      onTap: () => _push(TenderDetailScreen(tenderId: t.id)),
                      top: [
                        Expanded(child: Text(t.tenderNumber, style: procMono(context, color: pal.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 10),
                        Text(nd == null ? '—' : nd.relative, style: procMono(context,
                            color: nd == null ? pal.textDim : deadlineColor(context, nd.state))),
                      ],
                      title: t.title,
                      sub: [t.entity?.name, if (nd != null) nd.label, if (t.value != null) tshShort(t.value!)].whereType<String>().join(' · '),
                      bar: StepBar.segments(context, total: tenderFlow.length, step: t.step, current: cur),
                      status: t.flagged ? '${t.statusLabel} · overdue' : t.statusLabel,
                      statusColor: t.flagged ? AppColors.coral : pal.textMute,
                    );
                  }),
                ]),
    );
  }

  Widget _shipmentsPanel(BuildContext context) {
    final pal = context.pal;
    final rows = _activeShipments;
    final permit = rows.where((s) => s.isImport && s.step >= 3 && s.step <= 5).length;
    final clearing = rows.where((s) => s.isImport && s.step >= 6 && s.step <= 9).length;
    return ProcPanel(
      title: 'Shipments in progress', icon: Symbols.local_shipping,
      trailing: _more('All', 'shipments'),
      footer: _shipments == null ? null : Wrap(spacing: 6, runSpacing: 6, children: [
        ProcTag('${rows.where((s) => s.isImport).length} import', small: true),
        ProcTag('${rows.where((s) => !s.isImport).length} export', small: true),
        ProcTag('$permit at TMDA', tone: ProcTone.amber, small: true),
        ProcTag('$clearing in clearance', tone: ProcTone.violet, small: true),
      ]),
      child: _shipments == null
          ? _loading()
          : rows.isEmpty
              ? _empty(context, 'No shipments in progress.')
              : Column(children: [
                  for (final s in rows.take(5)) _row(
                    context,
                    highlight: s.flag == ShipmentFlag.blocked,
                    onTap: () => _push(ShipmentDetailScreen(shipmentId: s.id)),
                    top: [
                      Icon(directionIcon(s.direction), size: 14, color: pal.textDim),
                      const SizedBox(width: 6),
                      Expanded(child: Text(s.reference, style: procMono(context, color: pal.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Text('${s.docsUploaded}/${s.docsRequired} docs',
                          style: procMono(context, color: s.docsUploaded < s.docsRequired ? AppColors.amber : pal.textMute)),
                    ],
                    title: s.description,
                    sub: [freightLabel(s.freightMode), s.departmentName,
                      s.isImport ? s.supplierName : s.outboundReason].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                    bar: StepBar.segments(context, total: s.lastStep, step: s.step, current: shipmentFlagColor(context, s.flag)),
                    status: '${s.step}/${s.lastStep} · ${s.statusLabel}',
                    statusColor: s.flag == ShipmentFlag.none ? pal.textMute : shipmentFlagColor(context, s.flag),
                  ),
                ]),
    );
  }

  Widget _devicesPanel(BuildContext context) {
    final pal = context.pal;
    final all = _devices;
    final shown = [..._devicesDue, ...?all?.where((d) => d.status != 'registered' && !_devicesDue.contains(d))];
    return ProcPanel(
      title: 'Device registrations', icon: Symbols.verified,
      trailing: _more('All', 'tender_devices'),
      child: all == null
          ? _loading()
          : shown.isEmpty
              ? _empty(context, all.isEmpty ? 'No devices registered with TMDA yet.' : 'Every registration is current.')
              : Column(children: [
                  for (final d in shown.take(5)) Builder(builder: (context) {
                    final tone = switch (d.status) {
                      'expired' => ProcTone.coral,
                      'renewal_due' => ProcTone.amber,
                      'registered' => ProcTone.green,
                      'under_review' || 'submitted' => ProcTone.teal,
                      _ => ProcTone.neutral,
                    };
                    return _row(
                      context,
                      highlight: d.status == 'expired',
                      onTap: () => _go('tender_devices'),
                      top: [
                        Expanded(child: Text([d.brandName, d.model].whereType<String>().join(' '),
                            style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 10),
                        ProcTag(d.statusLabel, tone: tone, small: true),
                      ],
                      sub: [
                        d.registrationNumber ?? 'not registered yet',
                        if (d.riskClass != null) 'Class ${d.riskClass}',
                        if (d.renewal?.due != null) 'renew ${formatDate(d.renewal!.due!)} (${d.renewal!.relative})'
                        else if (d.checklistTotal > 0) 'dossier ${d.checklistDone}/${d.checklistTotal}',
                      ].join(' · '),
                      subColor: d.renewal != null && d.renewal!.state == DeadlineState.overdue ? AppColors.coral : pal.textDim,
                    );
                  }),
                ]),
    );
  }

  Widget _stockPanel(BuildContext context) {
    final pal = context.pal;
    final items = [...?_lowStock]..sort((a, b) => (a.stockQty - a.reorderLevel).compareTo(b.stockQty - b.reorderLevel));
    return ProcPanel(
      title: 'Low stock', icon: Symbols.inventory_2,
      trailing: _more('Inventory', 'inventory'),
      child: _lowStock == null
          ? _loading()
          : items.isEmpty
              ? _empty(context, 'Nothing is below its reorder level.')
              : Column(children: [
                  for (final i in items.take(6)) _row(
                    context,
                    onTap: () => _go('inventory'),
                    top: [
                      Expanded(child: Text(i.name, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Text('${i.stockQty} / ${i.reorderLevel}',
                          style: procMono(context, color: i.stockQty == 0 ? AppColors.coral : AppColors.amber)),
                    ],
                    sub: [i.sku, i.category, if (i.supplier.isNotEmpty) i.supplier].join(' · '),
                    subColor: pal.textDim,
                  ),
                ]),
    );
  }

  Widget _feesPanel(BuildContext context) {
    final pal = context.pal;
    final open = _feesOpen;
    final ready = _fees?.where((f) => f.status == VendorFeeStatus.readyForPayment).length ?? 0;
    return ProcPanel(
      title: 'Vendor fees', icon: Symbols.receipt_long,
      trailing: _more('All', 'vendor_fees'),
      footer: _fees == null ? null : ProcNote('$ready ready for payment with finance · ${open.length} waiting on receipts or rejected',
          icon: Symbols.payments),
      child: _fees == null
          ? _loading()
          : open.isEmpty
              ? _empty(context, 'No fee is waiting on a receipt.')
              : Column(children: [
                  for (final f in open.take(5)) _row(
                    context,
                    highlight: f.status == VendorFeeStatus.rejected,
                    onTap: () => _go('vendor_fees'),
                    top: [
                      Expanded(child: Text(f.vendorName ?? 'Vendor', style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Text(tshShort(f.billedAmount), style: procMono(context, color: pal.text)),
                    ],
                    sub: f.status == VendorFeeStatus.rejected
                        ? 'Rejected — ${f.paymentBlockReason ?? f.description}'
                        : '${f.description} · receipt needed',
                    subColor: f.status == VendorFeeStatus.rejected ? AppColors.coral : pal.textDim,
                  ),
                ]),
    );
  }

  /// One list row inside a panel: a top line, optional title / sub line and
  /// an optional step bar with its status — the list rows of the module pages.
  Widget _row(BuildContext context, {
    required List<Widget> top, String? title, String? sub, Color? subColor,
    List<Color>? bar, String? status, Color? statusColor, bool highlight = false, VoidCallback? onTap,
  }) {
    final pal = context.pal;
    return InkWell(
      onTap: onTap,
      hoverColor: pal.surface2.withValues(alpha: 0.5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: highlight ? AppColors.coral.withValues(alpha: 0.05) : null,
          border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: top),
          if (title != null && title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(title, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (sub != null && sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11, color: subColor ?? pal.textDim),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (bar != null) ...[
            const SizedBox(height: 8),
            StepBar(bar),
            if (status != null) Padding(padding: const EdgeInsets.only(top: 5),
                child: Text(status, style: AppTheme.bodySub.copyWith(fontSize: 11, color: statusColor ?? pal.textMute),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ]),
      ),
    );
  }
}
