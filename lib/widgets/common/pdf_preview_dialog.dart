import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../services/download_manager.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import 'phone_layout.dart';

/// Opens an in-app PDF viewer. [fetchBytes] runs inside the dialog so the
/// viewer appears immediately with a spinner instead of the caller blocking.
/// Download saves to `<Downloads>/Hypermed/` (same as before previews
/// existed); Open hands the saved file to the OS viewer, which is also the
/// route to printing.
Future<void> showPdfPreview(
  BuildContext context,
  Future<List<int>> Function() fetchBytes,
  String filename, {
  bool alreadySaved = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PdfPreviewDialog(fetchBytes: fetchBytes, filename: filename, alreadySaved: alreadySaved),
  );
}

/// Previews a PDF that is already on disk (Downloads screen).
Future<void> showPdfFilePreview(BuildContext context, File file) =>
    showPdfPreview(context, file.readAsBytes, file.path.split(Platform.pathSeparator).last, alreadySaved: true);

class PdfPreviewDialog extends StatefulWidget {
  const PdfPreviewDialog({super.key, required this.fetchBytes, required this.filename, this.alreadySaved = false});
  final Future<List<int>> Function() fetchBytes;
  final String filename;
  final bool alreadySaved;

  @override
  State<PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<PdfPreviewDialog> {
  final _controller = PdfViewerController();
  Uint8List? _bytes;
  Object? _error;
  File? _saved;
  bool _busy = false;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _bytes = null;
    });
    try {
      final b = await widget.fetchBytes();
      if (mounted) setState(() => _bytes = b is Uint8List ? b : Uint8List.fromList(b));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<File> _ensureSaved() async => _saved ??= await DownloadManager.instance.save(_bytes!, widget.filename);

  Future<void> _run(BuildContext ctx, Future<void> Function() action) async {
    if (_bytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (ctx.mounted) showErrorToast(ctx, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final ready = _bytes != null;
    // Phones: full-screen, icon-only actions, pinch instead of zoom buttons.
    final phone = isPhoneWidth(MediaQuery.sizeOf(context).width);
    return Dialog(
      backgroundColor: pal.surface1,
      insetPadding: phone ? EdgeInsets.zero : const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(phone ? 0 : 12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        // Own messenger so Saved/error toasts render above the dialog, not
        // behind its barrier on the root Scaffold.
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Builder(
              builder: (context) => Column(
                children: [
                  Container(
                    padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 10, phone ? 4 : 8, 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: pal.border)),
                    ),
                    child: Row(
                      children: [
                        Icon(Symbols.picture_as_pdf, size: 20, color: AppColors.coral),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.filename,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text),
                          ),
                        ),
                        if (_pages > 0) ...[
                          Text('$_page / $_pages', style: TextStyle(fontSize: 13, color: pal.textMute)),
                          const SizedBox(width: 8),
                          if (!phone) ...[
                            IconButton(
                              tooltip: 'Zoom out',
                              icon: const Icon(Symbols.zoom_out, size: 20),
                              onPressed: () => _controller.zoomDown(),
                            ),
                            IconButton(
                              tooltip: 'Zoom in',
                              icon: const Icon(Symbols.zoom_in, size: 20),
                              onPressed: () => _controller.zoomUp(),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                        if (!widget.alreadySaved)
                          _ToolbarButton(
                            compact: phone,
                            icon: Symbols.download,
                            label: _saved == null ? 'Download' : 'Saved',
                            onPressed: ready && !_busy
                                ? () => _run(context, () async {
                                    final f = await _ensureSaved();
                                    if (context.mounted) showSuccessToast(context, 'Saved to ${f.path}');
                                  })
                                : null,
                          ),
                        _ToolbarButton(
                          compact: phone,
                          icon: Symbols.print,
                          label: 'Open / print',
                          onPressed: ready && !_busy
                              ? () => _run(context, () async {
                                  await DownloadManager.instance.open(await _ensureSaved());
                                })
                              : null,
                        ),
                        _ToolbarButton(
                          compact: phone,
                          icon: Symbols.share,
                          label: 'Share',
                          onPressed: ready && !_busy
                              ? () => _run(context, () async {
                                  await DownloadManager.instance.share(await _ensureSaved());
                                })
                              : null,
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Symbols.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _body(pal)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppPalette pal) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.error, size: 32, color: AppColors.coral),
            const SizedBox(height: 8),
            Text(
              friendlyError(_error!),
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textMute),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_bytes == null) return const Center(child: CircularProgressIndicator());
    return PdfViewer.data(
      _bytes!,
      sourceName: widget.filename,
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: pal.surface3,
        onViewerReady: (doc, _) => setState(() {
          _pages = doc.pages.length;
          _page = 1;
        }),
        onPageChanged: (n) {
          if (n != null) setState(() => _page = n);
        },
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.label, required this.onPressed, this.compact = false});
  final bool compact;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon, size: 20))
      : Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label)),
        );
}
