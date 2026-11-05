// Section 18 registers across all import shipments: TMDA permits and the
// clearing fees (Section 16 vendor fees). Both read the same /shipments list
// — the permit and fee live on each shipment — and open the shipment to act.

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
import '../finance/vendor_fees_screen.dart' show attachVendorReceipt;

String _tsh(int v) => 'TSh ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

DateTime? _d(Map<String, dynamic>? m, String k) => m?[k] == null ? null : DateTime.tryParse(m![k] as String);

/// Shared load/refresh/open plumbing for both registers.
abstract class _RegisterState<T extends StatefulWidget> extends State<T> {
  ShipmentList? data = ShipmentService.cachedList;
  String? error;
  int tab = 0;
  String q = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await ShipmentService.instance.list();
      if (mounted) setState(() { data = d; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> open(Shipment s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: s.id)));
    load();
  }

  bool matches(Shipment s, List<String?> extra) {
    final x = q.toLowerCase();
    return x.isEmpty || [s.reference, s.description, s.supplierName, ...extra].any((v) => (v ?? '').toLowerCase().contains(x));
  }

  Widget page({required String title, required String subtitle, required List<Widget> children}) {
    final pal = context.pal;
    if (data == null) {
      return error != null ? ErrorView(message: error!, onRetry: load) : const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(title: title, subtitle: subtitle,
            actions: [if (!data!.canManage) const ProcTag('Read-only', tone: ProcTone.violet)]),
        Expanded(child: RefreshIndicator(
          onRefresh: load,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 14, 24, 24), children: children),
        )),
      ]),
    );
  }

  Widget table({required List<(String, int?, double?)> columns, required List<Shipment> rows,
      required List<Widget> Function(Shipment) cells, required String empty, Color? Function(Shipment)? tint}) {
    final pal = context.pal;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
        child: Text(empty, textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      );
    }
    Widget sized(int? flex, double? w, Widget child) => w != null ? SizedBox(width: w, child: child) : Expanded(flex: flex ?? 1, child: child);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 900;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!narrow) Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border))),
            child: Row(children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                sized(columns[i].$2, columns[i].$3, Text(columns[i].$1.toUpperCase(), style: procCaps(context))),
              ],
            ]),
          ),
          for (final s in rows) InkWell(
            onTap: () => open(s),
            hoverColor: pal.surface2.withValues(alpha: 0.5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: tint?.call(s), border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
              child: narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final c in cells(s)) Padding(padding: const EdgeInsets.only(bottom: 3), child: c),
                    ])
                  : Row(children: [
                      for (final (i, c) in cells(s).indexed) ...[
                        if (i > 0) const SizedBox(width: 14),
                        sized(columns[i].$2, columns[i].$3, c),
                      ],
                    ]),
            ),
          ),
        ]);
      }),
    );
  }

  Widget ref(Shipment s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(s.reference, style: procMono(context, color: context.pal.text)),
    Text(s.description, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textDim)),
  ]);

  Widget small(String t, {Color? color}) =>
      Text(t, overflow: TextOverflow.ellipsis, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: color ?? context.pal.textMute));
}

// ── TMDA permits ────────────────────────────────────────────────────────────

class TmdaPermitsScreen extends StatefulWidget {
  const TmdaPermitsScreen({super.key});
  @override
  State<TmdaPermitsScreen> createState() => _TmdaPermitsScreenState();
}

