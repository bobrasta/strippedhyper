import 'package:dio/dio.dart';
import '../models/email.dart';
import 'api_client.dart';

class EmailService {
  EmailService._();
  static final instance = EmailService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see InventoryService for the full
  // reasoning. EmailScreen fetches a different folder's list via a
  // different method (inbox()/sent()/drafts()/folder()) rather than one
  // method with a folder param, so cache by the same folder key the
  // screen itself uses ('inbox', 'sent', 'drafts', or a server folder
  // name) instead of a single unfiltered-list field. Only inbox()'s fully
  // unfiltered call (no unread/search/accountId) is cached — a filtered
  // inbox view showing stale data from a different filter would be
  // misleading, same reasoning as InventoryService's own default-list cache.
  static final Map<String, List<Email>> cachedByFolder = {};

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<List<Email>> inbox({bool? unread, String? search, int? accountId, bool noCache = false}) async {
    final res = await _dio.get('/emails/inbox', queryParameters: {
      if (unread == true) 'unread':     '1',
      'search':     ?search,
      'account_id': ?accountId,
    }, options: noCache ? ApiClient.noCache : null);
    final (data, _) = ApiClient.unwrapList(res);
    final emails = data.map((j) => Email.fromJson(j as Map<String, dynamic>)).toList();
    if (unread != true && search == null && accountId == null) {
      cachedByFolder['inbox'] = emails;
    }
    return emails;
  }

  /// One page of a folder (100 a page), and whether more pages follow.
  /// The lists used to stop at the API's first 30 — nothing paged past them.
  Future<({List<Email> emails, bool hasMore})> page(String folder, int page, {String? search}) async {
    final path = switch (folder) {
      'inbox' || 'sent' || 'drafts' => '/emails/$folder',
      _ => '/emails/folder/$folder',
    };
    final q = search?.trim() ?? '';
    final res = await _dio.get(path, queryParameters: {'page': page, 'per_page': 100, if (q.isNotEmpty) 'search': q});
    final (data, meta) = ApiClient.unwrapList(res);
    final emails = data.map((j) => Email.fromJson(j as Map<String, dynamic>)).toList();
    if (page == 1 && q.isEmpty) cachedByFolder[folder] = emails;
    final current = (meta?['current_page'] as num?)?.toInt() ?? page;
    final last = (meta?['last_page'] as num?)?.toInt() ?? page;
    return (emails: emails, hasMore: current < last);
  }

  Future<List<Email>> sent()   => _folder('sent');
  Future<List<Email>> drafts() => _folder('drafts');

  Future<List<Email>> folder(String name) async {
    final res = await _dio.get('/emails/folder/$name');
    final (data, _) = ApiClient.unwrapList(res);
    final emails = data.map((j) => Email.fromJson(j as Map<String, dynamic>)).toList();
    cachedByFolder[name] = emails;
    return emails;
  }

  Future<List<Email>> _folder(String name) async {
    final res = await _dio.get('/emails/$name');
    final (data, _) = ApiClient.unwrapList(res);
    final emails = data.map((j) => Email.fromJson(j as Map<String, dynamic>)).toList();
    cachedByFolder[name] = emails;
    return emails;
  }

