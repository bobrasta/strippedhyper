import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Saves generated documents (invoice/quotation PDFs, etc.) straight to disk
/// — a "Hypermed" subfolder inside the OS Downloads directory — instead of
/// opening them in a browser tab. The Downloads screen lists this same
/// folder directly rather than keeping a separate manifest, so it can never
/// drift from what's actually on disk.
class DownloadManager {
  DownloadManager._();
  static final instance = DownloadManager._();

  Future<Directory> _folder() async {
    final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Hypermed');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes [bytes] to `<Downloads>/Hypermed/<filename>`, overwriting any
  /// existing file with the same name (re-downloading a document is
  /// expected to refresh it, not pile up duplicates).
  Future<File> save(List<int> bytes, String filename) async {
    final dir = await _folder();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Newest first.
  Future<List<File>> list() async {
    final dir = await _folder();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<void> open(File file) => launchUrl(Uri.file(file.path));

  Future<void> share(File file) => Share.shareXFiles([XFile(file.path)]);

  Future<void> delete(File file) => file.delete();
}