class _TmdaPermitsScreenState extends _RegisterState<TmdaPermitsScreen> {
  @override
  Widget build(BuildContext context) {
    // Imports of medical goods only: non-medical goods need no TMDA permit.
    final imports = (data?.shipments ?? []).where((s) => s.isImport && !s.nonMedical).toList();
    final issued = imports.where((s) => _d(s.tmda, 'issued_at') != null).toList();
    final applied = imports.where((s) => s.tmda?['application_ref'] != null && _d(s.tmda, 'issued_at') == null).toList();
    // Arrived (step ≥3) with nothing applied for yet — the clock is running.
    final toApply = imports.where((s) => !s.isDone && s.step >= 3 && s.tmda?['application_ref'] == null).toList();
    final now = DateTime.now();
    final issuedThisMonth = issued.where((s) {
      final d = _d(s.tmda, 'issued_at')!;
      return d.year == now.year && d.month == now.month;
    }).length;
    final lists = [
      [...toApply, ...applied],
      toApply,
      applied,
      issued,
    ];
    final rows = lists[tab].where((s) => matches(s, [s.tmda?['application_ref'] as String?])).toList();

    return page(
      title: 'TMDA permits',
      subtitle: 'Import permits across all shipments · ${applied.length} awaiting TMDA · ${toApply.length} not applied yet',
      children: [
        KpiStrip([
          KpiStripItem(Symbols.report, ProcTone.coral, 'Not applied', '${toApply.length}', 'arrived, no application yet',
              alarm: toApply.isNotEmpty),
          KpiStripItem(Symbols.hourglass_top, ProcTone.amber, 'Awaiting TMDA', '${applied.length}',
              applied.isEmpty ? 'nothing pending' : 'oldest ${_oldestWait(applied)} days'),
          KpiStripItem(Symbols.verified, ProcTone.green, 'Issued this month', '$issuedThisMonth', '${issued.length} issued in total'),
          KpiStripItem(Symbols.flight_land, ProcTone.teal, 'Import shipments', '${imports.length}', '${imports.where((s) => !s.isDone).length} active'),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ProcSegmented(options: ['Open · ${toApply.length + applied.length}', 'Not applied · ${toApply.length}',
            'Awaiting TMDA · ${applied.length}', 'Issued · ${issued.length}'], selected: tab, onChanged: (i) => setState(() => tab = i)),
          ProcSearchField(hint: 'Shipment, application ref…', onChanged: (v) => setState(() => q = v)),
        ]),
        const SizedBox(height: 14),
        table(
          columns: const [('Shipment', 24, null), ('Application ref', null, 150), ('Applied', null, 110), ('Issued', null, 110),
            ('Waiting', null, 90), ('Permit file', null, 100), ('Shipment status', 14, null)],
          rows: rows,
          empty: 'No permits here.',
          tint: (s) => toApply.contains(s) ? AppColors.coral.withValues(alpha: 0.05) : null,
          cells: (s) {
            final appliedAt = _d(s.tmda, 'applied_at');
            final issuedAt = _d(s.tmda, 'issued_at');
            final waiting = appliedAt == null ? null : (issuedAt ?? now).difference(appliedAt).inDays;
            return [
              ref(s),
              Text(s.tmda?['application_ref'] as String? ?? 'Not applied', style: procMono(context,
                  color: s.tmda?['application_ref'] == null ? AppColors.coral : context.pal.text)),
              small(appliedAt == null ? '—' : formatDate(appliedAt)),
              small(issuedAt == null ? '—' : formatDate(issuedAt), color: issuedAt == null ? null : AppColors.green),
              small(waiting == null ? '—' : '$waiting day${waiting == 1 ? '' : 's'}${issuedAt == null ? '' : ' (done)'}',
                  color: issuedAt == null && (waiting ?? 0) > 14 ? AppColors.amber : null),
              small(s.tmda?['permit_uploaded'] == true ? 'Uploaded' : '—', color: s.tmda?['permit_uploaded'] == true ? AppColors.green : null),
              small('${s.step}/${s.lastStep} · ${s.statusLabel}'),
            ];
          },
        ),
      ],
    );
  }

  int _oldestWait(List<Shipment> l) => l
      .map((s) => _d(s.tmda, 'applied_at'))
      .whereType<DateTime>()
      .map((d) => DateTime.now().difference(d).inDays)
      .fold(0, (a, b) => a > b ? a : b);
}

// ── Clearing fees ───────────────────────────────────────────────────────────

class ClearingFeesScreen extends StatefulWidget {
  const ClearingFeesScreen({super.key});
  @override
  State<ClearingFeesScreen> createState() => _ClearingFeesScreenState();
}