  /// One email with its attachments. [markRead] false leaves its read
  /// state alone (the list's own toggle handles that).
  Future<Email> get(int id, {bool markRead = true}) async {
    final res = await _dio.get('/emails/$id', queryParameters: {if (!markRead) 'mark_read': '0'});
    return Email.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  // ── Attachments ────────────────────────────────────────────────────────────

  /// Big files over a slow line need far longer than the default timeouts.
  static final _fileOptions = Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5));

  Future<List<int>> attachmentBytes(int emailId, int attachmentId) async {
    final res = await _dio.get<List<int>>('/emails/$emailId/attachments/$attachmentId',
        options: _fileOptions.copyWith(responseType: ResponseType.bytes));
    return res.data ?? const [];
  }

  /// Uploads one picked file for a later send; returns its token.
  Future<String> uploadAttachment(String path, String name) async {
    final res = await _dio.post('/emails/attachments',
        data: FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)}), options: _fileOptions);
    return (ApiClient.unwrap(res) as Map)['token'] as String;
  }

  /// Tokens for outgoing attachments (`{path, name, token?}` maps, as kept in
  /// the outbox). Files not uploaded yet are uploaded now and their token is
  /// written back, so a retry doesn't upload them again.
  Future<List<String>> _tokens(List<Map<String, dynamic>>? files) async {
    final tokens = <String>[];
    for (final f in files ?? const <Map<String, dynamic>>[]) {
      final token = f['token'] as String? ??
          await uploadAttachment(f['path'] as String, f['name'] as String);
      f['token'] = token;
      tokens.add(token);
    }
    return tokens;
  }

  Future<int> unreadCount({bool noCache = false}) async {
    try {
      final res = await _dio.get('/emails/unread-count',
          options: noCache ? ApiClient.noCache : null);
      final raw = ApiClient.unwrap(res);
      if (raw is Map) return (raw['unread'] as num? ?? 0).toInt();
    } catch (_) {}
    return 0;
  }

  // ── Sync ───────────────────────────────────────────────────────────────────

  /// Asks the API to pull new mail over IMAP — it never does on its own.
  /// [accountId] null syncs the default account. Returns how many messages
  /// came in; throws with the mail server's own reason (data.error).
  Future<int> sync({int? accountId, String folder = 'INBOX', int limit = 25}) async {
    try {
      final res = await _dio.post('/emails/sync', data: {'account_id': ?accountId, 'folder': folder, 'limit': limit});
      return ((res.data?['data']?['synced'] as num?) ?? 0).toInt();
    } on DioException catch (e) {
      final body = e.response?.data;
      final reason = body is Map && body['data'] is Map ? body['data']['error'] : null;
      if (reason is String && reason.isNotEmpty) throw Exception('Mail server: $reason');
      rethrow;
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> compose({
    required String to,
    String? cc,
    String? bcc,
    required String subject,
    required String body,
    List<Map<String, dynamic>>? attachments,
  }) async =>
      _dio.post('/emails/compose', data: {
        'to':      _splitAddrs(to),
        if (cc  != null && cc.trim().isNotEmpty)  'cc':  _splitAddrs(cc),
        if (bcc != null && bcc.trim().isNotEmpty) 'bcc': _splitAddrs(bcc),
        'subject': subject,
        'body':    body,
        'attachments': await _tokens(attachments),
      });

  Future<void> reply(int id, {required String body, bool replyAll = false, List<Map<String, dynamic>>? attachments}) async =>
      _dio.post('/emails/$id/reply', data: {'body': body, 'reply_all': replyAll, 'attachments': await _tokens(attachments)});

  /// The original email's attachments go along (server side).
  Future<void> forward(int id, {required String to, required String body, List<Map<String, dynamic>>? attachments}) async =>
      _dio.post('/emails/$id/forward', data: {'to': _splitAddrs(to), 'body': body, 'attachments': await _tokens(attachments)});

  static List<Map<String, String>> _splitAddrs(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)
          .map((e) => {'email': e}).toList();

  Future<void> toggleRead(int id)  => _dio.patch('/emails/$id/read');
  Future<void> toggleFlag(int id)  => _dio.patch('/emails/$id/flag');
  /// Removes an email for good (on the mail server too). The screen's
  /// Delete moves to Trash first; this is Trash's "Delete forever".
  Future<void> delete(int id)      => _dio.delete('/emails/$id');

  /// Moves an email to 'inbox', 'spam', 'trash', 'archive', or 'restore'
  /// (out of Trash/Spam: own mail to Sent, the rest to Inbox) — on the mail
  /// server too. The folder lists cached for this session are dropped.
  Future<void> move(int id, String to) async {
    await _dio.post('/emails/$id/move', data: {'to': to});
    cachedByFolder.clear();
  }
}
