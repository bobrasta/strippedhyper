import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart' show userIdNotifier;
import '../models/chat.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'phone_notifications.dart';

/// Unread chat messages across all conversations — the top-bar badge.
final chatUnreadNotifier = ValueNotifier<int>(0);

/// False until the API answers GET /api/messaging/settings: an API without
/// the messaging module (older server) shows no chat button at all.
final chatAvailableNotifier = ValueNotifier<bool>(false);

/// True while the Chats menu screen is showing: the floating button hides.
final chatScreenOpenNotifier = ValueNotifier<bool>(false);

/// Everything the chat panel shows, kept while the shell is open.
///
/// Live updates come over [ChatRealtime]. While that is down (Reverb not set
/// up yet, or the line dropped) it polls instead: the chat list every 15 s
/// and the open chat every 4 s, so nothing is ever missed, only later.
class ChatController extends ChangeNotifier {
  ChatController({ChatService? service}) : _api = service ?? ChatService.instance;
  static final instance = ChatController();

  static const listPoll = Duration(seconds: 15);
  static const openChatPoll = Duration(seconds: 4);
  static const livePoll = Duration(minutes: 2); // safety net while live

  final ChatService _api;
  ChatRealtime? _rt;
  StreamSubscription<ChatEvent>? _eventSub;
  StreamSubscription<bool>? _connSub;
  Timer? _listTimer;
  Timer? _chatTimer;
  bool _running = false;
  int _generation = 0;

  ChatSettings settings = const ChatSettings();
  List<Conversation> conversations = [];
  bool loadingList = false;
  String? listError;
  bool get live => _rt?.isConnected ?? false;

  int? get me => userIdNotifier.value;

  // Open chat
  int? openId;
  List<ChatMessage> messages = []; // oldest first
  bool loadingMessages = false;
  bool hasOlder = false;
  String? messagesError;
  Conversation? get open => conversations.where((c) => c.id == openId).firstOrNull;

  /// Set when a desktop pop-up was clicked: the shell opens the panel on it.
  final openRequests = ValueNotifier<int?>(null);
  // How many chat views are on screen (dock window, phone page, Chats
  // screen): while any is, the open chat is read and gets no pop-ups.
  int _views = 0;
  // Backgrounded app: nothing is on screen even if a chat is open.
  bool _foreground = true;
  AppLifecycleListener? _lifecycle;
  bool get panelVisible => _views > 0 && _foreground;
  void attachView() => _views++;
  void detachView() => _views = max(0, _views - 1);

