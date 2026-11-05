import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/trial_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_shell.dart';
import 'package:bienhypermed/widgets/common/email_badge.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the shell at [size] with the Email badge showing [unread]/[failed],
/// returning any layout overflow reported meanwhile.
Future<List<String>> _pumpShell(WidgetTester tester, Size size, {required String role,
    required int unread, required int failed}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  userRoleNotifier.value = role;
  userPermissionsNotifier.value = {};
  emailBadgeNotifier.value = (unread: unread, failed: failed);
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (e) {
    if (e.exceptionAsString().contains('overflowed')) overflows.add(e.exceptionAsString().split('\n').first);
  };
  try {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const AppShell()));
    await tester.pump(const Duration(milliseconds: 500));
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

Future<void> _unmount(WidgetTester tester) async {
  emailBadgeNotifier.value = (unread: 0, failed: 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    try {
      trialNotifier = ValueNotifier(const TrialStatus(state: TrialState.valid));
    } catch (_) {/* already set by another test in this isolate */}
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': <dynamic>[]}));
    }));
  });

  test('labels cap at 99+', () {
    expect(EmailNavBadge.label(7), '7');
    expect(EmailNavBadge.label(99), '99');
    expect(EmailNavBadge.label(100), '99+');
  });

  testWidgets('phone: badge on the Email tab, both pills, no overflow', (tester) async {
    // cs: Home, Customers, Service, Email… — Email is one of the tabs.
    final overflows = await _pumpShell(tester, const Size(390, 844), role: 'cs', unread: 250, failed: 3);
    expect(overflows, isEmpty);
    expect(find.text('99+'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.byTooltip('3 failed to send'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('phone: badge on More when Email is not a tab', (tester) async {
    final overflows = await _pumpShell(tester, const Size(320, 640), role: 'admin', unread: 12, failed: 0);
    expect(overflows, isEmpty);
    expect(find.text('12'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('tablet rail and desktop sidebar show it too', (tester) async {
    for (final size in const [Size(900, 800), Size(1440, 900)]) {
      final overflows = await _pumpShell(tester, size, role: 'admin', unread: 5, failed: 2);
      expect(overflows, isEmpty, reason: '$size');
      expect(find.text('5'), findsWidgets, reason: '$size');
      expect(find.byTooltip('2 failed to send'), findsWidgets, reason: '$size');
    }
    await _unmount(tester);
  });

  testWidgets('hidden at zero', (tester) async {
    await _pumpShell(tester, const Size(1440, 900), role: 'admin', unread: 0, failed: 0);
    expect(find.byType(EmailNavBadge), findsWidgets);
    expect(find.descendant(of: find.byType(EmailNavBadge), matching: find.byType(Text)), findsNothing);
    await _unmount(tester);
  });
}
