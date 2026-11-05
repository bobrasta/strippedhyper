// Section 19 · tender detail (design 1b). Read-only for the CTO (19.7) —
// edit/generate/upload are hidden, everything stays visible.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/tender.dart';
import '../../services/tender_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'shipment_detail_screen.dart';
import 'shipment_forms.dart';
import 'tender_forms.dart';
import 'tenders_screen.dart' show deadlineColor;

String _tshFull(int v) => 'TSh ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

class TenderDetailScreen extends StatefulWidget {
  const TenderDetailScreen({super.key, required this.tenderId});
  final int tenderId;
  @override
  State<TenderDetailScreen> createState() => _TenderDetailScreenState();
}

class _TenderDetailScreenState extends State<TenderDetailScreen> {
  Tender? _t;
  String? _error;
  String? _busy; // which action is running

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await TenderService.instance.get(widget.tenderId);
      if (mounted) setState(() { _t = t; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() => _busy = key);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _edit() async {
    final t = await showTenderForm(context, tender: _t);
    if (t != null) _load();
  }

  Future<void> _changeStatus() async {
    final s = await pickTenderStatus(context, _t!.status);
    if (s == null || s == _t!.status || !mounted) return;
    String? reason;
    if (tenderStatusesNeedingReason.contains(s)) {
      reason = await askTenderStatusReason(context, s);
      if (reason == null) return;
    }
    await _run('status', () async {
      await TenderService.instance.setStatus(_t!.id, s, reason: reason);
      await _load();
    });
  }

  String _slug(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');

  Future<void> _generate(TenderDocumentSlot d) async {
    setState(() => _busy = 'gen-${d.type}');
    await downloadPdf(context, () => TenderService.instance.generate(_t!.id, d.type),
        '${_slug(d.label)}-${_slug(_t!.tenderNumber)}-draft.docx');
    await _load();
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _download(TenderDocumentSlot d, String which) async {
    setState(() => _busy = '$which-${d.type}');
    final name = which == 'executed' ? (d.executedName ?? '${_slug(d.label)}-signed') : '${_slug(d.label)}-${_slug(_t!.tenderNumber)}-draft.docx';
    await downloadPdf(context, () => TenderService.instance.download(_t!.id, d.type, which), name);
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _upload(TenderDocumentSlot d) async {
    if (Platform.isAndroid) {
      showErrorToast(context, Exception('File uploads aren\'t available on Android in this build.'));
      return;
    }
    final r = await FilePicker.pickFiles(allowMultiple: false, withData: false,
        type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'docx']);
    if (r == null || r.files.isEmpty || r.files.first.path == null) return;
    if (!mounted) return;
    // The server takes up to 20 MB; past ~25 MB it drops the file and
    // answers "file is required", which reads like a bug.
    if (r.files.first.size > 20 * 1024 * 1024) {
      showErrorToast(context, Exception('${r.files.first.name} is ${(r.files.first.size / 1048576).toStringAsFixed(1)} MB — '
          'the limit is 20 MB. Scan at a lower resolution or compress the PDF and try again.'));
      return;
    }
    await _run('up-${d.type}', () async {
      final t = await TenderService.instance.uploadExecuted(_t!.id, d.type, r.files.first.path!, r.files.first.name);
      if (mounted) { setState(() => _t = t); showSuccessToast(context, 'Signed ${d.label} uploaded. The generated draft is kept too.'); }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = _t;
    if (t == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: AppBar(backgroundColor: pal.bg),
          body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final readOnly = !t.canManage;
    final br = t.boardResolution;

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('Tenders')))),
        ProcPageHeader(
          title: t.title,
          breadcrumb: ['Tenders', t.tenderNumber],
          accent: t.flagged ? AppColors.coral : AppColors.cyan,
          tags: [
            ProcTag(t.flagged ? '${t.statusLabel} · overdue' : t.statusLabel, tone: t.flagged ? ProcTone.coral : ProcTone.teal),
            if (t.tenderType != 'standard') ProcTag(tenderTypeLabel(t.tenderType), tone: ProcTone.violet),
            if (t.statusReason != null && t.statusReason!.isNotEmpty)
              Text('Reason: ${t.statusReason}', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.coral)),
            if (t.contractNumber != null) ProcTag('Contract ${t.contractNumber}'),
            Text([
              if (t.value != null) '${_tshFull(t.value!)} VAT ${t.vatInclusive ? 'incl.' : 'excl.'}',
              if (t.ownerName != null) 'owner ${t.ownerName}',
              if (br != null) 'Board Res. No. ${br['number']}',
            ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          ],
          actions: readOnly
              ? [const ProcTag('Read-only', tone: ProcTone.violet)]
              : [
                  ProcButton(label: 'Edit details & dates', icon: Symbols.edit, onPressed: _edit),
                  ProcButton(label: _busy == 'status' ? 'Saving…' : 'Change status', icon: Symbols.route, tone: ProcTone.green,
                      onPressed: _busy == null ? _changeStatus : null),
                ],
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: LayoutBuilder(builder: (context, box) {
          final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (t.flagged) ...[_OverdueBanner(t, readOnly: readOnly, onUpload: () {
              final slot = t.documents.where((d) => d.type == 'performance_securing_declaration').firstOrNull;
              if (slot != null) _upload(slot);
            }), const SizedBox(height: 14)],
            _DeadlineCards(t),
            const SizedBox(height: 14),
            _documents(context, t, readOnly),
            const SizedBox(height: 14),
            _shipments(context, t, readOnly),
          ]);
          final side = Column(children: [
            _statusPanel(context, t),
            const SizedBox(height: 14),
            ProcPanel(title: 'Procuring entity', icon: Symbols.apartment, child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.entity?.addressBlock ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
                if (t.str('entity_ref') != null) Padding(padding: const EdgeInsets.only(top: 6),
                    child: Text('Their ref ${t.str('entity_ref')}${t.date('entity_ref_date') == null ? '' : ' of ${formatDate(t.date('entity_ref_date')!)}'}',
                        style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim))),
                if (t.str('our_ref') != null) Text('Our ref ${t.str('our_ref')}', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
              ]),
            )),
            if (br != null) ...[
              const SizedBox(height: 14),
              ProcPanel(title: 'Board resolution', icon: Symbols.format_list_numbered, child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
                child: Text('No. ${br['number']} of ${formatDate(DateTime.parse(br['resolution_date'] as String))}'
                    '${(br['shared_with'] as List).isEmpty ? '' : '\nAlso authorises: ${(br['shared_with'] as List).join(', ')}'}',
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
              )),
            ],
            const SizedBox(height: 14),
            ProcPanel(title: 'Audit log', icon: Symbols.history, child: t.audit.isEmpty
                ? Padding(padding: const EdgeInsets.all(14), child: Text('No changes yet.', style: AppTheme.bodySub.copyWith(color: pal.textDim)))
                : AuditList([for (final a in t.audit) (a.what, a.who ?? 'System', a.at == null ? '' : formatDate(a.at!),
                    a.what.toLowerCase().contains('overdue'))])),
          ]);
          if (box.maxWidth < 1050) {
            return ListView(padding: const EdgeInsets.all(16), children: [main, const SizedBox(height: 14), side]);
          }
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main), const SizedBox(width: 14), SizedBox(width: 300, child: side),
            ]),
          );
        }))),
      ])),
    );
  }

  Widget _shipments(BuildContext context, Tender t, bool readOnly) {
    final pal = context.pal;
    final rows = [for (final x in (t.raw['shipments'] as List? ?? [])) Map<String, dynamic>.from(x as Map)];
    return ProcPanel(
      title: 'Linked shipments · Section 18', icon: Symbols.flight_land, iconColor: AppColors.cyan,
      trailing: readOnly ? null : TextButton(
        onPressed: () async {
          final s = await showShipmentForm(context, tenderId: t.id);
          if (s == null || !context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: s.id)));
          _load();
        },
        child: const Text('New shipment', style: TextStyle(fontSize: 11.5))),
      child: rows.isEmpty
          ? Padding(padding: const EdgeInsets.all(14), child: Text('No shipments linked to this tender yet.',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)))
          : Column(children: [
              for (final r in rows) InkWell(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipmentId: (r['id'] as num).toInt())));
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                  child: Row(children: [
                    SizedBox(width: 120, child: Text('${r['reference']}', style: procMono(context, color: pal.text))),
                    Expanded(child: Text('${r['description']}', overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12))),
                    const SizedBox(width: 10),
                    Text('${r['step']}/${r['last_step']} · ${r['status_label']}', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textMute)),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _statusPanel(BuildContext context, Tender t) {
    final lost = t.status == 'lost' || t.status == 'cancelled';
    final step = t.step;
    return ProcPanel(
      title: 'Status', icon: Symbols.route, iconColor: AppColors.cyan,
      trailing: Text('$step of ${tenderFlow.length}', style: procMono(context, size: 10.5)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: StatusTimeline(compact: true, [
          for (var i = 0; i < tenderFlow.length; i++) TimelineEntry(
            i == 4 ? (lost ? tenderStatusLabel(t.status) : 'Won / Lost') : tenderStatusLabel(tenderFlow[i]),
            date: i == 6 && step < 7 ? (() {
              final d = t.deadline('performance_security')?.due;
              return d == null ? null : 'due ${formatDate(d)}';
            })() : null,
            done: i + 1 < step || (i + 1 == step && t.status == 'closed'),
            current: i + 1 == step && t.status != 'closed',
            currentColor: t.flagged || lost ? AppColors.coral : AppColors.cyan,
          ),
        ]),
      ),
    );
  }

  Widget _documents(BuildContext context, Tender t, bool readOnly) {
    final pal = context.pal;
    final executed = t.documents.where((d) => d.hasExecuted).length;
    final psOverdue = t.deadline('performance_security')?.state == DeadlineState.overdue;
    return ProcPanel(
      title: 'Tender documents', icon: Symbols.folder_copy, iconColor: AppColors.green,
      trailing: Text('$executed / ${t.documents.length} executed',
          style: procMono(context, size: 10.5, color: executed < t.documents.length ? AppColors.amber : AppColors.green)),
      footer: const ProcNote('Company address, TIN and signatory come from Company details. Drafts leave signature, seal and witness lines blank, as in the originals. '
          'Print, sign and stamp, then upload the scan — the draft and the signed copy are both kept.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final d in t.documents) Builder(builder: (context) {
          final late = !d.hasExecuted && d.type == 'performance_securing_declaration' && psOverdue;
          final execColor = d.hasExecuted ? AppColors.green : late ? AppColors.coral : pal.textDim;
          Widget link(String label, VoidCallback? onTap, {Color? color, String? busyKey}) => TextButton(
            onPressed: _busy != null ? null : onTap,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)),
            child: Text(_busy == busyKey && busyKey != null ? 'Working…' : label,
                style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: color ?? AppColors.teal)),
          );
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: late ? AppColors.coral.withValues(alpha: 0.05) : null,
                border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(d.label, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
              const SizedBox(height: 4),
              Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(d.hasDraft ? Symbols.description : Symbols.remove, size: 14, color: d.hasDraft ? AppColors.cyan : pal.textDim),
                  const SizedBox(width: 6),
                  Text(!d.generated ? 'From the buyer' : d.hasDraft ? 'Draft ${formatDate(d.draftAt!)}' : 'Not generated',
                      style: procMono(context, size: 10.5, color: d.hasDraft ? pal.textMute : pal.textDim)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(d.hasExecuted ? Symbols.verified : Symbols.upload, size: 14, color: execColor, fill: d.hasExecuted ? 1 : 0),
                  const SizedBox(width: 6),
                  Text(d.hasExecuted ? 'Signed copy ${formatDate(d.executedAt!)}' : late ? 'Not uploaded · overdue' : 'No signed copy',
                      style: procMono(context, size: 10.5, color: d.hasExecuted ? pal.textMute : execColor)),
                ]),
              ]),
              Wrap(children: [
                if (!readOnly && d.generated) link(d.hasDraft ? 'Regenerate draft' : 'Generate draft', () => _generate(d), busyKey: 'gen-${d.type}'),
                if (d.hasDraft) link('Download draft', () => _download(d, 'draft'), color: pal.textMute, busyKey: 'draft-${d.type}'),
                if (!readOnly) link(d.hasExecuted ? 'Replace signed copy' : 'Upload signed copy', () => _upload(d),
                    color: late ? AppColors.coral : AppColors.green, busyKey: 'up-${d.type}'),
                if (d.hasExecuted) link('Download signed copy', () => _download(d, 'executed'), color: pal.textMute, busyKey: 'executed-${d.type}'),
              ]),
            ]),
          );
        }),
      ]),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner(this.t, {required this.readOnly, required this.onUpload});
  final Tender t;
  final bool readOnly;
  final VoidCallback onUpload;
  @override
  Widget build(BuildContext context) {
    final coral = AppColors.coral;
    final overdue = t.deadlines.where((d) => d.highRisk && d.state == DeadlineState.overdue).toList();
    final ps = overdue.where((d) => d.kind == 'performance_security').firstOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(color: coral.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppColors.rMd),
          border: Border.all(color: coral.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(Symbols.report, size: 22, color: coral, fill: 1),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in overdue) Text('${d.label} is ${d.relative}', style: AppTheme.bodySm.copyWith(fontSize: 13, color: coral)),
          const SizedBox(height: 2),
          Text([
            for (final d in overdue) 'Due ${formatDate(d.due!)} (${d.basis}).',
            'The declarations warn of disqualification from future tenders. The owner, Director and CTO are being reminded.',
          ].join(' '), style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textMute)),
        ])),
        if (!readOnly && ps != null) ...[const SizedBox(width: 12),
          ProcButton(label: 'Upload signed copy', icon: Symbols.upload, tone: ProcTone.coral, onPressed: onUpload)],
      ]),
    );
  }
}

