import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/chat.dart';
import 'api_client.dart';
import 'chat_service.dart';

/// One event from a channel: `message.sent`, `read.updated`, …
class ChatEvent {
  const ChatEvent(this.channel, this.event, this.data);
  final String channel;
  final String event;
  final Map<String, dynamic> data;
}

/// The live connection to the API's Reverb server, speaking the Pusher
/// protocol over a plain WebSocket (no extra package).
///
/// Private and presence channels are signed by the API
/// (`POST /api/broadcasting/auth` with the user's token). Drops reconnect
/// with backoff, and every channel is subscribed again. [connected] tells
/// the chat controller when to fall back to polling.
class ChatRealtime {
  ChatRealtime(this._settings);

  final ChatSettings _settings;
  final _events = StreamController<ChatEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _channels = <String>{};
  final _rng = Random();

  WebSocket? _socket;
  String? _socketId;
  Timer? _retry;
  Timer? _idle;
  bool _closed = false;
  int _attempt = 0;
  Duration _activityTimeout = const Duration(seconds: 30);

  Stream<ChatEvent> get events => _events.stream;
  Stream<bool> get connectedChanges => _connected.stream;
  bool get isConnected => _socketId != null;

  Uri get _uri => Uri(
        scheme: _settings.realtimeTls ? 'wss' : 'ws',
        host: _settings.realtimeHost,
        port: _settings.realtimePort,
        path: '/app/${_settings.realtimeKey}',
        queryParameters: const {'protocol': '7', 'client': 'hypermed-dart', 'version': '1.0', 'flash': 'false'},
      );

  void connect() {
    _closed = false;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_closed || _socket != null) return;
    try {
      final ws = await WebSocket.connect(_uri.toString()).timeout(const Duration(seconds: 15));
      if (_closed) {
        await ws.close();
        return;
      }
      _socket = ws;
      ws.listen(_onFrame, onDone: _onDrop, onError: (_) => _onDrop(), cancelOnError: true);
    } catch (e) {
      dev.log('chat socket connect failed: $e', name: 'CHAT');
      _scheduleRetry();
    }
  }

  void _onFrame(dynamic raw) {
    _touch();
    Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return;
    }
    final event = msg['event'] as String? ?? '';
    final data = _decodeData(msg['data']);
    switch (event) {
      case 'pusher:connection_established':
        _socketId = data['socket_id'] as String?;
        final t = (data['activity_timeout'] as num?)?.toInt();
        if (t != null && t > 5) _activityTimeout = Duration(seconds: t);
        _attempt = 0;
        _connected.add(true);
        for (final c in _channels) {
          unawaited(_subscribe(c));
        }
      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': <String, dynamic>{}});
      case 'pusher:error':
        dev.log('chat socket error: $data', name: 'CHAT');
      case 'pusher_internal:subscription_succeeded' || 'pusher:pong':
        break;
      default:
        final channel = msg['channel'] as String?;
        if (channel != null && !event.startsWith('pusher')) {
          _events.add(ChatEvent(channel, event, data));
        }
    }
  }

  static Map<String, dynamic> _decodeData(dynamic d) {
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.isNotEmpty) {
      try {
        final v = jsonDecode(d);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// Keeps [channel] subscribed across reconnects.
  void subscribe(String channel) {
    if (!_channels.add(channel)) return;
    if (isConnected) unawaited(_subscribe(channel));
  }

  void unsubscribe(String channel) {
    if (!_channels.remove(channel)) return;
    if (isConnected) _send({'event': 'pusher:unsubscribe', 'data': {'channel': channel}});
  }

  Future<void> _subscribe(String channel) async {
    final socketId = _socketId;
    if (socketId == null) return;
    try {
      final res = await ApiClient.instance.dio.post(
        '${ChatService.origin}${_settings.authPath}',
        data: {'socket_id': socketId, 'channel_name': channel},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : _decodeData(res.data);
      if (_socketId != socketId || !_channels.contains(channel)) return;
      _send({
        'event': 'pusher:subscribe',
        'data': {
          'channel': channel,
          'auth': body['auth'],
          if (body['channel_data'] != null) 'channel_data': body['channel_data'],
        },
      });
    } catch (e) {
      dev.log('chat channel auth failed for $channel: $e', name: 'CHAT');
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _socket?.add(jsonEncode(msg));
    } catch (_) {}
  }

  // A quiet line is checked with a ping; no answer means it is dead.
  void _touch() {
    _idle?.cancel();
    _idle = Timer(_activityTimeout, () {
      _send({'event': 'pusher:ping', 'data': <String, dynamic>{}});
      _idle = Timer(const Duration(seconds: 15), () => _socket?.close());
    });
  }

  void _onDrop() {
    _idle?.cancel();
    final was = isConnected;
    _socket = null;
    _socketId = null;
    if (was) _connected.add(false);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    // 1 s, 2 s, 4 s … up to 60 s, with jitter so every PC doesn't knock at once.
    final base = min(60, 1 << min(_attempt, 6));
    _attempt++;
    _retry = Timer(Duration(milliseconds: base * 1000 + _rng.nextInt(1000)), _open);
  }

  /// Network came back (or the app woke up): try now instead of waiting.
  void nudge() {
    if (_closed || _socket != null) return;
    _retry?.cancel();
    _attempt = 0;
    unawaited(_open());
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _idle?.cancel();
    _channels.clear();
    final s = _socket;
    _socket = null;
    _socketId = null;
    await s?.close();
    await _events.close();
    await _connected.close();
  }
}
