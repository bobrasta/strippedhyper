import 'package:bienhypermed/main.dart' show authTokenNotifier, userIdNotifier;
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/chat_controller.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/chat/chat_panel.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// In-app chat with realistic data: the list, one chat (own ticks, a deleted
// message, an edit, a file, a system line, long words), sending, and
// starting a new chat — in the phone page (390 px) and the desktop dock
// window (380 × 560 inside a 1440 px window).
void main() {
  final now = DateTime.now().toUtc();
  String ago(int minutes) => now.subtract(Duration(minutes: minutes)).toIso8601String();
  Map<String, dynamic> user(int id, String name) => {'id': id, 'name': name, 'avatar_url': null};
  Map<String, dynamic> msg(int id, int? sender, String? body,
          {String type = 'text', bool deleted = false, bool edited = false, int minutes = 30, List attachments = const []}) =>
      {
        'id': id, 'conversation_id': 5, 'sender_id': sender,
        'sender': sender == null ? null : user(sender, sender == 1 ? 'Bob Temu' : 'Anna Mwakalinga Kisanga'),
        'type': type, 'body': deleted ? null : body, 'meta': null, 'client_uuid': 'uuid-$id', 'reply_to_id': null,
        'reply_to': null, 'attachments': attachments, 'entity': null, 'is_deleted': deleted,
        'edited_at': edited ? ago(minutes - 1) : null, 'created_at': ago(minutes),
      };
  Map<String, dynamic> conv(int id, String type, {String? title, int unread = 0, Map<String, dynamic>? last}) => {
        'id': id, 'type': type, 'title': title, 'org_unit_key': null, 'entity_type': null, 'entity_id': null,
        'created_by': 1, 'created_at': ago(600), 'last_activity_at': ago(id == 5 ? 2 : 900), 'last_message': last,
        'unread_count': unread, 'my_role': 'admin', 'last_read_message_id': null, 'muted_until': null,
        'participant_count': type == 'direct' ? 2 : 6,
        'participants': [
          {...user(1, 'Bob Temu'), 'role': 'admin', 'last_read_message_id': 12, 'last_delivered_message_id': 13},
          {...user(2, 'Anna Mwakalinga Kisanga wa Kilimanjaro'), 'role': 'member', 'last_read_message_id': 12, 'last_delivered_message_id': 13},
        ],
      };

  for (final (label, window, box, workspace) in [
    ('phone page', const Size(390, 844), const Size(390, 844), false),
    ('desktop dock', const Size(1440, 900), const Size(380, 560), false),
    // The Chats menu screen: list beside the chat on desktop, one pane on a phone.
    ('Chats screen, desktop', const Size(1440, 900), const Size(1208, 844), true),
    ('Chats screen, phone', const Size(390, 844), const Size(390, 788), true),
  ]) {
    testWidgets('chat at $label', (tester) async {
      try {
        authTokenNotifier = ValueNotifier<String?>('test-token');
      } catch (_) {/* already set */}
      userIdNotifier.value = 1;
      final sent = <Map<String, dynamic>>[];
      final stub = InterceptorsWrapper(onRequest: (o, h) {
        final p = o.uri.path;
        dynamic body = {'data': <dynamic>[]};
        if (p.endsWith('/api/messaging/settings')) {
          body = {'data': {'audit_enabled': true, 'can_audit': false, 'calls_enabled': false, 'realtime': null}};
        } else if (p.endsWith('/api/messaging/conversations') && o.method == 'GET') {
          body = {'data': [
            conv(5, 'direct', unread: 2, last: msg(14, 2, 'Can you check the Mindray BC-5150 at Muhimbili before Friday? Thanks a lot')),
            conv(6, 'group', title: 'Sales team — northern zone reps and coordinators', last: msg(20, 1, 'New stock arrived')),
          ], 'meta': {'next_cursor': null}};
        } else if (p.endsWith('/conversations/5/messages') && o.method == 'GET') {
          body = {'data': [
            msg(14, 2, 'Can you check the Mindray BC-5150 at Muhimbili before Friday?', minutes: 3),
            msg(13, 1, 'Supercalifragilisticexpialidocious-reference-HHL/2026/0001-with-no-spaces-at-all', minutes: 10),
            msg(12, 1, 'Quotation attached', type: 'file', minutes: 20, attachments: [
              {'id': 1, 'mime': 'application/pdf', 'size': 248000, 'original_name': 'Quotation QTN-2026-0457 Muhimbili National Hospital.pdf',
               'is_image': false, 'url': 'https://api.example.test/f/1', 'thumb_url': null},
            ]),
            msg(11, 2, null, deleted: true, minutes: 25),
            msg(10, 2, 'Morning! Fixed the date', edited: true, minutes: 40),
            msg(9, null, 'Bob Temu added Anna', type: 'system', minutes: 60),
          ], 'meta': {'has_more': false}};
        } else if (p.endsWith('/conversations/5/messages') && o.method == 'POST') {
          final d = Map<String, dynamic>.from(o.data as Map);
          sent.add(d);
          body = {'data': {...msg(99, 1, d['body'] as String, minutes: 0), 'client_uuid': d['client_uuid']}};
        } else if (p.endsWith('/read') || p.endsWith('/delivered')) {
          body = {'data': {'conversation_id': 5, 'last_read_message_id': 14, 'unread_count': 0}};
        } else if (p.endsWith('/api/messaging/users')) {
          body = {'data': [user(2, 'Anna Mwakalinga Kisanga'), user(3, 'Gabriel Shayo'), user(4, 'Sharif Mohamed')]};
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      });
      ApiClient.instance.dio.interceptors.insert(0, stub);
      addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ChatController.instance;
      addTearDown(c.stop);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox.fromSize(size: box, child: Material(child: workspace ? const ChatPanel(workspace: true) : ChatPanel(onClose: () {}))),
        )),
      ));
      await tester.runAsync(() async {
        await c.reloadSettings();
        await c.refreshList(baseline: true);
      });
      await tester.pumpAndSettle();
      expect(find.text('Anna Mwakalinga Kisanga wa Kilimanjaro'), findsOneWidget);
      expect(find.textContaining('Chat review is on'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'list');

      // Open the direct chat.
      await tester.tap(find.text('Anna Mwakalinga Kisanga wa Kilimanjaro').first);
      await tester.pumpAndSettle();
      expect(find.text('Message deleted'), findsOneWidget);
      expect(find.textContaining('edited'), findsOneWidget);
      expect(find.textContaining('Quotation QTN-2026-0457'), findsOneWidget);
      expect(find.byTooltip('Read'), findsWidgets);
      // Oldest first is at the top: scroll up to it.
      await tester.drag(find.byType(ListView).last, const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(find.text('Bob Temu added Anna'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'chat');

      // Send.
      await tester.enterText(find.descendant(of: find.byType(LabeledTextField).last, matching: find.byType(TextField)), 'On my way');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent.single['body'], 'On my way');
      expect(find.text('On my way'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'sent');

      // Back to the list, then start a new chat.
      await tester.tap(find.byTooltip('All chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      expect(find.text('Gabriel Shayo'), findsOneWidget);
      await tester.tap(find.text('New group'));
      await tester.pumpAndSettle();
      expect(find.text('Create group'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'new chat');
    });
  }
}
