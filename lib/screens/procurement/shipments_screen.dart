// Section 18 · Shipments list (design 1a). Procurement staff run shipments;
// CTO / MD / Sales Manager and department managers get the same list
// read-only. Flags and "what's blocking the next step" come from the API
// (ShipmentFlow), not from this screen.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/shipment.dart';
import '../../services/shipment_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'shipment_detail_screen.dart';
import 'shipment_forms.dart';
import 'shipment_settings_screen.dart';

Color shipmentFlagColor(BuildContext c, ShipmentFlag f) => switch (f) {
  ShipmentFlag.blocked => AppColors.coral,
  ShipmentFlag.action => AppColors.amber,
  ShipmentFlag.done => AppColors.green,
  ShipmentFlag.none => AppColors.cyan,
};

IconData directionIcon(String direction) => direction == 'export' ? Symbols.flight_takeoff : Symbols.flight_land;

class ShipmentsScreen extends StatefulWidget {
  const ShipmentsScreen({super.key, this.initialShipmentId});
  /// Opened from a shipment notification — jumps straight to that shipment.
  final int? initialShipmentId;
  @override
  State<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends State<ShipmentsScreen> {
  int _tab = 0; // active · needs action · done
  String _dir = 'all';
  String _q = '';
  ShipmentList? _data = ShipmentService.cachedList;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialShipmentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openId(widget.initialShipmentId!));
    }
  }

  Future<void> _load() async {
    try {
      final d = await ShipmentService.instance.list();
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  bool _inTab(Shipment s) => switch (_tab) {
    1 => s.flag == ShipmentFlag.action || s.flag == ShipmentFlag.blocked,
    2 => s.isDone,
    _ => !s.isDone,
  };

  List<Shipment> _rows(List<Shipment> all) {
    final q = _q.toLowerCase();
    return all.where((s) => _inTab(s) && (_dir == 'all' || s.direction == _dir) && (q.isEmpty ||
        s.reference.toLowerCase().contains(q) || s.description.toLowerCase().contains(q) ||
        (s.supplierName ?? '').toLowerCase().contains(q) || (s.poNumber ?? '').toLowerCase().contains(q) ||
        (s.departmentName ?? '').toLowerCase().contains(q))).toList();
  }

  Future<void> _openId(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: id)));
    _load();
  }

  Future<void> _new() async {
    final s = await showShipmentForm(context);
    if (s != null) _openId(s.id);
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShipmentSettingsScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final data = _data;
    if (data == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final all = data.shipments;
    final active = all.where((s) => !s.isDone).toList();
    final attention = all.where((s) => s.flag == ShipmentFlag.action || s.flag == ShipmentFlag.blocked).toList();
    final permit = active.where((s) => s.isImport && s.step >= 3 && s.step <= 5).toList();
    final atClearing = active.where((s) => s.isImport && s.step >= 6 && s.step <= 9).toList();

    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'Shipments',
          subtitle: '${all.length} shipment${all.length == 1 ? '' : 's'} · ${active.length} active · '
              '${attention.length} need${attention.length == 1 ? 's' : ''} action',
          actions: [
            if (!data.canManage) const ProcTag('Read-only', tone: ProcTone.violet),
            ProcButton(label: 'Settings', icon: Symbols.tune, onPressed: _settings),
            if (data.canManage) ProcButton(label: 'New shipment', icon: Symbols.add, tone: ProcTone.green, onPressed: _new),
          ],
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: [
            KpiStrip([
              KpiStripItem(Symbols.local_shipping, ProcTone.teal, 'Active', '${active.length}',
                  '${active.where((s) => s.isImport).length} import · ${active.where((s) => !s.isImport).length} export'),
              KpiStripItem(Symbols.report, ProcTone.coral, 'Needs action', '${attention.length}',
                  attention.isEmpty ? 'nothing blocked' : attention.map((s) => s.reference).take(2).join(' · '),
                  alarm: attention.any((s) => s.flag == ShipmentFlag.blocked)),
              KpiStripItem(Symbols.verified, ProcTone.amber, 'At TMDA', '${permit.length}', 'arrived, permit not yet issued'),
              KpiStripItem(Symbols.account_balance, ProcTone.violet, 'In clearance', '${atClearing.length}', 'with the clearing agent'),
            ]),
            if (attention.isNotEmpty) ...[
              const SizedBox(height: 14),
              NeedsActionPanel(subtitle: 'what blocks the next status', [
                for (final s in attention.take(6)) NeedsActionItem(
                  ref: s.reference,
                  tone: s.flag == ShipmentFlag.blocked ? ProcTone.coral : ProcTone.amber,
                  text: '${s.description} — ${s.flagReason ?? s.statusLabel}',
                  cta: s.flag == ShipmentFlag.action ? 'Add documents' : 'Open shipment',
                  onTap: () => _openId(s.id),
                ),
              ]),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ProcSegmented(options: ['Active · ${active.length}', 'Needs action · ${attention.length}', 'Done · ${all.length - active.length}'],
                  selected: _tab, onChanged: (i) => setState(() => _tab = i)),
              ProcSegmented(options: const ['All', 'Import', 'Export'],
                  selected: const ['all', 'import', 'export'].indexOf(_dir),
                  onChanged: (i) => setState(() => _dir = const ['all', 'import', 'export'][i])),
              ProcSearchField(hint: 'Reference, supplier, PO, department…', onChanged: (v) => setState(() => _q = v)),
            ]),
            const SizedBox(height: 14),
            _ShipmentTable(rows: _rows(all), onTap: (s) => _openId(s.id)),
          ]),
        )),
      ]),
    );
  }
}

