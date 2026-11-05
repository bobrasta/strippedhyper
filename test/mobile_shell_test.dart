import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/trial_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every API call with an empty list, so screens render without
/// reaching the network.
void _stubApi() {
  ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
    final data = <dynamic>[];
    h.resolve(Response(requestOptions: o, statusCode: 200, data: {
      'data': data,
      'meta': {'current_page': 1, 'last_page': 1, 'total': data.length},
    }));
  }));
}

Future<void> _pumpPhone(WidgetTester tester, String role) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  userRoleNotifier.value = role;
  userPermissionsNotifier.value = {};
  await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const AppShell()));
  await tester.pump(const Duration(seconds: 1));
}

/// Unmounts the shell (stops its background sync) before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// The bottom bar's labels, left to right.
List<String> _tabLabels(WidgetTester tester) {
  final bar = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_BottomTabBar');
  return tester
      .widgetList<Text>(find.descendant(of: bar, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
}

void main() {
  setUpAll(() {
    try {
      trialNotifier = ValueNotifier(const TrialStatus(state: TrialState.valid));
    } catch (_) {/* already set by another test in this isolate */}
    _stubApi();
  });

  testWidgets('phone tabs follow the role — HR never sees Revenue', (tester) async {
    await _pumpPhone(tester, 'hr');
    expect(_tabLabels(tester), ['Home', 'Directory', 'HR Approvals', 'Attendance', 'More']);
    await _unmount(tester);
  });

  testWidgets('a role with only self-service screens gets only those as tabs', (tester) async {
    await _pumpPhone(tester, 'technician');
    expect(_tabLabels(tester), ['Home', 'My Leave', 'Notifications', 'More']);
    await _unmount(tester);
  });

  testWidgets('top bar shows the page title; back goes to Home before leaving', (tester) async {
    await _pumpPhone(tester, 'storekeeper');
    expect(_tabLabels(tester), ['Home', 'Items', 'Staff', 'My Leave', 'More']);
    // Storekeeper lands on Inventory → title names it.
    expect(find.text('Items'), findsNWidgets(2)); // top bar + tab
    expect(find.text('Inventory Items'), findsOneWidget); // the screen's own header

    final exits = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'SystemNavigator.pop') exits.add(c);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Home'), findsNWidgets(2), reason: 'back from a tab returns to Home');
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, hasLength(1), reason: 'back on Home leaves the app');
    await _unmount(tester);
  });

  testWidgets('search icon opens full-screen search on phones', (tester) async {
    await _pumpPhone(tester, 'technician');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('Search pages, records, people…'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Search pages, records, people…'), findsNothing);
    await _unmount(tester);
  });
}
