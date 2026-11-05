import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/local_db.dart';
import 'package:bienhypermed/services/trial_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every call answers `{"data": []}`, except `/probe`, which waits for
/// [probe] so the test decides when the revalidation lands.
class _Adapter implements HttpClientAdapter {
  Completer<void> probe = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    if (o.path == '/probe') await probe.future;
    return ResponseBody.fromString(
      jsonEncode({'data': o.path == '/probe' ? ['fresh'] : []}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Finder _screenKey(int n) => find.byKey(ValueKey('screen-$n'));

void main() {
  late _Adapter adapter;

  setUpAll(() {
    try {
      trialNotifier = ValueNotifier(const TrialStatus(state: TrialState.valid));
    } catch (_) {/* already set by another test in this isolate */}
    try {
      authTokenNotifier = ValueNotifier<String?>('token');
    } catch (_) {}
    adapter = _Adapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;
    LocalDb.instance = LocalDb.openInMemory();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    userRoleNotifier.value = 'admin';
    userIdNotifier.value = 3;
    adapter.probe = Completer<void>();
    ApiClient.instance.diskCache.resetSession();
    LocalDb.instance!.putResponse(3, '/probe', Uint8List.fromList(utf8.encode('{"data":["stale"]}')));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark),
        home: const AppShell(initialScreenKey: 'my_leave')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('untouched screen is remounted silently with the fresh data', (tester) async {
    await pumpShell(tester);
    expect(_screenKey(0), findsOneWidget);

    Response<dynamic>? res;
    ApiClient.instance.dio.get('/probe').then((r) => res = r);
    await tester.pump(const Duration(milliseconds: 50));
    expect(res?.data, {'data': ['stale']}); // answered from disk
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    adapter.probe.complete();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(_screenKey(1), findsOneWidget);
    expect(find.text('Updated data available'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a touched screen gets the chip instead, and Refresh remounts it', (tester) async {
    await pumpShell(tester);
    ApiClient.instance.dio.get('/probe');
    await tester.pump(const Duration(milliseconds: 50));
    // The user starts working in the content area.
    await tester.tapAt(const Offset(800, 600));
    adapter.probe.complete();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(_screenKey(0), findsOneWidget);
    expect(find.text('Updated data available'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(_screenKey(1), findsOneWidget);
    expect(find.text('Updated data available'), findsNothing);
    await unmount(tester);
  });
}