class _ShipmentTable extends StatelessWidget {
  const _ShipmentTable({required this.rows, required this.onTap});
  final List<Shipment> rows;
  final ValueChanged<Shipment> onTap;

  List<Color> _segs(BuildContext c, Shipment s) =>
      StepBar.segments(c, total: s.lastStep, step: s.isDone ? s.lastStep + 1 : s.step, current: shipmentFlagColor(c, s.flag));

  String _party(Shipment s) => s.isImport
      ? [s.supplierName, s.poNumber].whereType<String>().join(' · ')
      : (s.outboundReason ?? '');

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
        child: Text('No shipments here.', textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900) return Column(children: [for (final s in rows) _card(context, s)]);
        Widget h(String s, {int flex = 0, double? w, TextAlign a = TextAlign.left}) {
          final x = Text(s.toUpperCase(), style: procCaps(context), textAlign: a);
          return w != null ? SizedBox(width: w, child: x) : Expanded(flex: flex, child: x);
        }
        const gap = SizedBox(width: 14);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border))),
            child: Row(children: [
              h('Reference', w: 130), gap, h('Shipment', flex: 22), gap, h('Status', flex: 16), gap,
              h('Department', w: 120), gap, h('Docs', w: 50), gap, h('Updated', w: 90, a: TextAlign.right),
            ]),
          ),
          for (final s in rows) InkWell(
            onTap: () => onTap(s),
            hoverColor: pal.surface2.withValues(alpha: 0.5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: s.flag == ShipmentFlag.blocked ? AppColors.coral.withValues(alpha: 0.05) : null,
                border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
              child: Row(children: [
                SizedBox(width: 130, child: Row(children: [
                  Icon(directionIcon(s.direction), size: 14, color: pal.textDim),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.reference, style: procMono(context, color: pal.text), overflow: TextOverflow.ellipsis)),
                ])),
                gap,
                Expanded(flex: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(s.description, style: AppTheme.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (s.manufacturerPaid) ...[const SizedBox(width: 6), const ProcTag('Manufacturer paid', tone: ProcTone.green, small: true)],
                  ]),
                  const SizedBox(height: 3),
                  Text('${freightLabel(s.freightMode)} · ${_party(s).isEmpty ? '—' : _party(s)}',
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                gap,
                Expanded(flex: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StepBar(_segs(context, s)),
                  const SizedBox(height: 6),
                  Text('${s.step}/${s.lastStep} · ${s.statusLabel}', overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySub.copyWith(fontSize: 11, color: s.flag == ShipmentFlag.none ? pal.text : shipmentFlagColor(context, s.flag))),
                ])),
                gap,
                SizedBox(width: 120, child: Text(s.departmentName ?? '—', overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
                gap,
                SizedBox(width: 50, child: Text('${s.docsUploaded}/${s.docsRequired}',
                    style: procMono(context, color: s.docsUploaded < s.docsRequired ? AppColors.amber : null))),
                gap,
                SizedBox(width: 90, child: Text(s.updatedAt == null ? '—' : formatDate(s.updatedAt!), textAlign: TextAlign.right,
                    style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
              ]),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _card(BuildContext context, Shipment s) {
    final pal = context.pal;
    return InkWell(
      onTap: () => onTap(s),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: s.flag == ShipmentFlag.blocked ? AppColors.coral.withValues(alpha: 0.05) : null,
            border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(directionIcon(s.direction), size: 14, color: pal.textDim),
            const SizedBox(width: 6),
            Expanded(child: Text(s.reference, style: procMono(context, color: pal.text))),
            Text('${s.docsUploaded}/${s.docsRequired} docs',
                style: procMono(context, color: s.docsUploaded < s.docsRequired ? AppColors.amber : pal.textMute)),
          ]),
          const SizedBox(height: 6),
          Text(s.description, style: AppTheme.bodySm),
          if (s.manufacturerPaid) const Padding(padding: EdgeInsets.only(top: 4),
              child: ProcTag('Manufacturer paid', tone: ProcTone.green, small: true)),
          Text([freightLabel(s.freightMode), s.departmentName, _party(s)].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          const SizedBox(height: 8),
          StepBar(_segs(context, s)),
          const SizedBox(height: 5),
          Text('${s.step}/${s.lastStep} · ${s.statusLabel}',
              style: AppTheme.bodySub.copyWith(fontSize: 11, color: s.flag == ShipmentFlag.none ? pal.text : shipmentFlagColor(context, s.flag))),
          if (s.flagReason != null && !s.isDone)
            Text(s.flagReason!, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        ]),
      ),
    );
  }
}
