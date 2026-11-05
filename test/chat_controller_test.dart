import 'package:bienhypermed/main.dart' show authTokenNotifier, userIdNotifier;
import 'package:bienhypermed/models/chat.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/chat_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Chat pop-ups and ticks: the first load only sets the baseline; later a
// new message from someone else pops up once, never for our own, a muted
// chat or the chat already open on screen; ticks follow the others' read
// and delivered pointers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> convs;
  late InterceptorsWrapper stub;

  Map<String, dynamic> conv(int id, int lastId, int sender, {int unread = 1, String? muted}) => {
        'id': id, 'type': 'direct', 'title': null, 'created_by': 1, 'created_at': '2026-11-04T08:00:00Z',
        'last_activity_at': '2026-11-04T09:00:00Z', 'unread_count': unread, 'my_role': 'member',
        'last_read_message_id': null, 'muted_until': muted, 'participant_count': 2,
        'last_message': {
          'id': lastId, 'conversation_id': id, 'sender_id': sender, 'sender': {'id': sender, 'name': 'Anna K', 'avatar_url': null},
          'type': 'text', 'body': 'hello $lastId', 'client_uuid': 'u$lastId', 'attachments': [], 'is_deleted': false,
          'created_at': '2026-11-04T09:00:00Z',
        },
        'participants': [
          {'id': 1, 'name': 'Me', 'avatar_url': null, 'role': 'member', 'last_read_message_id': null, 'last_delivered_message_id': null},
          {'id': 2, 'name': 'Anna K', 'avatar_url': null, 'role': 'member', 'last_read_message_id': 10, 'last_delivered_message_id': 12},
        ],
      };

  setUp(() {
    try {
      authTokenNotifier = ValueNotifier<String?>('t');
    } catch (_) {}
    userIdNotifier.value = 1;
    stub = InterceptorsWrapper(onRequest: (o, h) {
      final body = o.uri.path.endsWith('/conversations') ? {'data': convs, 'meta': <String, dynamic>{}} : {'data': <String, dynamic>{}};
      h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
  });
  tearDown(() => ApiClient.instance.dio.interceptors.remove(stub));

  test('pop-ups: baseline first, then only new messages from others', () async {
    final c = ChatController();
    final toasts = <String>[];
    c.debugToaster = (title, body, _) => toasts.add('$title|$body');

    convs = [conv(5, 10, 2), conv(6, 20, 2, muted: '2099-01-01T00:00:00Z')];
    await c.refreshList(baseline: true);
    expect(c.listError, isNull);
    expect(toasts, isEmpty);
    expect(chatUnreadNotifier.value, 2);

    convs = [conv(5, 11, 2), conv(6, 21, 2, muted: '2099-01-01T00:00:00Z'), conv(7, 30, 2)];
    await c.refreshList();
    expect(toasts, ['Anna K|hello 11', 'Anna K|hello 30']); // not the muted chat 6

    toasts.clear();
    convs = [conv(5, 12, 1, unread: 0)]; // our own message
    await c.refreshList();
    expect(toasts, isEmpty);

    // The chat open on screen doesn't pop up.
    c.openId = 5;
    c.attachView();
    convs = [conv(5, 13, 2)];
    await c.refreshList();
    expect(toasts, isEmpty);
  });

  test('ticks follow the other person\'s pointers', () async {
    final c = ChatController();
    convs = [conv(5, 10, 2)];
    await c.refreshList(baseline: true);
    c.openId = 5;
    ChatMessage own(int id) => ChatMessage(id: id, conversationId: 5, senderId: 1, sender: null, type: 'text',
        body: 'x', clientUuid: 'c$id', createdAt: DateTime.now());
    expect(c.stateOf(own(9)), SendState.read);
    expect(c.stateOf(own(11)), SendState.delivered);
    expect(c.stateOf(own(13)), SendState.sent);
    expect(c.stateOf(own(0).copyWith(localState: SendState.failed)), SendState.failed);
  });

  test('message ids are v4 uuids', () {
    final ids = {for (var i = 0; i < 50; i++) ChatController.newUuid()};
    expect(ids.length, 50);
    expect(ids.every((u) => RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(u)), isTrue);
  });
}
