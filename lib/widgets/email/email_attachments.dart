import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../main.dart' show userIdNotifier;
import '../../models/email.dart';
import '../../services/download_manager.dart';
import '../../services/email_attachment_cache.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../common/pdf_preview_dialog.dart';

// Email attachments inside Hypermed: received files open in the app (PDFs in
// the PDF viewer, images in an image viewer; Word/Excel etc. are saved to
// Downloads/Hypermed and opened with the PC's own program), and files can be
// attached to compose, reply and forward.

IconData _iconFor(String ext) => switch (ext) {
  'pdf' => Symbols.picture_as_pdf,
  'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Symbols.image,
  'doc' || 'docx' || 'odt' || 'rtf' || 'txt' => Symbols.description,
  'xls' || 'xlsx' || 'csv' || 'ods' => Symbols.table_chart,
  'zip' || 'rar' || '7z' => Symbols.folder_zip,
  _ => Symbols.attach_file,
};

/// Opens a received attachment — from this device when it was opened before.
Future<void> openEmailAttachment(BuildContext context, int emailId, EmailAttachment a) async {
  final uid = userIdNotifier.value;
  if (uid == null) return;
  if (a.isPdf) {
    return showPdfPreview(context, () async => (await EmailAttachmentCache.instance.get(uid, emailId, a)).readAsBytes(), a.filename);
  }
  try {
    final file = await EmailAttachmentCache.instance.get(uid, emailId, a);
    if (!context.mounted) return;
    if (a.isImage) {
      await showDialog<void>(context: context, builder: (dialogCtx) => _ImageViewer(file: file, name: a.filename));
      return;
    }
    final saved = await DownloadManager.instance.save(await file.readAsBytes(), a.filename);
    await DownloadManager.instance.open(saved);
    if (context.mounted) showSuccessToast(context, 'Saved to ${saved.path}');
  } catch (e) {
    if (context.mounted) showErrorToast(context, e);
  }
}

/// The attachments of a received (or sent) email.
class EmailAttachmentList extends StatefulWidget {
  const EmailAttachmentList({super.key, required this.emailId, required this.attachments});
  final int emailId;
  final List<EmailAttachment> attachments;

  @override
  State<EmailAttachmentList> createState() => _EmailAttachmentListState();
}

class _EmailAttachmentListState extends State<EmailAttachmentList> {
  int? _opening;
  final _onDevice = <int>{};

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  @override
  void didUpdateWidget(EmailAttachmentList old) {
    super.didUpdateWidget(old);
    if (old.emailId != widget.emailId) _checkDevice();
  }

  Future<void> _checkDevice() async {
    final uid = userIdNotifier.value;
    if (uid == null) return;
    final found = <int>{};
    for (final a in widget.attachments) {
      if (await EmailAttachmentCache.instance.cached(uid, a) != null) found.add(a.id);
    }
    if (mounted) setState(() => _onDevice..clear()..addAll(found));
  }

  Future<void> _open(EmailAttachment a) async {
    setState(() => _opening = a.id);
    await openEmailAttachment(context, widget.emailId, a);
    if (mounted) setState(() => _opening = null);
    _checkDevice();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.attachments.length} attachment${widget.attachments.length == 1 ? '' : 's'}',
          style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in widget.attachments)
          Material(
            color: pal.surface1,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: _opening == null ? () => _open(a) : null,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: pal.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _opening == a.id
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_iconFor(a.extension), size: 18, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                    Text('${a.sizeLabel}${_onDevice.contains(a.id) ? ' · on this device' : ''}',
                        style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
                  ])),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.file, required this.name});
  final File file;
  final String name;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Dialog(
      backgroundColor: pal.surface1,
      insetPadding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 8, 6), child: Row(children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStrong)),
          TextButton.icon(
            icon: const Icon(Symbols.download, size: 16),
            label: const Text('Save'),
            onPressed: () async {
              try {
                final saved = await DownloadManager.instance.save(await file.readAsBytes(), name);
                if (context.mounted) showSuccessToast(context, 'Saved to ${saved.path}');
              } catch (e) {
                if (context.mounted) showErrorToast(context, e);
              }
            },
          ),
          IconButton(icon: const Icon(Symbols.close, size: 18), onPressed: () => Navigator.of(context).pop()),
        ])),
        Flexible(child: InteractiveViewer(maxScale: 6, child: Image.file(file, fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Padding(padding: const EdgeInsets.all(30),
                child: Text('This image can\'t be shown.', style: AppTheme.bodySub))))),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ── Outgoing ────────────────────────────────────────────────────────────────

/// Server cap per email (EmailAttachmentStore::MAX_OUTGOING_BYTES).
const kMaxOutgoingAttachmentBytes = 22 * 1024 * 1024;

/// Picks files to send. Each is `{path, name, size}`, the shape the outbox
/// keeps (the upload token is added when it's sent).
Future<List<Map<String, dynamic>>> pickEmailFiles(BuildContext context) async {
  if (Platform.isAndroid) {
    showErrorToast(context, Exception('Attaching files isn\'t available on Android in this build.'));
    return const [];
  }
  final r = await FilePicker.pickFiles(allowMultiple: true, withData: false);
  if (r == null) return const [];
  return [
    for (final f in r.files)
      if (f.path != null) {'path': f.path!, 'name': f.name, 'size': f.size},
  ];
}

/// Adds picked files to [current], refusing the pick when the total would
/// pass the per-email limit. Returns whether anything was added.
bool addPickedFiles(BuildContext context, List<Map<String, dynamic>> current, List<Map<String, dynamic>> picked) {
  if (picked.isEmpty) return false;
  int total(List<Map<String, dynamic>> l) => l.fold(0, (a, f) => a + ((f['size'] as num?)?.toInt() ?? 0));
  if (total(current) + total(picked) > kMaxOutgoingAttachmentBytes) {
    showErrorToast(context, Exception('Attachments can total 22 MB per email.'));
    return false;
  }
  current.addAll(picked);
  return true;
}

/// Removable chips for the files about to be sent.
class OutgoingAttachmentChips extends StatelessWidget {
  const OutgoingAttachmentChips({super.key, required this.files, required this.onRemove});
  final List<Map<String, dynamic>> files;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    final pal = context.pal;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < files.length; i++)
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.only(left: 8, right: 2),
          decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: pal.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.attach_file, size: 14, color: pal.textMute),
            const SizedBox(width: 4),
            Flexible(child: Text(files[i]['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              icon: const Icon(Symbols.close),
              onPressed: () => onRemove(i),
            ),
          ]),
        ),
    ]);
  }
}
