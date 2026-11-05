import 'package:flutter/foundation.dart';

import '../main.dart' show emailBadgeNotifier, userIdNotifier;
import '../utils/api_error.dart';
import 'email_service.dart';
import 'local_db.dart';

/// Sends that failed (compose / reply / forward), kept so they can be
/// retried, edited or discarded instead of being lost. Stored in
/// LocalDb.outbox per user (in memory when there's no local store), and
/// counted in [emailBadgeNotifier]'s `failed`.
class EmailOutbox {
  EmailOutbox._();
  static final instance = EmailOutbox._();

  /// The signed-in user's failed sends, newest first.
  final entries = ValueNotifier<List<OutboxEntry>>(const []);

  // Fallback store when LocalDb isn't available.
  final _memory = <int, List<OutboxEntry>>{};
  int _memoryId = 0;

  /// Re-reads the signed-in user's entries (after login, logout or a wipe).
  void reload() {
    final uid = userIdNotifier.value;
    List<OutboxEntry> list;
    try {
      final db = LocalDb.instance;
      list = uid == null ? const [] : (db != null ? db.outbox(uid) : List.of(_memory[uid] ?? const []));
    } catch (_) {
      list = const [];
    }
    entries.value = list;
    emailBadgeNotifier.value = (unread: emailBadgeNotifier.value.unread, failed: list.length);
  }

  /// Saves a failed send — a new entry, or entry [id] again (the same
  /// dialog failing twice). Returns the entry's id.
  int? record({int? id, required String kind, required Map<String, dynamic> payload, required String error}) {
    final uid = userIdNotifier.value;
    if (uid == null) return id;
    try {
      final db = LocalDb.instance;
      if (db != null) {
        if (id != null) {
          db.updateOutbox(id, payload: payload, error: error);
        } else {
          id = db.addOutbox(uid, kind, payload, error);
        }
      } else {
        final list = _memory.putIfAbsent(uid, () => []);
        list.removeWhere((e) => e.id == id);
        id ??= --_memoryId;
        list.insert(0, OutboxEntry(id: id, kind: kind, payload: payload, error: error, createdAt: DateTime.now()));
      }
    } catch (_) {}
    reload();
    return id;
  }

  /// Drops entry [id] (sent after all, or discarded). Null is a no-op.
  void remove(int? id) {
    if (id == null) return;
    try {
      final db = LocalDb.instance;
      if (db != null) {
        db.removeOutbox(id);
      } else {
        for (final list in _memory.values) {
          list.removeWhere((e) => e.id == id);
        }
      }
    } catch (_) {}
    reload();
  }

  /// Sends [entry] again exactly as it was; removes it on success, keeps it
  /// with the new error (and rethrows) on failure.
  Future<void> retry(OutboxEntry entry) async {
    try {
      await send(entry.kind, entry.payload);
      remove(entry.id);
    } catch (e) {
      record(id: entry.id, kind: entry.kind, payload: entry.payload, error: friendlyError(e));
      rethrow;
    }
  }

  /// [p]'s `attachments` are `{path, name, token?}` maps; uploads write
  /// their token back into [p], so a retry reuses them.
  static Future<void> send(String kind, Map<String, dynamic> p) {
    final files = p['attachments'] == null
        ? null
        : [for (final a in p['attachments'] as List) Map<String, dynamic>.from(a as Map)];
    if (files != null) p['attachments'] = files;
    return switch (kind) {
      'reply' => EmailService.instance.reply((p['email_id'] as num).toInt(),
          body: p['body'] as String? ?? '', replyAll: p['reply_all'] == true, attachments: files),
      'forward' => EmailService.instance.forward((p['email_id'] as num).toInt(),
          to: p['to'] as String? ?? '', body: p['body'] as String? ?? '', attachments: files),
      _ => EmailService.instance.compose(
          to: p['to'] as String? ?? '',
          cc: p['cc'] as String?,
          bcc: p['bcc'] as String?,
          subject: p['subject'] as String? ?? '',
          body: p['body'] as String? ?? '',
          attachments: files),
    };
  }
}
