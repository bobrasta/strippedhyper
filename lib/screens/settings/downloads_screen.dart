import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/download_manager.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/pdf_preview_dialog.dart';

// Lists whatever's actually on disk in <Downloads>/Hypermed/ — no separate
// manifest to drift out of sync — so PDFs saved via the "Download PDF"
// actions on Invoices/Quotations/etc. show up here to open or share.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<File> _files = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final files = await DownloadManager.instance.list();
      if (mounted) setState(() { _files = files; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _open(File f) async {
    if (f.path.toLowerCase().endsWith('.pdf')) return showPdfFilePreview(context, f);
    try {
      await DownloadManager.instance.open(f);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _share(File f) async {
    try {
      await DownloadManager.instance.share(f);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _delete(File f) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Delete file'),
      content: Text('Delete "${_name(f)}" from disk? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await DownloadManager.instance.delete(f);
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  String _name(File f) => f.path.split(Platform.pathSeparator).last;

  String _size(File f) {
    final bytes = f.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _modified(File f) {
    final m = f.lastModifiedSync();
    return '${m.day.toString().padLeft(2, '0')}/${m.month.toString().padLeft(2, '0')}/${m.year} '
        '${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Downloads', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('${_files.length} file${_files.length == 1 ? '' : 's'} saved to Downloads/Hypermed', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Symbols.refresh, size: 16), label: const Text('Refresh')),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
                  ? Center(child: Text(_error!, style: AppTheme.bodySub))
                  : _files.isEmpty
                      ? Center(child: Text('No downloads yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)))
                      : SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                          child: Column(children: _files.map((f) => _fileRow(context, f)).toList()),
                        ),
        ),
      ]);
    });
  }

  Widget _fileRow(BuildContext context, File f) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.border)),
    child: Row(children: [
      Icon(Symbols.picture_as_pdf, size: 20, color: AppColors.coral),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_name(f), style: AppTheme.bodyStrong.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text('${_size(f)} · ${_modified(f)}', style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
      ])),
      IconButton(onPressed: () => _open(f), icon: const Icon(Symbols.open_in_new, size: 17), tooltip: 'Open'),
      IconButton(onPressed: () => _share(f), icon: const Icon(Symbols.share, size: 17), tooltip: 'Share'),
      IconButton(onPressed: () => _delete(f), icon: Icon(Symbols.delete, size: 17, color: AppColors.coral), tooltip: 'Delete'),
    ]),
  );
}