class _ClearingFeesScreenState extends _RegisterState<ClearingFeesScreen> {
  @override
  Widget build(BuildContext context) {
    // Manufacturer-paid shipments have no fee for HyperMed to record: their own tab, at TSh 0.
    final imports = (data?.shipments ?? []).where((s) => s.isImport && !s.manufacturerPaid).toList();
    final manufacturer = (data?.shipments ?? []).where((s) => s.isImport && s.manufacturerPaid).toList();
    final withFee = imports.where((s) => s.clearingFee != null).toList();
    // Assessment received (control number issued) but no fee recorded yet.
    final missing = imports.where((s) => s.clearingFee == null && s.step >= 7).toList();
    // Clearing fees are paid first: "awaiting receipt" is any fee whose receipt can still go on.
    final awaitingReceipt = withFee.where((s) => s.clearingFee!.canAttachReceipt).toList();
    final awaitingApproval = withFee.where((s) => s.clearingFee!.status == 'ready_for_payment').toList();
    final paid = withFee.where((s) => s.clearingFee!.paid).toList();
    int sum(List<Shipment> l) => l.fold(0, (a, s) => a + s.clearingFee!.billed);
    final lists = [
      [...missing, ...withFee.where((s) => !s.clearingFee!.paid && s.clearingFee!.status != 'rejected')],
      missing,
      awaitingReceipt,
      awaitingApproval,
      paid,
      manufacturer,
    ];
    final rows = lists[tab].where((s) => matches(s, [s.clearingFee?.vendorName, s.controlNumber])).toList();

    return page(
      title: 'Clearing fees',
      subtitle: 'Clearing agents\' charges on import shipments · Section 16 vendor fees: no receipt, no payment',
      children: [
        KpiStrip([
          KpiStripItem(Symbols.report, ProcTone.coral, 'Not recorded', '${missing.length}', 'assessed, no fee yet', alarm: missing.isNotEmpty),
          KpiStripItem(Symbols.receipt_long, ProcTone.amber, 'Awaiting receipt', '${awaitingReceipt.length}', _tsh(sum(awaitingReceipt))),
          KpiStripItem(Symbols.gavel, ProcTone.violet, 'Awaiting Director', '${awaitingApproval.length}', _tsh(sum(awaitingApproval))),
          KpiStripItem(Symbols.payments, ProcTone.green, 'Paid', '${paid.length}', _tsh(sum(paid))),
          KpiStripItem(Symbols.volunteer_activism, ProcTone.teal, 'Manufacturer paid', '${manufacturer.length}', _tsh(0)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ProcSegmented(options: ['Open · ${lists[0].length}', 'Not recorded · ${missing.length}', 'Awaiting receipt · ${awaitingReceipt.length}',
            'Awaiting Director · ${awaitingApproval.length}', 'Paid · ${paid.length}', 'Manufacturer paid · ${manufacturer.length}'], selected: tab, onChanged: (i) => setState(() => tab = i)),
          ProcSearchField(hint: 'Shipment, agent, control no…', onChanged: (v) => setState(() => q = v)),
        ]),
        const SizedBox(height: 10),
        const ProcNote('The fee is paid first; the clearing agent\'s receipt is attached when the shipment reaches "Arrived at HQ", '
            'with the Swissport storage & handling charges. Finance verifies it in Vendors & Delivery. '
            'Until the fee is paid the shipment waits at "Assessment received".'),
        const SizedBox(height: 14),
        table(
          columns: const [('Shipment', 22, null), ('Clearing agent', 14, null), ('Control no.', null, 120), ('Billed', null, 120),
            ('Receipts', null, 150), ('Status', 16, null)],
          rows: rows,
          empty: 'No clearing fees here.',
          tint: (s) => missing.contains(s) ? AppColors.coral.withValues(alpha: 0.05) : null,
          cells: (s) {
            final f = s.clearingFee;
            if (s.manufacturerPaid) {
              return [
                ref(s),
                small('—'),
                Text('—', style: procMono(context, color: context.pal.text)),
                Text(_tsh(0), style: procMono(context, color: context.pal.text)),
                small('—'),
                small('Paid by ${s.paidBy ?? 'the manufacturer'} · no cost to HyperMed', color: AppColors.green),
              ];
            }
            return [
              ref(s),
              small(f?.vendorName ?? '—'),
              Text(s.controlNumber ?? '—', style: procMono(context, color: context.pal.text)),
              Text(f == null ? '—' : _tsh(f.billed), style: procMono(context, color: context.pal.text)),
              small(f == null ? '—' : '${_tsh(f.receiptsTotal)}${f.receiptUploaded ? (f.financeVerified ? ' · verified' : ' · unverified') : ''}',
                  color: f != null && f.receiptsTotal == f.billed && f.financeVerified ? AppColors.green : null),
              Row(children: [
                Flexible(child: small(f == null ? 'Not recorded — open the shipment to record it' : f.paid ? 'Paid' : '${f.statusLabel}${f.blockReason == null ? '' : ' · ${f.blockReason}'}',
                    color: f == null ? AppColors.coral : f.paid ? AppColors.green : f.status == 'rejected' ? AppColors.coral : AppColors.amber)),
                // Waiting on the receipt: attach it once the goods are at HQ (user, 2026-11-02).
                if (data!.canManage && f != null && f.canAttachReceipt && s.step == s.lastStep)
                  TextButton(onPressed: () async {
                    if (await attachVendorReceipt(context, f.id, issuerHint: f.vendorName, amountHint: f.billed - f.receiptsTotal)) load();
                  }, child: const Text('Attach')),
              ]),
            ];
          },
        ),
      ],
    );
  }
}
