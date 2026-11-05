import 'package:dio/dio.dart';

import '../models/chat.dart';
import 'api_client.dart';

/// REST calls for in-app chat. The messaging routes live at /api/messaging,
/// beside the app's /api/v1, so paths are built from the API's origin.
/// Everything here is live data: never served from a cache.
class ChatService {
  ChatService._();
  static final instance = ChatService._();
  Dio get _dio => ApiClient.instance.dio;

  /// https://api.hypermed.co.tz (no path), from the app's API base URL.
  static String get origin {
    final u = Uri.parse(ApiClient.baseUrl);
    return u.replace(path: '', query: null, fragment: null).toString().replaceAll(RegExp(r'[?#]$'), '');
  }

  static String url(String path) => '$origin/api/messaging/$path';

  Options get _live => ApiClient.noCache;

  Future<ChatSettings> settings() async {
    final res = await _dio.get(url('settings'), options: _live);
    return ChatSettings.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  /// Newest activity first; [cursor] pages further back.
  Future<(List<Conversation>, String?)> conversations({String? cursor, int limit = 50}) async {
    final res = await _dio.get(url('conversations'),
        queryParameters: {'limit': limit, 'cursor': ?cursor}, options: _live);
    final (rows, meta) = ApiClient.unwrapList(res);
    return (
      [for (final r in rows) Conversation.fromJson(Map<String, dynamic>.from(r as Map))],
      meta?['next_cursor'] as String?,
    );
  }

  Future<Conversation> conversation(int id) async {
    final res = await _dio.get(url('conversations/$id'), options: _live);
    return Conversation.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<Conversation> openDirect(int userId) async {
    final res = await _dio.post(url('conversations/direct'), data: {'user_id': userId});
    return Conversation.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<Conversation> createGroup(String title, List<int> userIds) async {
    final res = await _dio.post(url('conversations/group'), data: {'title': title, 'user_ids': userIds});
    return Conversation.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<Conversation> addMembers(int conversationId, List<int> userIds) async {
    final res = await _dio.post(url('conversations/$conversationId/participants'), data: {'user_ids': userIds});
    return Conversation.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<void> leave(int conversationId, int myId) =>
      _dio.delete(url('conversations/$conversationId/participants/$myId'));

  Future<void> mute(int conversationId, DateTime? until) => _dio.post(
      url('conversations/$conversationId/mute'), data: {'muted_until': until?.toUtc().toIso8601String()});

  /// Newest first without a cursor or with [before]; oldest first with [after].
  Future<(List<ChatMessage>, bool)> messages(int conversationId, {int? before, int? after, int limit = 50}) async {
    final res = await _dio.get(url('conversations/$conversationId/messages'),
        queryParameters: {'limit': limit, 'before': ?before, 'after': ?after}, options: _live);
    final (rows, meta) = ApiClient.unwrapList(res);
    return (
      [for (final r in rows) ChatMessage.fromJson(Map<String, dynamic>.from(r as Map))],
      meta?['has_more'] == true,
    );
  }

  Future<ChatMessage> send(int conversationId, {required String clientUuid, required String body, int? replyToId}) async {
    final res = await _dio.post(url('conversations/$conversationId/messages'), data: {
      'client_uuid': clientUuid, 'type': 'text', 'body': body, 'reply_to_id': ?replyToId,
    });
    return ChatMessage.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<ChatMessage> sendFile(int conversationId, {required String clientUuid, required String path, String? caption}) async {
    final form = FormData.fromMap({
      'client_uuid': clientUuid,
      'file': await MultipartFile.fromFile(path),
      if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim(),
    });
    final res = await _dio.post(url('conversations/$conversationId/attachments'), data: form);
    return ChatMessage.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<ChatMessage> edit(int messageId, String body) async {
    final res = await _dio.patch(url('messages/$messageId'), data: {'body': body});
    return ChatMessage.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<ChatMessage> delete(int messageId) async {
    final res = await _dio.delete(url('messages/$messageId'));
    return ChatMessage.fromJson(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<int> markRead(int conversationId, int lastId) async {
    final res = await _dio.post(url('conversations/$conversationId/read'), data: {'last_read_message_id': lastId});
    final d = ApiClient.unwrap(res);
    return d is Map ? ((d['unread_count'] as num?)?.toInt() ?? 0) : 0;
  }

  Future<void> markDelivered(int conversationId, int lastId) =>
      _dio.post(url('conversations/$conversationId/delivered'), data: {'last_delivered_message_id': lastId});

  Future<int> unreadTotal() async {
    final res = await _dio.get(url('unread-summary'), options: _live);
    final d = ApiClient.unwrap(res);
    return d is Map ? ((d['total'] as num?)?.toInt() ?? 0) : 0;
  }

  /// Active staff the user can message (never themself).
  Future<List<ChatUser>> people(String search, {int limit = 30}) async {
    final res = await _dio.get(url('users'),
        queryParameters: {'limit': limit, if (search.trim().isNotEmpty) 'search': search.trim()}, options: _live);
    final (rows, _) = ApiClient.unwrapList(res);
    return [for (final r in rows) ChatUser.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  // ── Chat review (only while the Director has it switched on) ──────────────

  Future<(List<Conversation>, ChatUser?)> reviewConversations(int userId) async {
    final res = await _dio.get(url('audit/users/$userId/conversations'),
        queryParameters: {'limit': 50}, options: _live);
    final (rows, meta) = ApiClient.unwrapList(res);
    final subject = meta?['subject'] is Map ? ChatUser.fromJson(Map<String, dynamic>.from(meta!['subject'] as Map)) : null;
    return ([for (final r in rows) Conversation.fromJson(Map<String, dynamic>.from(r as Map))], subject);
  }

  Future<(List<ChatMessage>, bool)> reviewMessages(int conversationId, {int? before}) async {
    final res = await _dio.get(url('audit/conversations/$conversationId/messages'),
        queryParameters: {'limit': 100, 'before': ?before}, options: _live);
    final (rows, meta) = ApiClient.unwrapList(res);
    return (
      [for (final r in rows) ChatMessage.fromJson(Map<String, dynamic>.from(r as Map))],
      meta?['has_more'] == true,
    );
  }
}
