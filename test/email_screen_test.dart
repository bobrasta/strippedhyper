import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/screens/email/email_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/email_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_button.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The email screen: the message as sent (tables, lists, links), selectable
// and copyable; Mark as spam / Not spam / Delete to Trash from the toolbar and
// the right-click menu; date sections in the list — at phone and desktop width.

final _requests = <String>[];
final _moves = <String>[];

const _html = '<html><head><style>p{color:red}</style></head><body>'
    '<p>Dear <b>Diana</b>,</p><p>Please confirm the order below.</p>'
    '<table width="640" border="1"><tr><th>Item</th><th>Qty</th><th>Amount</th></tr>'
    '<tr><td>Liaison XL reagent kit — 200 tests</td><td>4</td><td>TSh 12,400,000</td></tr></table>'
    '<ul><li>Delivery to Mloganzila</li><li>Invoice in TSh</li></ul>'
    '<p><a href="https://example.com/po">Purchase order</a></p><img src="https://example.com/pixel.png" width="1" height="1">'
    '</body></html>';

Map<String, dynamic> _email(int id, String folder, {DateTime? at}) => {
  'id': id, 'subject': 'Order confirmation for Liaison XL reagents, Muhimbili National Hospital $id',
  'from': {'name': 'Dr. Florian Mwaisumbe (Microbiology, Muhimbili National Hospital)', 'email': 'florian.mwaisumbe@mnh.or.tz'},
  'to': [{'email': 'dianafrancis@hypermed.co.tz', 'name': 'Diana Francis'}],
  'cc': [{'email': 'procurement@mnh.or.tz', 'name': 'MNH Procurement'}],
  'body_text': 'Dear Diana, Please confirm the order below.', 'body_html': _html,
  'folder': folder, 'is_read': id != 1, 'is_flagged': false,
  'date': (at ?? DateTime.now()).toIso8601String(), 'has_attachments': false,
};

dynamic _respond(RequestOptions o) {
  final p = o.path;
  _requests.add('${o.method} $p');
  if (p == '/email-accounts') {
    return {'data': [{'id': 3, 'label': 'Work', 'from_email': 'dianafrancis@hypermed.co.tz', 'from_name': 'Diana Francis', 'is_default': true}]};
  }
  if (p == '/emails/inbox') {
    return {'data': [
      _email(1, 'INBOX'),
      _email(2, 'INBOX', at: DateTime.now().subtract(const Duration(days: 1))),
      _email(3, 'INBOX', at: DateTime.now().subtract(const Duration(days: 40))),
    ], 'meta': {'current_page': 1, 'last_page': 1}};
  }
  if (p == '/emails/folder/spam') return {'data': [_email(7, 'INBOX.Junk')], 'meta': {'current_page': 1, 'last_page': 1}};
  if (RegExp(r'^/emails/\d+/move$').hasMatch(p)) {
    _moves.add('${p.split('/')[2]}:${(o.data as Map)['to']}');
    return {'data': {}};
  }
  if (p == '/emails/unread-count') return {'data': {'unread': 1}};
  if (p == '/emails/sync') return {'data': {'synced': 0}};
  return {'data': <dynamic>[]};
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() {
    authTokenNotifier = ValueNotifier('t');
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) =>
        h.resolve(Response(requestOptions: o, statusCode: 200, data: _respond(o)))));
  });

  setUp(() {
    _requests.clear();
    _moves.clear();
    EmailService.cachedByFolder.clear();
  });

  for (final w in [390.0, 1440.0]) {
    testWidgets('read, copy, spam, not spam and delete at $w px', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'Clipboard.setData') copied = (c.arguments as Map)['text'] as String?;
        return null;
      });
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (e) => errors.add(e.exceptionAsString().split('\n').first);
      var sections = <String>[];
      var tableCell = false, picturesHidden = false, copiedBody = '';
      var menuHasSpam = false, notSpamShown = false, spamBanner = false;
      try {
        await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const Scaffold(body: EmailScreen())));
        await _settle(tester);
        sections = [for (final s in ['TODAY', 'YESTERDAY']) if (find.text(s).evaluate().isNotEmpty) s];

        await tester.tap(find.textContaining('Hospital 1').first);
        await _settle(tester);
        tableCell = find.textContaining('Liaison XL reagent kit', findRichText: true).evaluate().isNotEmpty;
        picturesHidden = find.text('Pictures are hidden.').evaluate().isNotEmpty;

        // Select everything in the message and copy it.
        await tester.tapAt(tester.getCenter(find.textContaining('Please confirm', findRichText: true).last));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        copiedBody = copied ?? '';

        // Toolbar Spam moves it out of the Inbox.
        await tester.tap(w > 700 ? find.widgetWithText(AppButton, 'Spam') : find.byTooltip('Mark as spam'));
        await _settle(tester);

        // Right-click the next row: its menu offers Mark as spam.
        if (w > 700) {
          await tester.tap(find.textContaining('Hospital 2').first, buttons: kSecondaryButton);
          await tester.pumpAndSettle();
          menuHasSpam = find.text('Mark as spam').evaluate().isNotEmpty;
          await tester.tap(find.text('Delete').last);
          await _settle(tester);
        }

        // Spam folder: banner + Not spam.
        if (w < 700) {
          await tester.tap(find.byIcon(Icons.menu));
          await _settle(tester);
        }
        await tester.tap(find.text('Spam').first);
        await _settle(tester);
        await tester.tap(find.textContaining('Hospital 7').first);
        await _settle(tester);
        spamBanner = find.textContaining('This email is in Spam').evaluate().isNotEmpty;
        notSpamShown = find.text('Not spam').evaluate().isNotEmpty;
        if (notSpamShown) {
          await tester.tap(find.text('Not spam'));
          await _settle(tester);
        }
      } finally {
        FlutterError.onError = previous;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      expect(errors, isEmpty);
      expect(sections, ['TODAY', 'YESTERDAY']);
      expect(tableCell, isTrue, reason: 'the HTML table renders');
      expect(picturesHidden, isTrue);
      expect(copiedBody, contains('Please confirm the order below.'));
      expect(copiedBody, contains('TSh 12,400,000'));
      expect(spamBanner, isTrue);
      expect(notSpamShown, isTrue);
      expect(_moves.first, '1:spam');
      if (w > 700) {
        expect(menuHasSpam, isTrue);
        expect(_moves, contains('2:trash'), reason: 'Delete moves to Trash, not gone for good');
      }
      expect(_moves.last, '7:inbox');
      expect(_requests.where((r) => r.startsWith('DELETE')), isEmpty);
    });
  }
}
