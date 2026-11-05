import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// One failed email send kept for Retry / Edit / Discard.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.error,
    required this.createdAt,
  });

  final int id;
  /// 'compose' | 'reply' | 'forward'.
  final String kind;
  final Map<String, dynamic> payload;
  final String? error;
  final DateTime createdAt;
}

/// The app's local SQLite store (`hypermed_local.db` in the application
/// support directory): settings/markers (`kv`), the persisted GET response
/// cache (`responses`) and failed email sends (`outbox`).
///
/// Everything here is optional: when the file can't be opened (tests, a
/// read-only profile) [instance] stays null and callers fall back to the
/// network / in-memory behaviour they had before.
///
/// kv scope is the user id as a string, or [appScope] for data that is not
/// tied to an account (trial status, the remembered server IP). Only the
/// app scope survives [wipeUser]/[wipeAll].
class LocalDb {
  LocalDb._(this._db) {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = NORMAL');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS kv (
        scope TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (scope, key)
      )''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS responses (
        user_id INTEGER NOT NULL,
        key TEXT NOT NULL,
        body BLOB NOT NULL,
        fetched_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, key)
      )''');
    _db.execute('CREATE INDEX IF NOT EXISTS responses_fetched ON responses (fetched_at)');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        error TEXT,
        created_at INTEGER NOT NULL
      )''');
  }

  static const appScope = 'app';
  static const fileName = 'hypermed_local.db';

  /// Responses older than this are dropped by [prune].
  static const maxResponseAge = Duration(days: 30);
  /// Total response bytes kept; the least recently fetched go first.
  static const maxResponseBytes = 150 * 1024 * 1024;

  final Database _db;
  int _putsSincePrune = 0;

  static LocalDb? instance;

  /// Opens the on-disk store and sets [instance]. Never throws — returns
  /// null (and leaves [instance] null) if the file can't be opened.
  static Future<LocalDb?> open() async {
    if (instance != null) return instance;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final db = LocalDb._(sqlite3.open('${dir.path}/$fileName'));
      db.prune();
      return instance = db;
    } catch (e) {
      dev.log('LocalDb unavailable: $e', name: 'LocalDb');
      return null;
    }
  }

  /// A throwaway in-memory store (tests).
  static LocalDb openInMemory() => LocalDb._(sqlite3.openInMemory());

  void close() => _db.close();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ── kv ──────────────────────────────────────────────────────────────────────

  String? getValue(String scope, String key) {
    final rows = _db.select('SELECT value FROM kv WHERE scope = ? AND key = ?', [scope, key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setValue(String scope, String key, String value) => _db.execute(
        'INSERT INTO kv (scope, key, value, updated_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT (scope, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
        [scope, key, value, _now()],
      );

  void removeValue(String scope, String key) =>
      _db.execute('DELETE FROM kv WHERE scope = ? AND key = ?', [scope, key]);

  Object? getJson(String scope, String key) {
    final raw = getValue(scope, key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void setJson(String scope, String key, Object? value) => setValue(scope, key, jsonEncode(value));

  // ── responses ───────────────────────────────────────────────────────────────

  ({Uint8List body, DateTime fetchedAt})? getResponse(int userId, String key) {
    final rows = _db.select(
        'SELECT body, fetched_at FROM responses WHERE user_id = ? AND key = ?', [userId, key]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      body: row['body'] as Uint8List,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
    );
  }

  void putResponse(int userId, String key, Uint8List body, {DateTime? fetchedAt}) {
    _db.execute(
      'INSERT INTO responses (user_id, key, body, fetched_at) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (user_id, key) DO UPDATE SET body = excluded.body, fetched_at = excluded.fetched_at',
      [userId, key, body, (fetchedAt ?? DateTime.now()).millisecondsSinceEpoch],
    );
    if (++_putsSincePrune >= 200) prune();
  }

  /// Drops responses older than [maxAge], then the least recently fetched
  /// until the rest fit in [maxBytes].
  void prune({Duration maxAge = maxResponseAge, int maxBytes = maxResponseBytes, DateTime? now}) {
    _putsSincePrune = 0;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge).millisecondsSinceEpoch;
    _db.execute('DELETE FROM responses WHERE fetched_at < ?', [cutoff]);
    final total = _db.select('SELECT COALESCE(SUM(LENGTH(body)), 0) AS n FROM responses').first['n'] as int;
    if (total <= maxBytes) return;
    // Keep the newest rows whose running total fits; delete the rest.
    _db.execute('''
      DELETE FROM responses WHERE rowid IN (
        SELECT rowid FROM (
          SELECT rowid, SUM(LENGTH(body)) OVER (ORDER BY fetched_at DESC, rowid DESC) AS running
          FROM responses
        ) WHERE running > ?
      )''', [maxBytes]);
  }

  // ── outbox ──────────────────────────────────────────────────────────────────

  int addOutbox(int userId, String kind, Map<String, dynamic> payload, String? error) {
    _db.execute(
      'INSERT INTO outbox (user_id, kind, payload, error, created_at) VALUES (?, ?, ?, ?, ?)',
      [userId, kind, jsonEncode(payload), error, _now()],
    );
    return _db.lastInsertRowId;
  }

  void updateOutbox(int id, {Map<String, dynamic>? payload, String? error}) => _db.execute(
        'UPDATE outbox SET payload = COALESCE(?, payload), error = ? WHERE id = ?',
        [payload == null ? null : jsonEncode(payload), error, id],
      );

  void removeOutbox(int id) => _db.execute('DELETE FROM outbox WHERE id = ?', [id]);

  List<OutboxEntry> outbox(int userId) => [
        for (final r in _db.select(
            'SELECT id, kind, payload, error, created_at FROM outbox WHERE user_id = ? ORDER BY id DESC',
            [userId]))
          OutboxEntry(
            id: r['id'] as int,
            kind: r['kind'] as String,
            payload: (jsonDecode(r['payload'] as String) as Map).cast<String, dynamic>(),
            error: r['error'] as String?,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          ),
      ];

  int outboxCount(int userId) =>
      _db.select('SELECT COUNT(*) AS n FROM outbox WHERE user_id = ?', [userId]).first['n'] as int;

  // ── wipe ────────────────────────────────────────────────────────────────────

  /// Removes everything stored for [userId]: cached responses, their kv
  /// (permissions, last-seen markers) and failed sends.
  void wipeUser(int userId) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM responses WHERE user_id = ?', [userId]);
      _db.execute('DELETE FROM outbox WHERE user_id = ?', [userId]);
      _db.execute('DELETE FROM kv WHERE scope = ?', ['$userId']);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Removes every user's data; only [appScope] kv survives.
  void wipeAll() {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM responses');
      _db.execute('DELETE FROM outbox');
      _db.execute('DELETE FROM kv WHERE scope <> ?', [appScope]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
