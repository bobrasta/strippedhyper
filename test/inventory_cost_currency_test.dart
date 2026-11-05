import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/screens/inventory/inventory_items_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Inventory → Add Item: the unit cost has a currency picker, sent as cost_currency.
void main() {
  testWidgets('Add Item offers a currency for the unit cost', (tester) async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': o.method == 'POST'
          ? {'id': 1, 'sku': 'X', 'name': 'X'} : <dynamic>[]}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: InventoryItemsScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Add Item').first);
    await tester.pumpAndSettle();
    expect(find.text('Unit Cost'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('TZS'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