class _DeadlineCards extends StatelessWidget {
  const _DeadlineCards(this.t);
  final Tender t;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget card(TenderDeadline d) {
      final overdue = d.state == DeadlineState.overdue;
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: overdue ? AppColors.coral.withValues(alpha: 0.4) : pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d.label.toUpperCase(), style: procCaps(context), overflow: TextOverflow.ellipsis)),
            ProcTag(d.computed ? 'auto' : 'manual', tone: d.computed ? ProcTone.amber : ProcTone.neutral, small: true),
          ]),
          const SizedBox(height: 5),
          Text(d.due == null ? '—' : formatDate(d.due!), style: AppTheme.cardTitle.copyWith(fontSize: 18,
              color: overdue ? AppColors.coral : pal.text)),
          const SizedBox(height: 5),
          Text(d.basis, style: procMono(context, size: 10)),
          const SizedBox(height: 5),
          Text(d.relative, style: AppTheme.bodySub.copyWith(fontSize: 11, color: deadlineColor(context, d.state))),
        ]),
      );
    }
    return LayoutBuilder(builder: (_, box) {
      final cols = box.maxWidth < 620 ? 2 : box.maxWidth < 900 ? 3 : 5;
      final w = (box.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final d in t.deadlines) SizedBox(width: w, child: card(d))]);
    });
  }
}