  // Highest message id seen per conversation: anything above it is new.
  final _seen = <int, int>{};
  final _deliveredSent = <int, int>{};
  Timer? _deliveredDebounce;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final gen = ++_generation;
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        _foreground = true;
        nudge(); // reconnect / catch up after the phone slept
        unawaited(markOpenRead());
      },
      onPause: () => _foreground = false,
      onHide: () => _foreground = false,
      onShow: () => _foreground = true,
    );
    try {
      settings = await _api.settings();
    } catch (_) {
      // No messaging on this server (or offline at start): try again later.
      if (_running && gen == _generation) {
        _listTimer = Timer(const Duration(minutes: 2), () {
          if (_running && gen == _generation) {
            _running = false;
            unawaited(start());
          }
        });
      }
      return;
    }
    if (!_running || gen != _generation) return;
    chatAvailableNotifier.value = true;
    await refreshList(baseline: true);
    if (!_running || gen != _generation) return;
    _connectRealtime();
    _schedulePolls();
  }

  Future<void> stop() async {
    _running = false;
    _generation++;
    _listTimer?.cancel();
    _chatTimer?.cancel();
    _deliveredDebounce?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    _foreground = true;
    await _eventSub?.cancel();
    await _connSub?.cancel();
    final rt = _rt;
    _rt = null;
    await rt?.close();
    conversations = [];
    messages = [];
    openId = null;
    _seen.clear();
    _deliveredSent.clear();
    settings = const ChatSettings();
    chatUnreadNotifier.value = 0;
    chatAvailableNotifier.value = false;
    openRequests.value = null;
    notifyListeners();
  }

  /// After the Director flips chat review: the notice and review access follow.
  Future<void> reloadSettings() async {
    try {
      settings = await _api.settings();
      chatAvailableNotifier.value = true;
      notifyListeners();
    } catch (_) {}
  }

  void _connectRealtime() {
    if (!settings.hasRealtime) return;
    final rt = ChatRealtime(settings);
    _rt = rt;
    _eventSub = rt.events.listen(_onEvent);
    _connSub = rt.connectedChanges.listen((up) {
      _schedulePolls();
      notifyListeners();
      // Catch up on whatever happened while the line was down.
      if (up) {
        unawaited(refreshList());
        if (openId != null) unawaited(_fetchNewer());
      }
    });
    final uid = me;
    if (uid != null) rt.subscribe('private-messaging.user.$uid');
    rt.subscribe('presence-messaging.presence');
    rt.connect();
  }

  void _schedulePolls() {
    _listTimer?.cancel();
    _chatTimer?.cancel();
    if (!_running) return;
    _listTimer = Timer.periodic(live ? livePoll : listPoll, (_) => refreshList());
    if (!live) {
      _chatTimer = Timer.periodic(openChatPoll, (_) {
        if (openId != null && panelVisible) unawaited(_fetchNewer());
      });
    }
  }

  // ── Chat list ─────────────────────────────────────────────────────────────

  Future<void> refreshList({bool baseline = false}) async {
    if (conversations.isEmpty) {
      loadingList = true;
      notifyListeners();
    }
    try {
      final (list, _) = await _api.conversations();
      listError = null;
      _announceNew(list, quiet: baseline);
      conversations = list;
      _updateUnread();
      _ackDelivered(list);
    } catch (e) {
      listError = '$e';
    } finally {
      loadingList = false;
      notifyListeners();
    }
  }

  void _updateUnread() {
    chatUnreadNotifier.value = conversations.fold(0, (s, c) => s + c.unreadCount);
  }

  /// Pop-ups for messages newer than what this device has already seen.
  void _announceNew(List<Conversation> list, {bool quiet = false}) {
    final fresh = <(Conversation, ChatMessage)>[];
    for (final c in list) {
      final last = c.lastMessage;
      if (last == null) continue;
      final seen = _seen[c.id];
      _seen[c.id] = max(seen ?? 0, last.id);
      // The first load only records where each chat is; after that, a chat
      // never seen before (someone just wrote to us) counts as new.
      if (quiet) continue;
      if (seen != null && last.id <= seen) continue;
      if (last.senderId == me || last.isSystem || c.isMuted || c.unreadCount == 0) continue;
      if (panelVisible && c.id == openId) continue;
      fresh.add((c, last));
    }
    if (fresh.isEmpty) return;
    if (fresh.length > 3) {
      _toast('${fresh.length} new chat messages', 'Open Hypermed to read them.', null);
      return;
    }
    for (final (c, m) in fresh) {
      final who = m.sender?.name ?? 'New message';
      final title = c.isDirect ? who : '$who · ${c.displayName(me)}';
      _toast(title, m.preview, c.id);
    }
  }

  // Tell senders their messages reached this device (✓✓).
  void _ackDelivered(List<Conversation> list) {
    for (final c in list) {
      final last = c.lastMessage;
      if (last == null || last.senderId == me || c.unreadCount == 0) continue;
      if ((_deliveredSent[c.id] ?? 0) >= last.id) continue;
      _deliveredSent[c.id] = last.id;
      unawaited(_api.markDelivered(c.id, last.id).catchError((_) {}));
    }
  }

  // ── Open chat ─────────────────────────────────────────────────────────────

  Future<void> openChat(int conversationId) async {
    if (openId != null && openId != conversationId) _rt?.unsubscribe('private-messaging.conversation.$openId');
    openId = conversationId;
    messages = [];
    hasOlder = false;
    messagesError = null;
    loadingMessages = true;
    notifyListeners();
    _rt?.subscribe('private-messaging.conversation.$conversationId');
    try {
      final (rows, more) = await _api.messages(conversationId);
      if (openId != conversationId) return;
      messages = rows.reversed.toList();
      hasOlder = more;
      if (!conversations.any((c) => c.id == conversationId)) {
        conversations = [await _api.conversation(conversationId), ...conversations];
      }
    } catch (e) {
      if (openId == conversationId) messagesError = '$e';
    } finally {
      if (openId == conversationId) {
        loadingMessages = false;
        notifyListeners();
        unawaited(markOpenRead());
      }
    }
  }

  void closeChat() {
    if (openId != null) _rt?.unsubscribe('private-messaging.conversation.$openId');
    openId = null;
    messages = [];
    notifyListeners();
  }

  Future<void> loadOlder() async {
    final id = openId;
    if (id == null || !hasOlder || loadingMessages || messages.isEmpty) return;
    loadingMessages = true;
    notifyListeners();
    try {
      final firstId = messages.firstWhere((m) => !m.isPending, orElse: () => messages.first).id;
      final (rows, more) = await _api.messages(id, before: firstId);
      if (openId != id) return;
      messages = [...rows.reversed, ...messages];
      hasOlder = more;
    } catch (_) {
    } finally {
      loadingMessages = false;
      notifyListeners();
    }
  }

  int get _lastServerId => messages.lastWhere((m) => !m.isPending, orElse: () => ChatMessage(
      id: 0, conversationId: 0, senderId: null, sender: null, type: 'text', body: null,
      clientUuid: '', createdAt: DateTime(2000))).id;

  Future<void> _fetchNewer() async {
    final id = openId;
    if (id == null || loadingMessages) return;
    try {
      final (rows, _) = await _api.messages(id, after: _lastServerId, limit: 100);
      if (openId != id || rows.isEmpty) return;
      for (final m in rows) {
        _merge(m);
      }
      notifyListeners();
      unawaited(markOpenRead());
    } catch (_) {}
  }

  /// Adds or replaces a message, matching our own pending copy by client_uuid.
  void _merge(ChatMessage m) {
    final byUuid = m.clientUuid.isEmpty ? -1 : messages.indexWhere((x) => x.clientUuid == m.clientUuid);
    final byId = messages.indexWhere((x) => x.id == m.id && m.id != 0);
    final i = byId >= 0 ? byId : byUuid;
    if (i >= 0) {
      messages[i] = m;
    } else {
      messages.add(m);
      messages.sort((a, b) => (a.isPending ? 1 << 62 : a.id).compareTo(b.isPending ? 1 << 62 : b.id));
    }
  }

  Future<void> markOpenRead() async {
    final c = open;
    if (c == null || !panelVisible) return;
    final last = _lastServerId;
    if (last == 0 || c.unreadCount == 0) return;
    c.unreadCount = 0;
    _updateUnread();
    notifyListeners();
    try {
      c.unreadCount = await _api.markRead(c.id, last);
      _updateUnread();
    } catch (_) {}
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  static String newUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  ChatMessage _pending(int conversationId, String type, String? body, {String? filePath}) => ChatMessage(
        id: 0, conversationId: conversationId, senderId: me, sender: null, type: type, body: body,
        clientUuid: newUuid(), createdAt: DateTime.now(), localState: SendState.sending, localFilePath: filePath,
        attachments: filePath == null ? const [] : [
          ChatAttachment(id: 0, mime: '', size: 0, name: filePath.split(Platform.pathSeparator).last,
              isImage: false, url: ''),
        ],
      );

  Future<void> sendText(String text) async {
    final id = openId;
    final body = text.trim();
    if (id == null || body.isEmpty) return;
    final m = _pending(id, 'text', body);
    messages.add(m);
    notifyListeners();
    await _deliver(m);
  }

  Future<void> sendFile(String path, {String? caption}) async {
    final id = openId;
    if (id == null) return;
    final m = _pending(id, 'file', caption, filePath: path);
    messages.add(m);
    notifyListeners();
    await _deliver(m);
  }

  /// Tap on a failed message: try again with the same client_uuid (the
  /// server ignores a repeat it already has).
  Future<void> retry(ChatMessage m) async {
    final i = messages.indexWhere((x) => x.clientUuid == m.clientUuid);
    if (i < 0) return;
    messages[i] = m.copyWith(localState: SendState.sending);
    notifyListeners();
    await _deliver(messages[i]);
  }

  void discard(ChatMessage m) {
    messages.removeWhere((x) => x.clientUuid == m.clientUuid && x.isPending);
    notifyListeners();
  }

  Future<void> _deliver(ChatMessage m) async {
    try {
      final saved = m.localFilePath != null
          ? await _api.sendFile(m.conversationId, clientUuid: m.clientUuid, path: m.localFilePath!, caption: m.body)
          : await _api.send(m.conversationId, clientUuid: m.clientUuid, body: m.body ?? '');
      if (openId == m.conversationId) _merge(saved);
      unawaited(refreshList());
    } catch (_) {
      final i = messages.indexWhere((x) => x.clientUuid == m.clientUuid && x.isPending);
      if (i >= 0) messages[i] = m.copyWith(localState: SendState.failed);
    }
    notifyListeners();
  }

  Future<void> edit(ChatMessage m, String body) async {
    final saved = await _api.edit(m.id, body.trim());
    _merge(saved);
    notifyListeners();
  }

  Future<void> delete(ChatMessage m) async {
    final saved = await _api.delete(m.id);
    _merge(saved);
    notifyListeners();
    unawaited(refreshList());
  }

  // ── Starting chats ────────────────────────────────────────────────────────

  Future<int> startDirect(int userId) async {
    final c = await _api.openDirect(userId);
    _upsert(c);
    return c.id;
  }

  Future<int> startGroup(String title, List<int> userIds) async {
    final c = await _api.createGroup(title, userIds);
    _upsert(c);
    return c.id;
  }

  Future<void> addMembers(int conversationId, List<int> userIds) async {
    _upsert(await _api.addMembers(conversationId, userIds));
  }

  Future<void> leave(int conversationId) async {
    final uid = me;
    if (uid == null) return;
    await _api.leave(conversationId, uid);
    if (openId == conversationId) closeChat();
    conversations.removeWhere((c) => c.id == conversationId);
    _updateUnread();
    notifyListeners();
  }

  Future<void> setMuted(int conversationId, bool muted) async {
    await _api.mute(conversationId, muted ? DateTime.now().add(const Duration(days: 3650)) : null);
    await refreshList();
  }

  void _upsert(Conversation c) {
    final i = conversations.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      conversations[i] = c;
    } else {
      conversations = [c, ...conversations];
    }
    notifyListeners();
  }

  // ── Ticks ─────────────────────────────────────────────────────────────────

  /// ✓ sent, ✓✓ grey delivered to everyone else, ✓✓ blue read by everyone else.
  SendState stateOf(ChatMessage m) {
    if (m.localState != null) return m.localState!;
    final others = (open?.participants ?? const <ChatParticipant>[]).where((p) => p.id != me).toList();
    if (others.isEmpty) return SendState.sent;
    if (others.every((p) => (p.lastReadId ?? 0) >= m.id)) return SendState.read;
    if (others.every((p) => max(p.lastDeliveredId ?? 0, p.lastReadId ?? 0) >= m.id)) return SendState.delivered;
    return SendState.sent;
  }

  void _movePointer(int conversationId, int userId, {int? read, int? delivered}) {
    final i = conversations.indexWhere((c) => c.id == conversationId);
    if (i < 0) return;
    final c = conversations[i];
    for (var k = 0; k < c.participants.length; k++) {
      final p = c.participants[k];
      if (p.id != userId) continue;
      c.participants[k] = p.copyWith(
        lastReadId: read != null ? max(read, p.lastReadId ?? 0) : null,
        lastDeliveredId: delivered != null ? max(delivered, p.lastDeliveredId ?? 0) : null,
      );
    }
    notifyListeners();
  }

  // ── Live events ───────────────────────────────────────────────────────────

  void _onEvent(ChatEvent e) {
    final d = e.data;
    int? n(String k) => (d[k] as num?)?.toInt();
    switch (e.event) {
      case 'message.created' || 'conversation.added' || 'conversation.removed':
        unawaited(refreshList());
        final cid = n('conversation_id');
        if (e.event == 'message.created' && cid != null && cid == openId) unawaited(_fetchNewer());
      case 'conversation.read':
        final cid = n('conversation_id');
        final c = conversations.where((x) => x.id == cid).firstOrNull;
        if (c != null) {
          c.unreadCount = n('unread_count') ?? c.unreadCount;
          _updateUnread();
          notifyListeners();
        }
      case 'message.sent' || 'message.edited' || 'message.deleted':
        final raw = d['message'];
        if (raw is Map) {
          final m = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
          if (m.conversationId == openId) {
            _merge(m);
            notifyListeners();
            if (e.event == 'message.sent' && m.senderId != me) unawaited(markOpenRead());
          }
        }
      case 'read.updated':
        final cid = n('conversation_id'), uid = n('user_id'), id = n('last_read_message_id');
        if (cid != null && uid != null && id != null) _movePointer(cid, uid, read: id, delivered: id);
      case 'delivered.updated':
        final cid = n('conversation_id'), uid = n('user_id'), id = n('last_delivered_message_id');
        if (cid != null && uid != null && id != null) _movePointer(cid, uid, delivered: id);
    }
  }

  /// The app came back to the foreground / the network returned.
  void nudge() {
    _rt?.nudge();
    if (_running) unawaited(refreshList());
  }

  // ── Desktop pop-ups ───────────────────────────────────────────────────────

  @visibleForTesting
  void Function(String title, String body, int? conversationId)? debugToaster;

  static bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _toast(String title, String body, int? conversationId) {
    final t = debugToaster;
    if (t != null) return t(title, body, conversationId);
    if (Platform.isAndroid) {
      unawaited(PhoneNotifications.instance.showChat(title, body, conversationId));
      return;
    }
    if (!_isDesktop) return;
    try {
      final n = LocalNotification(identifier: 'hm_chat_${DateTime.now().microsecondsSinceEpoch}', title: title, body: body);
      n.onClick = () => unawaited(_openFromToast(conversationId));
      n.show().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _openFromToast(int? conversationId) async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    openRequests.value = null;
    openRequests.value = conversationId ?? -1; // -1 = just the chat list
  }
}
