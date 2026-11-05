import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/models/search_result.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/top_bar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

// Top-bar search: menu pages + records grouped by type, arrow keys + Enter,
// at desktop width (inline dropdown) and phone width (full-screen page).
void main() {
  final records = [
    {'type': 'shipment', 'id': 7, 'title': 'SHP-2026-0042', 'subtitle': 'Kanam Latex Industries Sdn Bhd · Surgical gloves, sterile, size 7.5 — 40 cartons by air'},
    {'type': 'purchase_order', 'id': 492, 'title': 'PO-2026-0003', 'subtitle': 'Kanam Latex Industries Sdn Bhd · pending director final'},
    {'type': 'shipment', 'id': 8, 'title': 'SHP-2026-0043', 'subtitle': 'Mindray Medical International · BC-5150 analysers'},
    {'type': 'meeting', 'id': 3, 'title': 'Shipments and clearing weekly review with Swissport and Rangel', 'subtitle': '04 Nov 2026 · Board room'},
  ];

  void stubApi() {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {}
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': o.path.endsWith('/search') ? records : []}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
  }

  testWidgets('desktop: pages first, grouped records, keyboard opens the highlighted one', (tester) async {
    stubApi();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SearchResult? opened;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Column(children: [
      TopBar(onOpenSearchResult: (r) => opened = r, canOpenPage: (k) => k != 'shipment_settings'),
    ]))));
    await tester.enterText(find.byType(TextField).first, 'ship');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('PAGES'), findsOneWidget);
    expect(find.text('Shipments'), findsWidgets);
    expect(find.text('SHIPMENTS'), findsOneWidget);
    expect(find.text('PURCHASE ORDERS'), findsOneWidget);
    expect(find.text('MEETINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Row order: page(s), then both shipments together, then the PO, then the meeting.
    final pageCount = matchSearchPages('ship', (k) => k != 'shipment_settings').length;
    for (var i = 0; i < pageCount + 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened?.type, 'shipment');
    expect(opened?.id, 8);
  });

  testWidgets('phone: full-screen search fits and opens a result', (tester) async {
    stubApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SearchResult? opened;

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Column(children: [
      TopBar(compact: true, title: 'Dashboard', onOpenSearchResult: (r) => opened = r),
    ]))));
    await tester.tap(find.byIcon(Symbols.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'kanam');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('PO-2026-0003'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('PO-2026-0003'));
    await tester.pumpAndSettle();
    expect(opened?.type, 'purchase_order');
  });
}
