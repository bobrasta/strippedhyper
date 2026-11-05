// Section 18 · shipment detail (designs 1b / 1d). Read-only for the CTO,
// MD, Sales Manager and department managers (18.4) — edit, upload and status
// actions are hidden, everything stays visible. The MD's one write action,
// approving the clearing payment, lives on the Section 16 vendor fee.

import '../../widgets/finance/connections_button.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/shipment.dart';
import '../../services/shipment_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'shipment_forms.dart';
import 'shipments_screen.dart' show shipmentFlagColor, directionIcon;
import '../finance/vendor_fees_screen.dart' show attachVendorReceipt;

String _tsh(int v) => 'TSh ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

// Role names are shown in ALL CAPS app-wide.
String _roleLabel(String role) => role.replaceAll('_', ' ').trim().toUpperCase();

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  return p.isEmpty ? '?' : (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

class ShipmentDetailScreen extends StatefulWidget {
  const ShipmentDetailScreen({super.key, required this.shipmentId});
  final int shipmentId;
  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  Shipment? _s;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ShipmentService.instance.get(widget.shipmentId);
      if (mounted) setState(() { _s = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _apply(Shipment? s) {
    if (s != null && mounted) setState(() => _s = s);
  }

  Future<void> _upload(ShipmentDocument d) async {
    final f = await pickShipmentFile(context);
    if (f == null) return;
    setState(() => _busy = 'up-${d.type}');
    try {
      _apply(await ShipmentService.instance.uploadDocument(_s!.id, d.type, f.path, f.name));
      if (mounted) showSuccessToast(context, '${d.label} uploaded.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _download(ShipmentDocument d) async {
    setState(() => _busy = 'dl-${d.type}');
    await downloadPdf(context, () => ShipmentService.instance.downloadDocument(_s!.id, d.type), d.fileName ?? '${d.type}.pdf');
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = _s;
    if (s == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: AppBar(backgroundColor: pal.bg),
          body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final readOnly = !s.canManage;
    final accent = shipmentFlagColor(context, s.flag);

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Shipments')))),
        ProcPageHeader(
          title: s.description,
          breadcrumb: ['Shipments', s.reference],
          accent: accent,
          tags: [
            ProcTag('${s.step}/${s.lastStep} · ${s.statusLabel}', tone: switch (s.flag) {
              ShipmentFlag.blocked => ProcTone.coral,
              ShipmentFlag.action => ProcTone.amber,
              ShipmentFlag.done => ProcTone.green,
              ShipmentFlag.none => ProcTone.teal,
            }),
            ProcTag(s.isImport ? 'Import' : 'Export', tone: ProcTone.violet),
            ProcTag(freightLabel(s.freightMode)),
            if (s.nonMedical) const ProcTag('Non-medical · documents optional', tone: ProcTone.green),
            if (s.manufacturerPaid) ProcTag('Paid by ${s.paidBy ?? 'manufacturer'}', tone: ProcTone.green),
            if (s.docsUploaded < s.docsRequired) ProcTag('Incomplete · ${s.docsUploaded}/${s.docsRequired} docs', tone: ProcTone.amber),
          ],
          actions: readOnly
              ? [ConnectionsButton(type: 'shipment', id: s.id, compact: true), const ProcTag('Read-only', tone: ProcTone.violet)]
              : [
                  ConnectionsButton(type: 'shipment', id: s.id, compact: true),
                  ProcButton(label: 'Edit', icon: Symbols.edit, onPressed: () async => _apply(await showShipmentForm(context, shipment: s))),
                  ProcButton(label: 'Update status', icon: Symbols.route, tone: ProcTone.green,
                      onPressed: () => _moveStatus(s)),
                ],
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: LayoutBuilder(builder: (context, box) {
          final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.nextBlockReason != null && !s.isDone) ...[
              ProcNote('Next: ${s.labelFor(s.step + 1)} — ${s.nextBlockReason}', icon: Symbols.block,
                  tone: s.flag == ShipmentFlag.blocked ? ProcTone.coral : ProcTone.amber),
              // Waiting on the clearing agent's receipt: attach it right here.
              if (_receiptAction(s, readOnly) case final action?) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: action)],
              const SizedBox(height: 14),
            ],
            _documents(context, s, readOnly),
            if (s.isImport) ...[const SizedBox(height: 14), if (!s.nonMedical) ...[_tmda(context, s), const SizedBox(height: 14)],
              s.manufacturerPaid ? _noCost(context, s) : _fee(context, s, readOnly),
              if (!s.manufacturerPaid && (s.handlingFee != null || s.step == s.lastStep)) ...[const SizedBox(height: 14), _handling(context, s, readOnly)]],
            const SizedBox(height: 14),
          ]);
          final side = Column(children: [
            _statusPanel(context, s),
            const SizedBox(height: 14),
            ProcPanel(title: 'Details', icon: Symbols.info, child: KvGrid([
              (s.isImport ? 'Supplier' : 'Recipient', Text(s.supplierName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
              if (s.isImport) ('PO', Text(s.poNumber ?? '—', style: procMono(context, color: pal.text))),
              if (!s.isImport) ('Reason', Text(s.outboundReason ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
              ('Carrier', Text(s.carrierName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
              ('Goods', Text(goodsCategoryLabel(s.goodsCategory), style: AppTheme.bodySm.copyWith(fontSize: 12))),
              if (s.isImport) ('Costs', Text(s.manufacturerPaid ? 'Paid by ${s.paidBy ?? 'the manufacturer'} · TSh 0 to HyperMed' : 'HyperMed',
                  style: AppTheme.bodySm.copyWith(fontSize: 12))),
              ('Department', Text('${s.departmentName ?? '—'}${s.departmentManager == null ? '' : ' · ${s.departmentManager}'}',
                  style: AppTheme.bodySm.copyWith(fontSize: 12))),
              if (s.tender != null) ('Tender', Text('${s.tender!['tender_number']}', style: procMono(context, color: pal.text))),
              (s.isImport ? 'Arrival' : 'Delivery', Text('${shipDate(s.expectedArrival)}${s.port == null ? '' : ' · ${s.port}'}',
                  style: AppTheme.bodySm.copyWith(fontSize: 12))),
              if (s.locationNotes != null) ('Notes', Text(s.locationNotes!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
              ('Opened by', Text(s.createdByName ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
            ])),
            const SizedBox(height: 14),
            ProcPanel(title: 'Notified on every change', icon: Symbols.notifications_active, iconColor: AppColors.amber,
              child: Column(children: [
                for (final r in s.recipients) RecipientRow(
                  initials: _initials(r['name'] as String? ?? ''),
                  role: _roleLabel(r['role'] as String? ?? ''),
                  name: r['name'] as String?,
                ),
                if (s.recipients.isEmpty) Padding(padding: const EdgeInsets.all(14),
                    child: Text('No one to notify yet.', style: AppTheme.bodySub.copyWith(color: pal.textDim))),
              ])),
          ]);
          if (box.maxWidth < 1050) {
            return ListView(padding: const EdgeInsets.all(16), children: [main, const SizedBox(height: 14), side]);
          }
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main), const SizedBox(width: 14), SizedBox(width: 320, child: side),
            ]),
          );
        }))),
      ])),
    );
  }

  Widget _statusPanel(BuildContext context, Shipment s) {
    // Latest move into each step, for the date under it.
    final reached = <int, ShipmentEvent>{for (final e in s.events) e.toStep: e};
    final corrections = s.events.where((e) => e.backward).toList();
    return ProcPanel(
      title: 'Status', icon: directionIcon(s.direction), iconColor: AppColors.cyan,
      trailing: Text('${s.step} of ${s.lastStep}', style: procMono(context, size: 10.5)),
      footer: corrections.isEmpty ? null : Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in corrections) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
            'Corrected back to "${e.label}"${e.by == null ? '' : ' by ${e.by}'}${e.at == null ? '' : ', ${formatDate(e.at!)}'}: ${e.reason}',
            style: AppTheme.bodySub.copyWith(fontSize: 11, color: AppColors.amber))),
        ]),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: StatusTimeline(compact: true, [
          for (var i = 1; i <= s.lastStep; i++) TimelineEntry(
            s.labelFor(i),
            date: i <= s.step && reached[i]?.at != null ? formatDate(reached[i]!.at!) : null,
            note: i <= s.step ? reached[i]?.note : null,
            done: i < s.step || (i == s.step && s.isDone),
            current: i == s.step && !s.isDone,
            currentColor: shipmentFlagColor(context, s.flag),
          ),
        ]),
      ),
    );
  }

  Widget _documents(BuildContext context, Shipment s, bool readOnly) {
    final pal = context.pal;
    final required = s.documents.where((d) => d.required).toList();
    final done = required.where((d) => d.isUploaded).length;
    return ProcPanel(
      title: 'Shipping documents', icon: Symbols.folder_copy, iconColor: AppColors.green,
      trailing: Text('$done / ${required.length}',
          style: procMono(context, size: 10.5, color: done < required.length ? AppColors.amber : AppColors.green)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final d in s.documents) Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
          child: Row(children: [
            Icon(d.isUploaded ? Symbols.verified : d.notApplicable ? Symbols.remove_done : Symbols.upload_file, size: 16, fill: d.isUploaded ? 1 : 0,
                color: d.isUploaded ? AppColors.green : d.required ? AppColors.amber : pal.textDim),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.label}${d.required ? '' : d.notApplicable ? ' · not applicable' : d.forRecords ? ' · for records' : ' · when available'}',
                  style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: d.notApplicable && !d.isUploaded ? pal.textDim : null)),
              Text(d.isUploaded
                  ? '${d.fileName} · ${d.uploadedBy ?? ''}${d.uploadedAt == null ? '' : ', ${formatDate(d.uploadedAt!)}'}'
                  : d.notApplicable ? 'Not required for this shipment' : 'Not uploaded',
                  overflow: TextOverflow.ellipsis,
                  style: procMono(context, size: 10.5, color: d.isUploaded ? pal.textMute : pal.textDim)),
            ])),
            if (d.isUploaded) TextButton(onPressed: _busy != null ? null : () => _download(d),
                child: Text(_busy == 'dl-${d.type}' ? 'Working…' : 'Download', style: TextStyle(color: pal.textMute, fontSize: 11.5))),
            if (!readOnly) TextButton(onPressed: _busy != null ? null : () => _upload(d),
                child: Text(_busy == 'up-${d.type}' ? 'Uploading…' : d.isUploaded ? 'Replace' : 'Upload',
                    style: const TextStyle(fontSize: 11.5))),
          ]),
        ),
      ]),
    );
  }

  Widget _tmda(BuildContext context, Shipment s) {
    final pal = context.pal;
    final t = s.tmda ?? const {};
    DateTime? d(String k) => t[k] == null ? null : DateTime.tryParse(t[k] as String);
    final issued = d('issued_at');
    return ProcPanel(
      title: 'TMDA import permit', icon: Symbols.verified_user, iconColor: issued != null ? AppColors.green : AppColors.amber,
      trailing: ProcTag(issued != null ? 'Issued' : t['application_ref'] != null ? 'Applied' : 'Not applied',
          tone: issued != null ? ProcTone.green : ProcTone.amber, small: true),
      child: KvGrid([
        ('Application', Text(t['application_ref'] as String? ?? '—', style: procMono(context, color: pal.text))),
        ('Applied', Text(shipDate(d('applied_at')), style: AppTheme.bodySm.copyWith(fontSize: 12))),
        ('Issued', Text(shipDate(issued), style: AppTheme.bodySm.copyWith(fontSize: 12))),
        ('Permit file', Text(t['permit_uploaded'] == true ? 'Uploaded (see documents)' : 'Not uploaded',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
        ('Sent to courier', Text(s.permitSentAt == null && s.permitSentVendorName == null ? '—'
            : [s.permitSentVendorName, if (s.permitSentAt != null) shipDate(s.permitSentAt)].whereType<String>().join(' · '),
            style: AppTheme.bodySm.copyWith(fontSize: 12))),
      ]),
    );
  }

  /// Moving into "Arrived at HQ" asks for the clearing agent's receipt(s)
  /// right after (user, 2026-11-02: the receipt is attached there now).
  Future<void> _moveStatus(Shipment before) async {
    final saved = await showShipmentStatusDialog(context, before);
    _apply(saved);
    if (saved == null || !saved.isImport || saved.manufacturerPaid || saved.step != saved.lastStep || before.step == saved.lastStep) return;
    var attached = false;
    for (final f in [saved.clearingFee, saved.handlingFee]) {
      if (f == null || !f.canAttachReceipt || !mounted) continue;
      attached = await attachVendorReceipt(context, f.id, issuerHint: f.vendorName, amountHint: f.billed - f.receiptsTotal) || attached;
    }
    if (attached) _load();
  }

  /// The agent's receipt is attached at "Arrived at HQ", not before.
  bool _receiptStep(Shipment s) => s.step == s.lastStep;

  Widget _attachReceipt(ClearingFee f) => ProcButton(label: 'Attach receipt', icon: Symbols.attach_file, tone: ProcTone.green, onPressed: () async {
    if (await attachVendorReceipt(context, f.id, issuerHint: f.vendorName, amountHint: f.billed - f.receiptsTotal)) _load();
  });

  /// Fee first, then straight on to the agent's receipt.
  Future<void> _recordFeeAndReceipt(Shipment s) async {
    final saved = await showClearingFeeDialog(context, s);
    _apply(saved);
    final fee = saved?.clearingFee;
    if (fee != null && fee.status == 'pending_receipt' && _receiptStep(s) && mounted &&
        await attachVendorReceipt(context, fee.id, issuerHint: fee.vendorName, amountHint: fee.billed - fee.receiptsTotal)) {
      _load();
    }
  }

  /// "Attach receipt" (or record the fee and its receipt) for a "We pay"
  /// import waiting on the clearing agent's receipt; null otherwise.
  Widget? _receiptAction(Shipment s, bool readOnly) {
    if (readOnly || !s.isImport || s.manufacturerPaid || s.step < 7) return null;
    final f = s.clearingFee;
    if (f == null) {
      // The assessed cost goes in with the status (and the accountant is notified).
      return ProcButton(label: 'Enter assessed cost', icon: Symbols.payments, tone: ProcTone.green,
          onPressed: () async => _apply(await showShipmentStatusDialog(context, s)));
    }
    if (!f.canAttachReceipt || !_receiptStep(s)) return null;
    return _attachReceipt(f);
  }

  Widget _fee(BuildContext context, Shipment s, bool readOnly) {
    final pal = context.pal;
    final f = s.clearingFee;
    return ProcPanel(
      title: 'Clearing fee · Section 16', icon: Symbols.receipt_long, iconColor: AppColors.violet,
      trailing: f == null ? null : ProcTag(f.statusLabel, small: true,
          tone: f.paid ? ProcTone.green : f.status == 'rejected' ? ProcTone.coral : ProcTone.amber),
      footer: ProcNote(s.canApproveFee
          ? 'Approve the payment from Vendors & Delivery once Finance has verified the receipt.'
          : 'No receipt, no payment: receipt amount must equal the billed amount and be verified before the Director approves.'),
      child: f == null
          ? Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Expanded(child: Text(s.controlNumber == null
                  ? 'Recorded once the clearing agent sends the assessment.'
                  : 'Control number ${s.controlNumber} — record the clearing agent\'s fee.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim))),
              if (!readOnly) ProcButton(label: 'Record fee & receipt', icon: Symbols.add,
                  onPressed: () => _recordFeeAndReceipt(s)),
            ]))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KvGrid([
                ('Agent', Text(f.vendorName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
                ('Billed', Text(_tsh(f.billed), style: procMono(context, color: pal.text))),
                ('Receipts', Text('${_tsh(f.receiptsTotal)}${f.receiptUploaded ? (f.financeVerified ? ' · verified' : ' · awaiting Finance') : ''}',
                    style: procMono(context, color: f.receiptsTotal == f.billed ? AppColors.green : AppColors.amber))),
                if (s.controlNumber != null) ('Control no.', Text(s.controlNumber!, style: procMono(context, color: pal.text))),
                if (f.receiptFollowUp != null) ('Receipt', Text(f.receiptFollowUp!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber))),
                if (f.canAttachReceipt && !_receiptStep(s)) ('Receipt', Text('Attached at "${s.labelFor(s.lastStep)}"',
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim))),
                if (f.blockReason != null) ('Blocked', Text(f.blockReason!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber))),
              ]),
              if (!readOnly && !f.paid) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Wrap(spacing: 8, runSpacing: 8, children: [
                // The clearing agent's receipt goes on at "Arrived at HQ" (user, 2026-11-02);
                // Finance verifies it and the Director approves in Vendors & Delivery.
                if (f.canAttachReceipt && _receiptStep(s)) _attachReceipt(f),
                TextButton(onPressed: () async => _apply(await showClearingFeeDialog(context, s)), child: const Text('Link a different fee')),
              ])),
            ]),
    );
  }

  /// Storage & handling (Swissport etc.) the clearing agent paid for us,
  /// entered at "Arrived at HQ" and owed to the agent.
  Widget _handling(BuildContext context, Shipment s, bool readOnly) {
    final pal = context.pal;
    final f = s.handlingFee;
    return ProcPanel(
      title: 'Storage & handling · Swissport etc.', icon: Symbols.warehouse, iconColor: AppColors.violet,
      trailing: f == null ? null : ProcTag(f.statusLabel, small: true,
          tone: f.paid ? ProcTone.green : f.status == 'rejected' ? ProcTone.coral : ProcTone.amber),
      child: f == null
          ? Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Expanded(child: Text('Charges the clearing agent paid for us (storage, handling). Enter them with the Swissport papers.',
                  style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim))),
              if (!readOnly) ProcButton(label: 'Enter charges', icon: Symbols.add,
                  onPressed: () async => _apply(await showShipmentStatusDialog(context, s))),
            ]))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KvGrid([
                ('Owed to', Text(f.vendorName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12))),
                ('Billed', Text(_tsh(f.billed), style: procMono(context, color: pal.text))),
                ('Receipts', Text('${_tsh(f.receiptsTotal)}${f.receiptUploaded ? (f.financeVerified ? ' · verified' : ' · awaiting Finance') : ''}',
                    style: procMono(context, color: f.receiptsTotal == f.billed ? AppColors.green : AppColors.amber))),
                if (f.receiptFollowUp != null) ('Receipt', Text(f.receiptFollowUp!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.amber))),
              ]),
              if (!readOnly && f.status != 'rejected') Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (f.canAttachReceipt) _attachReceipt(f),
                if (!f.paid) TextButton(onPressed: () async => _apply(await showShipmentStatusDialog(context, s)), child: const Text('Change amount')),
              ])),
            ]),
    );
  }

  /// Manufacturer-paid import: nothing to pay, so no Section 16 fee.
  Widget _noCost(BuildContext context, Shipment s) => ProcPanel(
    title: 'Clearing, duty & freight', icon: Symbols.volunteer_activism, iconColor: AppColors.green,
    trailing: const ProcTag('No cost to HyperMed', tone: ProcTone.green, small: true),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KvGrid([
        ('Paid by', Text(s.paidBy ?? 'the manufacturer', style: AppTheme.bodySm.copyWith(fontSize: 12))),
        ('Cost to us', Text('TSh 0', style: procMono(context, color: AppColors.green))),
        if (s.costNote != null) ('Note', Text(s.costNote!, style: AppTheme.bodySm.copyWith(fontSize: 12))),
      ]),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Text(
        'No clearing fee is recorded, and the control-number and payment steps don\'t hold this shipment up. '
        'Switch it back under Edit if HyperMed ends up paying.',
        style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textMute))),
    ]),
  );
}
