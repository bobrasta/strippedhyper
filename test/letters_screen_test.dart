import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/screens/letters/letters_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Letters: the list, a new letter (serial reference from the server), and
// the signatory signing it — at desktop and phone width.
void main() {
  Map<String, dynamic> letter({bool signed = false}) => {
    'id': 1, 'reference_number': 'HHL/2026/0001', 'letter_date': '2026-11-03',
    'recipient': 'The Executive Director\nMuhimbili National Hospital', 'subject': 'Supply of surgical gloves size 7.5',
    'body': 'Dear Sir,\n\nWe are pleased to confirm availability.', 'signatory': {'id': 57, 'name': 'Moses Deogratius Kiduduye', 'has_signature': true},
    'signatory_position': 'Managing Director', 'signed_at': signed ? '2026-11-03T10:00:00Z' : null, 'include_stamp': true,
    'created_by': {'id': 56, 'name': 'Administration'}, 'can_edit': true, 'can_sign': true,
  };

  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets('letters at ${size.width.toInt()} px: list, new letter, sign', (tester) async {
      try {
        authTokenNotifier = ValueNotifier<String?>('test-token');
      } catch (_) {/* already set */}
      Map<String, dynamic>? created;
      var signed = false;
      final stub = InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = {'data': <dynamic>[]};
        if (o.method == 'GET' && o.path.endsWith('/letters')) {
          body = {'data': [letter(signed: signed)], 'meta': {'has_stamp': true, 'my_signature': true, 'can_manage_stamp': true}};
        } else if (o.path.endsWith('/letters/signatories')) {
          body = {'data': [{'id': 57, 'name': 'Moses Deogratius Kiduduye', 'position': 'Managing Director', 'has_signature': true}]};
        } else if (o.method == 'POST' && o.path.endsWith('/letters')) {
          created = Map<String, dynamic>.from(o.data as Map);
          body = {'data': letter()..['id'] = 2..['reference_number'] = 'HHL/2026/0002'};
        } else if (o.path.endsWith('/letters/1/sign')) {
          signed = true;
          body = {'data': letter(signed: true)};
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      });
      ApiClient.instance.dio.interceptors.insert(0, stub);
      addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: LettersScreen())));
      await tester.pumpAndSettle();
      expect(find.text('HHL/2026/0001'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'list');

      // New letter.
      await tester.tap(find.text(size.width < 600 ? 'New' : 'New letter'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'form');
      Finder field(String label) => find.descendant(of: find.widgetWithText(LabeledTextField, label).first, matching: find.byType(TextField));
      await tester.enterText(field('To (recipient and address)'), 'The Director\nMNH');
      await tester.enterText(field('Subject'), 'Gloves');
      await tester.tap(find.text('Save letter'));
      await tester.pumpAndSettle();
      expect(created?['subject'], 'Gloves');
      expect(created?['recipient'], 'The Director\nMNH');

      // Open it and sign.
      await tester.tap(find.text('HHL/2026/0001'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'detail');
      await tester.tap(find.text('Sign').last);
      await tester.pumpAndSettle();
      expect(signed, isTrue);
      expect(find.textContaining('Signed by Moses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
