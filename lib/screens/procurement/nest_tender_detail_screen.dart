// One NeST tender: everything NeST published, why it was flagged (matched
// rules), the change history, triage (new / reviewing / skipped), notes,
// assignment and "Start bid", which creates a Section 19 tender that carries
// the pipeline from then on. Documents come through the API using the
// company's NeST login; "Open in NeST" is always there as the fallback.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart' show userIdNotifier;
import '../../models/nest_tender.dart';
import '../../services/download_manager.dart';
import '../../services/nest_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/pdf_preview_dialog.dart';
import '../../widgets/procurement/nest_widgets.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'tender_detail_screen.dart';

class NestTenderDetailScreen extends StatefulWidget {
  const NestTenderDetailScreen({super.key, required this.tenderId});
  final int tenderId;
  @override
  State<NestTenderDetailScreen> createState() => _NestTenderDetailScreenState();
}

class _NestTenderDetailScreenState extends State<NestTenderDetailScreen> {
  NestTenderDetail? _d;
  String? _error;
  String? _busy;
  final _notes = TextEditingController();
  bool _notesDirty = false;
  NestDocuments? _docs;
  String? _docsError;
  bool _docsLoading = false;
  String? _opening; // file id being fetched

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _apply(NestTenderDetail d) {
    _d = d;
    if (!_notesDirty) _notes.text = d.tender.notes ?? '';
  }

