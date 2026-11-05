import 'dart:io';

import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/models/email.dart';
import 'package:bienhypermed/screens/email/email_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/email_attachment_cache.dart';
import 'package:bienhypermed/services/email_outbox.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Email attachments in the app: the device cache (download once, then from
// disk; least-recently-opened trim; wiped per user), outgoing files uploaded
// once and reused on retry, and the reading pane laid out with realistic data.

final _requests = <String>[];
var _failCompose = 0;

Map<String, dynamic> _email(int id, {bool attachments = true}) => {
  'id': id, 'subject': 'Liaison XL — tender documents and calibration certificates for Mloganzila $id',
  'from_name': 'Dr. Florian Mwaisumbe (Microbiology, Muhimbili National Hospital)', 'from_email': 'florian.mwaisumbe@mnh.or.tz',
  'to': [{'email': 'dianafrancis@hypermed.co.tz', 'name': 'Diana Francis'}],
  'body_text': 'Dear Diana,\n\nPlease find attached the tender pack and the signed calibration certificates.\n\nRegards',
  'folder': 'INBOX', 'is_read': true, 'is_flagged': false, 'date': '2026-10-20T08:15:00Z', 'has_attachments': attachments,
  if (attachments) 'attachments': [
    {'id': 11, 'filename': 'MNH-Tender-Pack-2026-2027-Lot-1-to-6-Technical-Specifications-FINAL-signed.pdf', 'mime_type': 'application/pdf', 'size': 27800000},
    {'id': 12, 'filename': 'fault-photo.jpg', 'mime_type': 'image/jpeg', 'size': 812000},
    {'id': 13, 'filename': 'Price schedule.xlsx', 'mime_type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'size': 48000},
  ],
};

dynamic _respond(RequestOptions o) {
  final p = o.path;
  _requests.add('${o.method} $p');
  if (p == '/email-accounts') {
    return {'data': [{'id': 3, 'label': 'Work', 'from_email': 'dianafrancis@hypermed.co.tz', 'from_name': 'Diana Francis', 'is_default': true}]};
  }
  if (p == '/emails/inbox') return {'data': [_email(1), _email(2, attachments: false)], 'meta': {'total': 2}};
  if (RegExp(r'^/emails/\d+/attachments/\d+$').hasMatch(p)) return List<int>.filled(2048, 7);
  if (p == '/emails/attachments') return {'data': {'token': '11111111-2222-3333-4444-555555555555', 'filename': 'specs.pdf'}};
  if (p == '/emails/compose') {
    if (_failCompose-- > 0) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    return {'data': {'id': 99}};
  }
  if (RegExp(r'^/emails/\d+$').hasMatch(p)) return {'data': _email(int.parse(p.split('/').last))};
  if (p == '/emails/unread-count') return {'data': {'unread': 0}};
  return {'data': <dynamic>[]};
}

void main() {
  late Directory tmp;

  setUpAll(() {
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      try {
        h.resolve(Response(requestOptions: o, statusCode: 200, data: _respond(o)));
      } on DioException catch (e) {
        h.reject(e);
      }
    }));
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hm_att_');
    EmailAttachmentCache.instance.rootDir = () async => tmp;
    userIdNotifier.value = 68;
    _requests.clear();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  const a = EmailAttachment(id: 11, filename: 'pack.pdf', size: 2048, mimeType: 'application/pdf');

  test('an attachment downloads once, then comes from the device', () async {
    final f1 = await EmailAttachmentCache.instance.get(68, 1, a);
    final f2 = await EmailAttachmentCache.instance.get(68, 1, a);
    expect(f1.path, f2.path);
    expect(await f2.length(), 2048);
    expect(_requests.where((r) => r.contains('/attachments/11')).length, 1);
    expect(await EmailAttachmentCache.instance.cached(68, a), isNotNull);
  });

  test('trim drops the least recently opened; wipeUser clears the user', () async {
    const b = EmailAttachment(id: 12, filename: 'b.pdf', size: 2048);
    final fa = await EmailAttachmentCache.instance.get(68, 1, a);
    await EmailAttachmentCache.instance.get(68, 1, b);
    await fa.setLastModified(DateTime.now().subtract(const Duration(days: 1)));
    await EmailAttachmentCache.instance.trim(limit: 3000);
    expect(await EmailAttachmentCache.instance.cached(68, a), isNull);
    expect(await EmailAttachmentCache.instance.cached(68, b), isNotNull);

    await EmailAttachmentCache.instance.wipeUser(68);
    expect(await EmailAttachmentCache.instance.cached(68, b), isNull);
  });

  test('a failed send keeps its upload token, so a retry does not upload again', () async {
    final file = File('${tmp.path}/specs.pdf')..writeAsBytesSync([1, 2, 3]);
    final payload = <String, dynamic>{
      'to': 'x@example.com', 'subject': 'Specs', 'body': 'Attached',
      'attachments': [{'path': file.path, 'name': 'specs.pdf', 'size': 3}],
    };
    _failCompose = 1;
    await expectLater(EmailOutbox.send('compose', payload), throwsA(isA<DioException>()));
    expect((payload['attachments'] as List).first['token'], isNotNull);
    await EmailOutbox.send('compose', payload);
    expect(_requests.where((r) => r == 'POST /emails/attachments').length, 1);
    expect(_requests.where((r) => r == 'POST /emails/compose').length, 2);
  });

  for (final w in [390.0, 1440.0]) {
    testWidgets('the reading pane lists attachments without overflow at $w px', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (e) => errors.add(e.exceptionAsString().split('\n').first);
      try {
        await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const Scaffold(body: EmailScreen())));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.tap(find.textContaining('Mloganzila 1').first);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(find.text('3 attachments'), findsOneWidget);
        expect(find.textContaining('MNH-Tender-Pack'), findsOneWidget);
        expect(find.textContaining('26.5 MB'), findsOneWidget);
        // Opening it doesn't mark it read again (the list toggles read state).
        expect(_requests.where((r) => r.startsWith('GET /emails/1')), isNotEmpty);
      } finally {
        FlutterError.onError = previous;
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(errors, isEmpty);
    });
  }
}
