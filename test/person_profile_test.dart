import 'package:bienhypermed/main.dart' show authTokenNotifier, userIdNotifier;
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/chat_controller.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/people/person_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A colleague's profile card: photo/initials, position, department, reports
// to, contact, bio, qualifications and "Message" — at phone and desktop width.
void main() {
  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets('profile card at ${size.width.toInt()} px', (tester) async {
      try {
        authTokenNotifier = ValueNotifier<String?>('test-token');
      } catch (_) {}
      userIdNotifier.value = 1;
      chatAvailableNotifier.value = true;
      addTearDown(() => chatAvailableNotifier.value = false);
      final stub = InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': {
          'id': 2, 'name': 'Anna Mwakalinga Kisanga wa Kilimanjaro', 'avatar_url': null,
          'position': 'Senior Biomedical Engineer — Laboratory and Imaging Equipment', 'department': 'Technical Services',
          'role': 'technician', 'region': 'Kilimanjaro', 'email': 'anna.kisanga@hypermed.co.tz', 'phone': '+255 700 000 001',
          'joined': '2021-03-01', 'bio': 'Eight years on Mindray and Sysmex analysers across the northern zone.',
          'qualifications': ['BSc Biomedical Engineering (UDSM)', 'Mindray BC-5150 certified', 'Sysmex XN-L field service'],
          'reports_to': {'id': 9, 'name': 'Gabriel Shayo', 'position': 'CTO'}, 'is_active': true,
        }}));
      });
      ApiClient.instance.dio.interceptors.insert(0, stub);
      addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Builder(
        builder: (ctx) => Center(child: TextButton(onPressed: () => showPersonProfile(ctx, 2), child: const Text('open'))),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Anna Mwakalinga Kisanga wa Kilimanjaro'), findsOneWidget);
      expect(find.text('Technical Services'), findsOneWidget);
      expect(find.textContaining('Gabriel Shayo'), findsOneWidget);
      expect(find.text('Mindray BC-5150 certified'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Technical Services'), findsNothing);
    });
  }
}
