import 'package:flutter/material.dart';
import '../services/download_manager.dart';
import '../widgets/common/pdf_preview_dialog.dart';
import 'api_error.dart';

/// The shared behaviour behind every "Download PDF" action (invoices,
/// quotations, ...). PDFs open in the in-app preview, which has its own
/// Download button; other formats (.xlsx, .docx) save straight to
/// `<Downloads>/Hypermed/`.
Future<void> downloadPdf(BuildContext context, Future<List<int>> Function() fetchBytes, String filename) async {
  if (filename.toLowerCase().endsWith('.pdf')) return showPdfPreview(context, fetchBytes, filename);
  try {
    final bytes = await fetchBytes();
    final file = await DownloadManager.instance.save(bytes, filename);
    if (context.mounted) showSuccessToast(context, 'Saved to ${file.path}');
  } catch (e) {
    if (context.mounted) showErrorToast(context, e);
  }
}