  Future<void> _load() async {
    try {
      final d = await NestService.instance.get(widget.tenderId);
      if (mounted) setState(() { _apply(d); _error = null; });
      if (d.documentAvailable && _docs == null && !_docsLoading) _loadDocs();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run(String key, Future<NestTenderDetail?> Function() action, {String? done}) async {
    setState(() => _busy = key);
    try {
      final d = await action();
      if (d != null && mounted) setState(() => _apply(d));
      if (done != null && mounted) showSuccessToast(context, done);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _triage(String status) => _run('triage', () => NestService.instance.update(widget.tenderId, {'triage_status': status}));

  Future<void> _assignToMe(bool me) => _run('assign', () => NestService.instance.update(widget.tenderId, {'assigned_to': me ? userIdNotifier.value : null}),
      done: me ? 'Assigned to you.' : 'Unassigned.');

  Future<void> _saveNotes() => _run('notes', () async {
    final d = await NestService.instance.update(widget.tenderId, {'notes': _notes.text.trim()});
    _notesDirty = false;
    return d;
  }, done: 'Notes saved.');

  Future<void> _startBid() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Start a bid?'),
      content: const Text('This creates a tender in Tenders & Contracts with this reference, buyer and closing date, '
          'so the bid documents, deadlines and status are tracked there. Its submission deadline follows NeST '
          'until the bid is submitted.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start bid')),
      ],
    ));
    if (ok != true || !mounted) return;
    await _run('bid', () => NestService.instance.startBid(widget.tenderId), done: 'Bid started — it is in Tenders & Contracts.');
  }

  Future<void> _openBid() async {
    final id = _d?.tender.tenderId;
    if (id == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TenderDetailScreen(tenderId: id)));
    _load();
  }

  String _fileSlug(NestTender t) => t.reference.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');

  void _document() {
    final t = _d!.tender;
    showPdfPreview(context, () => NestService.instance.document(t.id), 'NeST-${_fileSlug(t)}.pdf');
  }

  Future<void> _copySummary() async {
    final t = _d!.tender;
    final text = t.summary((d) => '${formatDate(d)} ${formatTime(d)}');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSuccessToast(context, 'Summary copied — paste it into WhatsApp, email or anywhere.');
  }

  /// Saves an .ics event at the closing time (with a reminder the day
  /// before) and hands it to the calendar app.
  Future<void> _addToCalendar() async {
    final t = _d!.tender;
    final at = t.closingAt;
    if (at == null) return;
    String stamp(DateTime d) {
      final u = d.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}00Z';
    }
    String esc(String s) => s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');
    final ics = [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Hypermed//NeST tenders//EN', 'BEGIN:VEVENT',
      'UID:nest-${t.entityUuid}@hypermed.co.tz',
      'DTSTAMP:${stamp(DateTime.now())}',
      'DTSTART:${stamp(at)}',
      'DTEND:${stamp(at.add(const Duration(minutes: 30)))}',
      'SUMMARY:${esc('Tender closes: ${t.description}')}',
      'DESCRIPTION:${esc(t.summary((d) => '${formatDate(d)} ${formatTime(d)}'))}',
      'URL:${t.nestUrl}',
      'BEGIN:VALARM', 'TRIGGER:-P1D', 'ACTION:DISPLAY', 'DESCRIPTION:${esc('Tender closes tomorrow: ${t.reference}')}', 'END:VALARM',
      'END:VEVENT', 'END:VCALENDAR',
    ].join('\r\n');
    try {
      final file = await DownloadManager.instance.save(utf8.encode(ics), 'NeST-${_fileSlug(t)}.ics');
      if (Platform.isAndroid || Platform.isIOS) {
        await DownloadManager.instance.share(file);
      } else {
        await DownloadManager.instance.open(file);
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _loadDocs({bool refresh = false}) async {
    setState(() { _docsLoading = true; _docsError = null; });
    try {
      final docs = await NestService.instance.documents(widget.tenderId, refresh: refresh);
      if (mounted) setState(() => _docs = docs);
    } catch (e) {
      if (mounted) setState(() => _docsError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _docsLoading = false);
    }
  }

  /// PDFs open in the in-app viewer; anything else (Word, Excel, drawings)
  /// is saved to Downloads/Hypermed and handed to the OS.
  Future<void> _openFile(NestDocument doc) async {
    setState(() => _opening = doc.id);
    try {
      final (bytes, name) = await NestService.instance.documentFile(widget.tenderId, doc.id);
      final filename = name ?? '${_fileSlug(_d!.tender)}-${doc.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.pdf';
      final isPdf = bytes.length > 4 && String.fromCharCodes(bytes.take(4)) == '%PDF';
      if (!mounted) return;
      if (isPdf) {
        await showPdfPreview(context, () async => bytes, filename);
      } else {
        final file = await DownloadManager.instance.save(bytes, filename);
        await DownloadManager.instance.open(file);
        if (mounted) showSuccessToast(context, 'Saved to ${file.path}');
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final d = _d;
    if (d == null) {
      return Scaffold(backgroundColor: pal.bg, appBar: AppBar(backgroundColor: pal.bg),
          body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final t = d.tender;
    final manage = d.canManage;

    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 8, top: 6), child: Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Symbols.arrow_back, size: 16), label: const Text('NeST tenders')))),
        ProcPageHeader(
          title: t.description,
          breadcrumb: ['NeST tenders', t.reference],
          accent: t.isClosingSoon ? AppColors.coral : AppColors.green,
          tags: [
            ProcTag(nestPipelineLabel(t.pipelineStatus), tone: nestPipelineTone(t.pipelineStatus)),
            for (final tag in t.tags) ProcTag(nestTagLabel(tag), tone: nestTagTone(tag)),
            if (t.hasAddendum) const ProcTag('Addendum', tone: ProcTone.amber),
            if (t.relevance == 'maybe') const ProcTag('Maybe relevant'),
            Text(t.procuringEntityName ?? '', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          ],
          actions: [
            ProcButton(label: 'Open in NeST', icon: Symbols.open_in_new, tone: ProcTone.green,
                onPressed: () => launchUrl(Uri.parse(t.nestUrl), mode: LaunchMode.externalApplication)),
            ProcButton(label: 'Tender document', icon: Symbols.picture_as_pdf, locked: !d.documentAvailable, onPressed: _document),
            if (t.closingAt != null) ProcButton(label: 'Add to calendar', icon: Symbols.calendar_add_on, onPressed: _addToCalendar),
            ProcButton(label: 'Copy summary', icon: Symbols.content_copy, onPressed: _copySummary),
          ],
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 1000;
          final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // On phones the countdown leads, above the pipeline panel.
            if (!narrow) ...[_closing(context, t), const SizedBox(height: 14)],
            if (d.documentAvailable) ...[_documentsPanel(context, t), const SizedBox(height: 14)],
            if ((_docs?.addendumChanges ?? const []).isNotEmpty) ...[_addendumPanel(context), const SizedBox(height: 14)],
            if ((_docs?.clarifications ?? const []).isNotEmpty) ...[_clarificationsPanel(context), const SizedBox(height: 14)],
            _details(context, t),
            const SizedBox(height: 14),
            _why(context, t),
            const SizedBox(height: 14),
            _history(context, t),
          ]);
          final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pipeline(context, t, manage),
            const SizedBox(height: 14),
            _notesPanel(context, t, manage),
            if (!d.documentAvailable) ...[
              const SizedBox(height: 14),
              ProcNote(manage
                  ? 'Tender documents need the company NeST login — add it under NeST tenders → Settings. Until then use "Open in NeST".'
                  : 'Documents: use "Open in NeST" (the NeST login has not been set up here yet).', tone: ProcTone.amber),
            ],
          ]);
          if (narrow) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              _closing(context, t), const SizedBox(height: 14), side, const SizedBox(height: 14), main]);
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

  Widget _documentsPanel(BuildContext context, NestTender t) {
    final pal = context.pal;
    final docs = _docs;
    IconData icon(String kind) => switch (kind) {
      'tender_document' => Symbols.description,
      'clarification' => Symbols.forum,
      'pre_bid' => Symbols.groups,
      'requisition' => Symbols.design_services,
      _ => Symbols.attach_file,
    };
    String kindLabel(String kind) => switch (kind) {
      'tender_document' => 'Issued by the buyer',
      'clarification' => 'Clarification',
      'pre_bid' => 'Pre-bid meeting',
      'requisition' => 'Specifications / drawings',
      _ => 'Attachment',
    };
    Widget body;
    if (docs == null) {
      body = Padding(padding: const EdgeInsets.all(14), child: _docsError != null
          ? Text(_docsError!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.coral))
          : Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Fetching the document list from NeST…', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
            ]));
    } else if (docs.documents.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(14), child: Text('NeST shows no documents for this tender yet.',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)));
    } else {
      body = Column(children: [
        for (final doc in docs.documents) InkWell(
          onTap: _opening == null ? () => _openFile(doc) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
            child: Row(children: [
              Icon(icon(doc.kind), size: 18, color: doc.kind == 'tender_document' ? AppColors.green : pal.textMute),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                Text(doc.note ?? kindLabel(doc.kind), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
              ])),
              const SizedBox(width: 10),
              _opening == doc.id
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Open', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: AppColors.cyan)),
            ]),
          ),
        ),
      ]);
    }
    return ProcPanel(
      title: 'Documents${docs == null ? '' : ' · ${docs.documents.length}'}', icon: Symbols.folder_open, iconColor: AppColors.green,
      trailing: TextButton(
        onPressed: _docsLoading ? null : () => _loadDocs(refresh: true),
        child: Text(_docsLoading && docs != null ? 'Checking…' : 'Re-check NeST', style: const TextStyle(fontSize: 11.5))),
      footer: docs != null && docs.errors.isNotEmpty
          ? ProcNote('Some parts could not be read from NeST: ${docs.errors.join(' · ')}', tone: ProcTone.amber)
          : null,
      child: body,
    );
  }

  Widget _addendumPanel(BuildContext context) {
    final pal = context.pal;
    final docs = _docs!;
    return ProcPanel(
      title: 'Addendum', icon: Symbols.edit_document, iconColor: AppColors.amber,
      trailing: docs.addendumStatus == null ? null : Text(docs.addendumStatus!.toLowerCase(), style: procMono(context, size: 10.5)),
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (area, reason) in docs.addendumChanges) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(area ?? 'Change', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            if (reason != null && reason.trim().isNotEmpty)
              Text(reason.trim(), style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
          ]),
        ),
      ])),
    );
  }

  Widget _clarificationsPanel(BuildContext context) {
    final pal = context.pal;
    final list = _docs!.clarifications;
    String when(DateTime? d) => d == null ? '' : ' · ${formatDate(toEat(d))}';
    return ProcPanel(
      title: 'Clarifications · ${list.length}', icon: Symbols.forum,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in list) Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            if ((c.question ?? '').trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3),
                child: SelectableText(c.question!.trim(), style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
            Text('${c.fromBuyer ? 'Buyer' : 'Tenderer'}${when(c.at)}', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
            for (final r in c.replies) Container(
              margin: const EdgeInsets.only(top: 8, left: 12),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(border: Border(left: BorderSide(width: 2,
                  color: r.fromBuyer ? AppColors.green.withValues(alpha: 0.6) : pal.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText((r.text ?? '').trim().isEmpty ? '(no text — see the attachment)' : r.text!.trim(),
                    style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.text)),
                Text('${r.fromBuyer ? 'Buyer replied' : 'Tenderer'}${when(r.at)}', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
              ]),
            ),
            if (c.replies.isEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                child: Text('No answer yet.', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: AppColors.amber))),
          ]),
        ),
      ]),
    );
  }

  Widget _closing(BuildContext context, NestTender t) {
    final pal = context.pal;
    final color = nestClosingColor(context, t);
    return ProcPanel(
      title: 'Closing', icon: Symbols.alarm, iconColor: color,
      borderColor: t.isClosingSoon ? AppColors.coral.withValues(alpha: 0.45) : null,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Wrap(spacing: 28, runSpacing: 10, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.countdown, style: AppTheme.kpiValue.copyWith(fontSize: 22, height: 1.1, color: color)),
          const SizedBox(height: 3),
          Text(t.closingAt == null ? '—' : '${nestClosingText(t)} EAT (submission / opening)',
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
        ]),
        if (t.invitationAt != null) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Invited', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          Text(formatDate(toEat(t.invitationAt!)), style: AppTheme.bodySm),
        ]),
      ])),
    );
  }

  Widget _details(BuildContext context, NestTender t) {
    final pal = context.pal;
    Widget v(String? s) => SelectableText(s == null || s.isEmpty ? '—' : s, style: AppTheme.bodySm.copyWith(fontSize: 12));
    return ProcPanel(
      title: 'From NeST', icon: Symbols.description,
      child: KvGrid(labelWidth: 120, [
        ('Reference', v(t.referenceNumber)),
        ('Tender no.', v(t.entityNumber)),
        ('Procuring entity', v(t.procuringEntityName)),
        ('Type', v(switch (t.entityType) { 'FRAMEWORK' => 'Framework agreement', 'PLANNED_TENDER' => 'Planned tender', 'TENDER' => 'Tender', _ => t.entityType })),
        ('Category', v([t.procurementCategoryName, t.procurementCategory].whereType<String>().join(' · '))),
        ('Sub-category', v(t.subCategoryName)),
        ('Financial year', v(t.financialYear)),
        ('Lots', v(t.lotCount?.toString())),
        ('Addendum', v(t.hasAddendum ? 'Yes — check NeST for the changes' : 'No')),
        ('Eligible', t.eligibleTypes.isEmpty ? v(null) : Text(
            t.eligibleTypes.map((e) => e.replaceAll('_', ' ').toLowerCase()).join(', '),
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
        ('First seen', v(t.firstSeenAt == null ? null : formatDate(toEat(t.firstSeenAt!)))),
      ]),
    );
  }

  Widget _why(BuildContext context, NestTender t) {
    final pal = context.pal;
    return ProcPanel(
      title: 'Why it was flagged', icon: Symbols.manage_search,
      trailing: Text('score ${t.relevanceScore}', style: procMono(context, size: 10.5, color: t.isRelevant ? AppColors.green : pal.textMute)),
      footer: t.matched.any((m) => !m.counted)
          ? const ProcNote('Struck-through rules matched but did not count (see the tooltip for why).')
          : null,
      child: t.matched.isEmpty
          ? Padding(padding: const EdgeInsets.all(14), child: Text('No rule matched this tender.', style: AppTheme.bodySub.copyWith(color: pal.textDim)))
          : Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in t.matched) Tooltip(
                message: [
                  switch (m.type) { 'keyword' => 'Keyword', 'exclude' => 'Exclude', 'health_subcategory' => 'Health-sector sub-category', 'entity_hint' => 'Buyer name hint', _ => m.type },
                  '${m.weight > 0 ? '+' : ''}${m.weight}',
                  ?m.note,
                ].join(' · '),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (m.weight < 0 ? AppColors.coral : m.tag != null ? nestTagTone(m.tag!).fg(context) : pal.textMute)
                        .withValues(alpha: m.counted ? 0.12 : 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: m.counted ? null : Border.all(color: pal.border),
                  ),
                  child: Text('${m.term} ${m.weight > 0 ? '+' : ''}${m.weight}', style: AppTheme.bodySub.copyWith(fontSize: 11,
                      color: m.counted ? pal.text : pal.textDim,
                      decoration: m.counted ? null : TextDecoration.lineThrough)),
                ),
              ),
            ])),
    );
  }

  Widget _history(BuildContext context, NestTender t) {
    final pal = context.pal;
    String val(NestChange c, String? s) {
      if (s == null) return '—';
      if (c.field == 'closing_at') {
        final d = DateTime.tryParse(s);
        return d == null ? s : '${formatDate(toEat(d))} ${formatTime(toEat(d))}';
      }
      if (c.field == 'has_addendum') return s == 'yes' ? 'addendum' : 'no addendum';
      return s;
    }
    String label(String f) => switch (f) {
      'closing_at' => 'Closing date moved',
      'has_addendum' => 'Addendum',
      'lot_count' => 'Lots changed',
      'description' => 'Description changed',
      _ => f,
    };
    return ProcPanel(
      title: 'Change history', icon: Symbols.history,
      child: t.changes.isEmpty
          ? Padding(padding: const EdgeInsets.all(14), child: Text('No changes on NeST since it was first seen.', style: AppTheme.bodySub.copyWith(color: pal.textDim)))
          : AuditList([
              for (final c in t.changes) (
                c.field == 'description' ? label(c.field) : '${label(c.field)}: ${val(c, c.oldValue)} → ${val(c, c.newValue)}',
                'NeST',
                c.detectedAt == null ? '' : '${formatDate(toEat(c.detectedAt!))} ${formatTime(toEat(c.detectedAt!))}',
                c.field == 'closing_at' || c.field == 'has_addendum',
              ),
            ]),
    );
  }

  Widget _pipeline(BuildContext context, NestTender t, bool manage) {
    final pal = context.pal;
    final me = userIdNotifier.value;
    final mine = me != null && t.assignedToId == me;
    const triage = ['new', 'reviewing', 'skipped'];

    return ProcPanel(
      title: 'Pipeline', icon: Symbols.route, iconColor: AppColors.cyan,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t.bidStarted) ...[
          Row(children: [
            ProcTag(nestPipelineLabel(t.pipelineStatus), tone: nestPipelineTone(t.pipelineStatus)),
            const SizedBox(width: 8),
            Expanded(child: Text('Bid in Tenders & Contracts', style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
          ]),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: ProcButton(label: 'Open the bid', icon: Symbols.gavel, tone: ProcTone.green, onPressed: _openBid)),
        ] else ...[
          Text('Status', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
          const SizedBox(height: 6),
          if (manage)
            ProcSegmented(
              options: [for (final s in triage) nestPipelineLabel(s)],
              selected: triage.indexOf(t.triageStatus).clamp(0, 2),
              onChanged: (i) { if (_busy == null && triage[i] != t.triageStatus) _triage(triage[i]); },
            )
          else
            Align(alignment: Alignment.centerLeft, child: ProcTag(nestPipelineLabel(t.triageStatus), tone: nestPipelineTone(t.triageStatus))),
          if (manage) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: ProcButton(
              label: _busy == 'bid' ? 'Starting…' : 'Start bid', icon: Symbols.gavel, tone: ProcTone.green,
              onPressed: _busy == null ? _startBid : null)),
          ],
        ],
        const SizedBox(height: 14),
        Text('Assigned to', style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(t.assignedToName ?? 'Nobody yet', style: AppTheme.bodySm.copyWith(fontSize: 12.5,
              color: t.assignedToName == null ? pal.textDim : pal.text))),
          if (manage && me != null) TextButton(
            onPressed: _busy == null ? () => _assignToMe(!mine) : null,
            child: Text(mine ? 'Unassign' : 'Assign to me', style: const TextStyle(fontSize: 11.5)),
          ),
        ]),
      ])),
    );
  }

  Widget _notesPanel(BuildContext context, NestTender t, bool manage) {
    final pal = context.pal;
    if (!manage) {
      return ProcPanel(title: 'Notes', icon: Symbols.sticky_note_2, child: Padding(padding: const EdgeInsets.all(14),
          child: Text((t.notes ?? '').isEmpty ? 'No notes.' : t.notes!, style: AppTheme.bodySub.copyWith(fontSize: 12, color: pal.textMute))));
    }
    return ProcPanel(
      title: 'Notes', icon: Symbols.sticky_note_2,
      child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LabeledTextField(label: 'Notes for the team', controller: _notes, maxLines: 5,
            hint: 'Lots we can quote, site visit, who has the brochure…',
            onChanged: (_) { if (!_notesDirty) setState(() => _notesDirty = true); }),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: ProcButton(
          label: _busy == 'notes' ? 'Saving…' : 'Save notes', icon: Symbols.save,
          tone: _notesDirty ? ProcTone.green : ProcTone.neutral,
          onPressed: _busy == null && _notesDirty ? _saveNotes : null)),
      ])),
    );
  }
}
