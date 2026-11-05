// In-app chat (hypermed-api packages/hypermed/messaging, /api/messaging).
// Shapes follow the package's contract: ids are ints, times ISO-8601 UTC.

DateTime? _time(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

class ChatUser {
  const ChatUser({required this.id, required this.name, this.avatarUrl});
  final int id;
  final String name;
  final String? avatarUrl;

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
        id: _int(j['id']) ?? 0,
        name: (j['name'] as String?) ?? '',
        avatarUrl: j['avatar_url'] as String?,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class ChatParticipant extends ChatUser {
  const ChatParticipant({
    required super.id,
    required super.name,
    super.avatarUrl,
    this.role = 'member',
    this.lastReadId,
    this.lastDeliveredId,
  });
  final String role;
  final int? lastReadId;
  final int? lastDeliveredId;

  factory ChatParticipant.fromJson(Map<String, dynamic> j) => ChatParticipant(
        id: _int(j['id']) ?? 0,
        name: (j['name'] as String?) ?? '',
        avatarUrl: j['avatar_url'] as String?,
        role: (j['role'] as String?) ?? 'member',
        lastReadId: _int(j['last_read_message_id']),
        lastDeliveredId: _int(j['last_delivered_message_id']),
      );

  ChatParticipant copyWith({int? lastReadId, int? lastDeliveredId}) => ChatParticipant(
        id: id, name: name, avatarUrl: avatarUrl, role: role,
        lastReadId: lastReadId ?? this.lastReadId,
        lastDeliveredId: lastDeliveredId ?? this.lastDeliveredId,
      );
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.mime,
    required this.size,
    required this.name,
    required this.isImage,
    required this.url,
    this.thumbUrl,
  });
  final int id;
  final String mime;
  final int size;
  final String name;
  final bool isImage;
  final String url;
  final String? thumbUrl;

  factory ChatAttachment.fromJson(Map<String, dynamic> j) => ChatAttachment(
        id: _int(j['id']) ?? 0,
        mime: (j['mime'] as String?) ?? '',
        size: _int(j['size']) ?? 0,
        name: (j['original_name'] as String?) ?? 'file',
        isImage: j['is_image'] == true,
        url: (j['url'] as String?) ?? '',
        thumbUrl: j['thumb_url'] as String?,
      );

  String get sizeLabel {
    if (size >= 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (size >= 1024) return '${(size / 1024).round()} KB';
    return '$size B';
  }
}

/// Where an own message is: still sending, failed, on the server, reached
/// everyone's device, or read by everyone.
enum SendState { sending, failed, sent, delivered, read }

/// An earlier text of an edited message (chat review only).
class ChatRevision {
  const ChatRevision(this.body, this.replacedAt);
  final String? body;
  final DateTime? replacedAt;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sender,
    required this.type,
    required this.body,
    required this.clientUuid,
    required this.createdAt,
    this.meta,
    this.replyToId,
    this.replyPreview,
    this.replySender,
    this.attachments = const [],
    this.isDeleted = false,
    this.editedAt,
    this.deletedAt,
    this.revisions = const [],
    this.localState,
    this.localFilePath,
  });

  /// 0 while it only exists on this device (sending / failed).
  final int id;
  final int conversationId;
  final int? senderId;
  final ChatUser? sender;
  final String type; // text | file | system | entity_ref
  final String? body;
  final Map<String, dynamic>? meta;
  final String clientUuid;
  final int? replyToId;
  final String? replyPreview;
  final String? replySender;
  final List<ChatAttachment> attachments;
  final bool isDeleted;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final List<ChatRevision> revisions;
  final DateTime createdAt;
  /// Set only for messages this device is sending (sending / failed).
  final SendState? localState;
  /// A file waiting to be (re)sent.
  final String? localFilePath;

  bool get isSystem => type == 'system';
  bool get isPending => id == 0;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final reply = j['reply_to'] is Map ? Map<String, dynamic>.from(j['reply_to'] as Map) : null;
    final sender = j['sender'] is Map ? ChatUser.fromJson(Map<String, dynamic>.from(j['sender'] as Map)) : null;
    return ChatMessage(
      id: _int(j['id']) ?? 0,
      conversationId: _int(j['conversation_id']) ?? 0,
      senderId: _int(j['sender_id']),
      sender: sender,
      type: (j['type'] as String?) ?? 'text',
      body: j['body'] as String?,
      meta: j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : null,
      clientUuid: (j['client_uuid'] as String?) ?? '',
      replyToId: _int(j['reply_to_id']),
      replyPreview: reply == null ? null : (reply['is_deleted'] == true ? 'Message deleted' : reply['body'] as String?),
      replySender: reply?['sender_name'] as String?,
      attachments: [
        for (final a in (j['attachments'] as List? ?? const []))
          ChatAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      isDeleted: j['is_deleted'] == true,
      editedAt: _time(j['edited_at']),
      deletedAt: _time(j['deleted_at']),
      revisions: [
        for (final r in (j['revisions'] as List? ?? const []))
          if (r is Map) ChatRevision(r['body'] as String?, _time(r['replaced_at'])),
      ],
      createdAt: _time(j['created_at']) ?? DateTime.now(),
    );
  }

  ChatMessage copyWith({SendState? localState, bool clearLocal = false}) => ChatMessage(
        id: id, conversationId: conversationId, senderId: senderId, sender: sender, type: type,
        body: body, meta: meta, clientUuid: clientUuid, replyToId: replyToId,
        replyPreview: replyPreview, replySender: replySender, attachments: attachments,
        isDeleted: isDeleted, editedAt: editedAt, deletedAt: deletedAt, revisions: revisions,
        createdAt: createdAt, localFilePath: clearLocal ? null : localFilePath,
        localState: clearLocal ? null : (localState ?? this.localState),
      );

  /// One-line preview for the chat list.
  String get preview {
    if (isDeleted) return 'Message deleted';
    if (type == 'file') {
      final names = attachments.map((a) => a.name).join(', ');
      final caption = (body ?? '').trim();
      return caption.isNotEmpty ? caption : (names.isNotEmpty ? '📎 $names' : '📎 File');
    }
    return (body ?? '').replaceAll('\n', ' ');
  }
}

