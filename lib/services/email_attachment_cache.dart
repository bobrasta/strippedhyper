import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/email.dart';
import 'email_service.dart';

/// Email attachments kept on this device after the first open, so opening
/// one again is instant and works without a connection.
///
/// Files live under `<app support>/email_attachments/<user>/<attachment>/<name>`.
/// An attachment id's content never changes on the server,
/// so a cached copy never goes stale. Least recently opened files go first
/// once the folder passes [maxBytes]; [wipeUser] runs with the rest of the
/// user's local data on logout.
class EmailAttachmentCache {
  EmailAttachmentCache._();
  static final instance = EmailAttachmentCache._();

  static const maxBytes = 500 * 1024 * 1024;

  /// Overridable in tests.
  Future<Directory> Function() rootDir = () async =>
      Directory('${(await getApplicationSupportDirectory()).path}/email_attachments');

  Future<File> _file(int userId, EmailAttachment a) async =>
      File('${(await rootDir()).path}/$userId/${a.id}/${a.filename}');

  /// The cached copy, or null.
  Future<File?> cached(int userId, EmailAttachment a) async {
    final f = await _file(userId, a);
    return await f.exists() ? f : null;
  }

  /// The attachment as a local file: from the device when it's there,
  /// otherwise downloaded once and kept.
  Future<File> get(int userId, int emailId, EmailAttachment a) async {
    final f = await _file(userId, a);
    if (await f.exists()) {
      // Opening it counts as use for the least-recently-used trim.
      try { await f.setLastModified(DateTime.now()); } catch (_) {}
      return f;
    }
    final bytes = await EmailService.instance.attachmentBytes(emailId, a.id);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    await trim();
    return f;
  }

  /// Drops least recently opened files until the cache fits [limit].
  Future<void> trim({int limit = maxBytes}) async {
    final root = await rootDir();
    if (!await root.exists()) return;
    final files = <File>[];
    var total = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) {
        files.add(e);
        total += await e.length();
      }
    }
    if (total <= limit) return;
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final f in files) {
      if (total <= limit) break;
      total -= await f.length();
      try {
        await f.delete();
        if (await f.parent.list().isEmpty) await f.parent.delete();
      } catch (_) {}
    }
  }

  Future<void> wipeUser(int userId) async {
    final dir = Directory('${(await rootDir()).path}/$userId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
