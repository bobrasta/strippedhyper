import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/screens/chat/chat_review_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Chat review: staff → their chats → a chat, read-only, showing deleted text
// and the words before an edit — at desktop and phone width.
void main() {
  Map<String, dynamic> user(int id, String name) => {'id': id, 'name': name, 'avatar_url': null};
  final chat = {
    'id': 5, 'type': 'direct', 'title': null, 'created_by': 2, 'created_at': '2026-11-03T08:00:00Z',
    'last_activity_at': '2026-11-04T09:00:00Z', 'unread_count': 0, 'my_role': 'member', 'muted_until': null,
    'participant_count': 2, 'last_message': null,
    'participants': [{...user(2, 'Anna Mwakalinga Kisanga'), 'role': 'member'}, {...user(3, 'Gabriel Shayo'), 'role': 'member'}],
  };
  Map<String, dynamic> msg(int id, int sender, String body, {bool deleted = false, List revisions = const []}) => {
    'id': id, 'conversation_id': 5, 'sender_id': sender, 'sender': user(sender, sender == 2 ? 'Anna Mwakalinga Kisanga' : 'Gabriel Shayo'),
    'type': 'text', 'body': body, 'client_uuid': 'u$id', 'attachments': [], 'is_deleted': deleted,
    'deleted_at': deleted ? '2026-11-04T09:05:00Z' : null, 'edited_at': revisions.isEmpty ? null : '2026-11-04T09:02:00Z',
    'revisions': revisions, 'created_at': '2026-11-04T09:00:00Z',
  };

  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets('chat review at ${size.width.toInt()} px', (tester) async {
      try {
        authTokenNotifier = ValueNotifier<String?>('test-token');
      } catch (_) {}
      final stub = InterceptorsWrapper(onRequest: (o, h) {
        final p = o.uri.path;
        dynamic body = {'data': <dynamic>[]};
        if (p.endsWith('/api/messaging/users')) {
          body = {'data': [user(2, 'Anna Mwakalinga Kisanga'), user(3, 'Gabriel Shayo')]};
        } else if (p.endsWith('/audit/users/2/conversations')) {
          body = {'data': [chat], 'meta': {'next_cursor': null, 'subject': user(2, 'Anna Mwakalinga Kisanga')}};
        } else if (p.endsWith('/audit/conversations/5/messages')) {
          body = {'data': [
            msg(3, 2, 'Regretted words', deleted: true),
            msg(2, 3, 'Softer words', revisions: [{'body': 'Harsh words', 'replaced_at': '2026-11-04T09:02:00Z'}]),
            msg(1, 2, 'Morning'),
          ], 'meta': {'has_more': false, 'participant_ids': [2, 3]}};
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      });
      ApiClient.instance.dio.interceptors.insert(0, stub);
      addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ChatReviewScreen())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Activity Log'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'people');

      await tester.tap(find.text('Anna Mwakalinga Kisanga'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gabriel Shayo').last);
      await tester.pumpAndSettle();
      expect(find.text('Regretted words'), findsOneWidget);
      expect(find.textContaining('DELETED'), findsOneWidget);
      expect(find.textContaining('Before edit'), findsOneWidget);
      expect(find.textContaining('Harsh words'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'chat');
    });
  }
}