class Conversation {
  Conversation({
    required this.id,
    required this.type,
    required this.title,
    required this.lastActivityAt,
    required this.lastMessage,
    required this.unreadCount,
    required this.myRole,
    required this.mutedUntil,
    required this.participantCount,
    required this.participants,
  });
  final int id;
  final String type; // direct | group | department | entity
  final String? title;
  final DateTime? lastActivityAt;
  final ChatMessage? lastMessage;
  int unreadCount;
  final String myRole;
  final DateTime? mutedUntil;
  final int participantCount;
  final List<ChatParticipant> participants;

  bool get isDirect => type == 'direct';
  bool get isMuted => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: _int(j['id']) ?? 0,
        type: (j['type'] as String?) ?? 'direct',
        title: j['title'] as String?,
        lastActivityAt: _time(j['last_activity_at']),
        lastMessage: j['last_message'] is Map
            ? ChatMessage.fromJson(Map<String, dynamic>.from(j['last_message'] as Map))
            : null,
        unreadCount: _int(j['unread_count']) ?? 0,
        myRole: (j['my_role'] as String?) ?? 'member',
        mutedUntil: _time(j['muted_until']),
        participantCount: _int(j['participant_count']) ?? 0,
        participants: [
          for (final p in (j['participants'] as List? ?? const []))
            ChatParticipant.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );

  /// The other person in a direct chat.
  ChatParticipant? other(int? me) {
    for (final p in participants) {
      if (p.id != me) return p;
    }
    return null;
  }

  String displayName(int? me) {
    if (isDirect) return other(me)?.name ?? 'Chat';
    final t = (title ?? '').trim();
    return t.isNotEmpty ? t : participants.map((p) => p.name.split(' ').first).join(', ');
  }
}

/// What GET /api/messaging/settings says about this deployment.
class ChatSettings {
  const ChatSettings({
    this.auditEnabled = false,
    this.canAudit = false,
    this.realtimeKey,
    this.realtimeHost,
    this.realtimePort = 443,
    this.realtimeTls = true,
    this.authPath = '/api/broadcasting/auth',
  });
  final bool auditEnabled;
  final bool canAudit;
  final String? realtimeKey;
  final String? realtimeHost;
  final int realtimePort;
  final bool realtimeTls;
  final String authPath;

  bool get hasRealtime => realtimeKey != null && realtimeKey!.isNotEmpty && realtimeHost != null;

  factory ChatSettings.fromJson(Map<String, dynamic> j) {
    final rt = j['realtime'] is Map ? Map<String, dynamic>.from(j['realtime'] as Map) : null;
    return ChatSettings(
      auditEnabled: j['audit_enabled'] == true,
      canAudit: j['can_audit'] == true,
      realtimeKey: rt?['key'] as String?,
      realtimeHost: rt?['host'] as String?,
      realtimePort: _int(rt?['port']) ?? 443,
      realtimeTls: rt?['tls'] != false,
      authPath: (rt?['auth_path'] as String?) ?? '/api/broadcasting/auth',
    );
  }
}
