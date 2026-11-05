import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/models/purchase_order.dart';
import 'package:bienhypermed/screens/inventory/purchase_orders_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// New purchase order: each line's unit cost has its own currency, a product
// not in inventory can be added from the line, and lines in two currencies
// save as two draft orders.
void main() {
  testWidgets('per-line currency, add a new product, one draft per currency', (tester) async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    final posted = <Map<String, dynamic>>[];
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      dynamic data = <dynamic>[];
      if (o.path.endsWith('/suppliers')) data = [{'id': 7, 'name': 'Boditech Med', 'currency': 'USD'}];
      if (o.path.endsWith('/locations')) data = [{'id': 1, 'name': 'Dar es Salaam Main Warehouse'}];
      if (o.path.endsWith('/inventory')) data = [{'id': 51, 'sku': 'RGT-0017', 'name': 'iChroma FSH', 'unit_cost': 40, 'cost_currency': 'USD'}];
      if (o.path.endsWith('/inventory/quick-create')) {
        data = {'id': 99, 'sku': 'QR-1', 'name': (o.data as Map)['name'], 'cost_currency': (o.data as Map)['cost_currency']};
      }
      if (o.method == 'POST' && o.path.endsWith('/purchase-orders')) {
        posted.add(Map<String, dynamic>.from(o.data as Map));
        data = {'id': posted.length, 'po_number': 'PO-${posted.length}', 'status': 'draft', 'currency': (o.data as Map)['currency'], 'items': []};
      }
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': data}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Builder(builder: (ctx) =>
        Scaffold(body: TextButton(onPressed: () => showNewPurchaseOrder(ctx), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Unit cost'), findsOneWidget);
    expect(find.text('Unit cost (TZS)'), findsNothing);

    // Supplier in USD: the empty line follows it.
    final fields = find.byType(TextField);
    await tester.tap(fields.at(0));
    await tester.enterText(fields.at(0), 'bodi');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boditech Med').last);
    await tester.pumpAndSettle();

    // Line 1: a product that isn't in inventory yet.
    final item = find.widgetWithText(TextField, 'Search catalogue…').first;
    await tester.tap(item);
    await tester.enterText(item, 'Zybio new reagent');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new product: "Zybio new reagent"'));
    await tester.pumpAndSettle();

    // A cost with cents counts in the total.
    Finder field(String label) => find.descendant(
        of: find.widgetWithText(LabeledTextField, label).first, matching: find.byType(TextField));
    await tester.enterText(field('Unit cost'), '12.50');
    await tester.enterText(field('Qty'), '3');
    await tester.pumpAndSettle();
    expect(find.text('USD 37.50'), findsOneWidget);

    // Line 2 in TZS.
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    final item2 = find.widgetWithText(TextField, 'Search catalogue…').last;
    await tester.tap(item2);
    await tester.enterText(item2, 'fsh');
    await tester.pumpAndSettle();
    await tester.tap(find.text('RGT-0017 · iChroma FSH').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TZS').last);
    await tester.pumpAndSettle();

    expect(find.text('Create 2 drafts'), findsOneWidget);
    await tester.tap(find.text('Create 2 drafts'));
    await tester.pumpAndSettle();
    expect(posted.map((p) => p['currency']), ['USD', 'TZS']);
    expect((posted[0]['items'] as List).single['inventory_item_id'], 99);
    expect((posted[0]['items'] as List).single['unit_cost'], 12.5);
    expect((posted[1]['items'] as List).single['inventory_item_id'], 51);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a draft order saves its lines back to the same order', (tester) async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    Map<String, dynamic>? put;
    var created = 0;
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      dynamic data = <dynamic>[];
      if (o.path.endsWith('/suppliers')) data = [{'id': 7, 'name': 'Local Gloves Ltd', 'currency': 'TZS'}];
      if (o.path.endsWith('/locations')) data = [{'id': 1, 'name': 'Dar es Salaam Main Warehouse'}];
      if (o.path.endsWith('/inventory')) data = [{'id': 1675, 'sku': 'CON-GLOVES-GYN-75', 'name': 'Gloves gynecological 7.5'}];
      if (o.method == 'PUT') {
        put = Map<String, dynamic>.from(o.data as Map);
        data = {'id': 5, 'po_number': 'PO-2026-0005', 'status': 'draft', 'currency': 'TZS', 'items': []};
      }
      if (o.method == 'POST' && o.path.endsWith('/purchase-orders')) created++;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': data}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final po = PurchaseOrder.fromJson({
      'id': 5, 'po_number': 'PO-2026-0005', 'status': 'draft', 'currency': 'TZS', 'supplier_id': 7,
      'location_id': 1, 'total_amount': 50000, 'notes': 'Size 7.5',
      'items': [{'id': 9, 'inventory_item_id': 1675, 'quantity_ordered': 10, 'unit_cost': 5000, 'currency': 'TZS',
                 'inventory_item': {'id': 1675, 'sku': 'CON-GLOVES-GYN-75', 'name': 'Gloves gynecological 7.5'}}],
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Builder(builder: (ctx) =>
        Scaffold(body: TextButton(onPressed: () => showNewPurchaseOrder(ctx, editing: po), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit PO-2026-0005'), findsOneWidget);
    expect(find.text('TZS 50,000'), findsOneWidget);

    Finder field(String label) => find.descendant(
        of: find.widgetWithText(LabeledTextField, label).first, matching: find.byType(TextField));
    await tester.enterText(field('Unit cost'), '5500.50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(created, 0);
    expect(put?['notes'], 'Size 7.5');
    expect(put?['location_id'], 1);
    final line = (put?['items'] as List).single as Map;
    expect(line['inventory_item_id'], 1675);
    expect(line['quantity_ordered'], 10);
    expect(line['unit_cost'], 5500.5);
    expect(tester.takeException(), isNull);
  });
}
