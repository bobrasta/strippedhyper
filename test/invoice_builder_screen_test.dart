import 'package:bienhypermed/main.dart' show authTokenNotifier;
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/invoice_service.dart';
import 'package:dio/dio.dart';
import 'package:bienhypermed/models/invoice.dart';
import 'package:bienhypermed/screens/sales/invoice_builder_screen.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/sales/line_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
    await tester.pump(const Duration(milliseconds: 50));
  }

  final draft = Invoice.fromJson({
    'id': 9, 'invoice_number': 'DRAFT-2026-0003', 'client_name': 'Mwangaza Polyclinic',
    'issue_date': '2026-09-30', 'due_date': '2026-10-30', 'pay_term_number': 30, 'pay_term_type': 'days',
    'subtotal': 50000, 'total': 50000, 'amount_paid': 0, 'status': 'draft', 'sale_status': 'draft',
    'staff_note': 'confirm price', 'line_items': [{'description': 'X-ray film', 'quantity': 10, 'unit_price': 5000, 'total': 50000}],
  });

  testWidgets('new sale offers Final / Draft / Quotation / Proforma', (tester) async {
    await pump(tester, const InvoiceBuilderScreen());
    expect(find.text('Add sale'), findsOneWidget);
    expect(find.text('Status *'), findsOneWidget);
    await tester.tap(find.text('Final').first);
    await tester.pumpAndSettle();
    for (final s in ['Draft', 'Quotation', 'Proforma']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await tester.tap(find.text('Draft').last);
    await tester.pumpAndSettle();
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.text('Client TIN'), findsOneWidget); // optional for a draft
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a draft pre-fills it and can finalise', (tester) async {
    await pump(tester, InvoiceBuilderScreen(editing: draft));
    expect(find.text('Edit DRAFT-2026-0003'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'X-ray film'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'confirm price'), findsOneWidget);
    expect(find.text('Quotation'), findsNothing); // not offered when editing
    expect(tester.takeException(), isNull);
  });

  // Sidebar "Add draft" / "Add quotation" open the form on that status.
  testWidgets('opens on the status the sidebar asked for', (tester) async {
    await pump(tester, const InvoiceBuilderScreen(initialStatus: 'draft'));
    expect(find.text('Add draft'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);

    await pump(tester, const InvoiceBuilderScreen(key: ValueKey('q'), initialStatus: 'quotation'));
    expect(find.text('Add quotation'), findsOneWidget);
    expect(find.text('Save quotation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('line discount in TSh comes off the line and the totals', (tester) async {
    await pump(tester, const InvoiceBuilderScreen());
    expect(find.text('DISCOUNT (TSH)'), findsOneWidget);
    final entry = tester.widget<LineItemTableRow>(find.byType(LineItemTableRow)).entry;
    entry.qtyCtrl.text = '2';
    entry.priceCtrl.text = '500000'; // 2 x 500,000 = 1,000,000
    entry.discCtrl.text = '150000';
    await tester.pump();
    expect(find.text('TSh 850K'), findsWidgets);          // line + TOTAL
    expect(find.text('TSh 1.0M'), findsOneWidget);        // subtotal before discount
    expect(find.text('- TSh 150K'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 81 of October's 86 sales (Clickhuduma imports) have no TIN; editing
  // one used to stop silently on "Client TIN is required".
  testWidgets('editing a final sale with no TIN saves', (tester) async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    final sent = <String>[];
    final finalSale = Invoice.fromJson({
      'id': 12, 'invoice_number': 'HH-51306', 'client_name': 'Eagle Regional Referral Hospital',
      'issue_date': '2026-10-01', 'due_date': '2026-10-31', 'pay_term_number': 30, 'pay_term_type': 'days',
      'subtotal': 50000, 'total': 50000, 'amount_paid': 50000, 'status': 'paid', 'sale_status': 'final',
      'hospital_id': 16308, 'hospital': {'id': 16308, 'name': 'Eagle Regional Referral Hospital'},
      'line_items': [{'description': 'Led Assay', 'quantity': 1, 'unit_price': 50000, 'total': 50000}],
    });
    Map<String, dynamic>? body;
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      sent.add('${o.method} ${o.path}');
      if (o.method == 'PUT') body = Map<String, dynamic>.from(o.data as Map);
      final isUpdate = o.method == 'PUT' && o.path.endsWith('/invoices/12');
      h.resolve(Response(requestOptions: o, statusCode: 200,
          data: {'data': isUpdate ? {'id': 12, 'invoice_number': 'HH-51306', 'status': 'paid', 'sale_status': 'final'} : <dynamic>[]}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));

    await pump(tester, InvoiceBuilderScreen(editing: finalSale));
    await tester.tap(find.text('Save changes'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Not saved'), findsNothing);
    expect(sent.where((s) => s.startsWith('PUT') && s.endsWith('/invoices/12')), hasLength(1));
    // The customer record hadn't loaded (stub answers []): the link is kept.
    expect(body?['hospital_id'], 16308);
  });

  // The product search shows each product's price, and a product with lots
  // in stock once per lot; picking a lot fills the lot and expiry.
  testWidgets('product search lists price and lots; a lot fills lot + expiry', (tester) async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    final stub = InterceptorsWrapper(onRequest: (o, h) {
      final data = switch (o.path) {
        final p when p.endsWith('/inventory-lots') => [
          {'inventory_item_id': 51, 'lot_number': 'DFSVLE11', 'expiry_date': '2027-08-23', 'qty_left': 10},
          {'inventory_item_id': 51, 'lot_number': 'DFSWBF01', 'expiry_date': '2027-10-18', 'qty_left': 27},
        ],
        final p when p.endsWith('/inventory') => [
          {'id': 51, 'sku': 'RGT-0017', 'name': 'iChroma FSH', 'unit_of_measure': 'box',
           'specifications': {'Selling price (TZS)': '215,000'}},
          {'id': 52, 'sku': 'HH-0061', 'name': 'Hemoglobinometer-Hemochromax Plus',
           'specifications': {'Selling price (TZS)': '800,000'}},
        ],
        _ => <dynamic>[],
      };
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': data}));
    });
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));

    await pump(tester, const InvoiceBuilderScreen());
    await tester.pump(const Duration(milliseconds: 50));
    final search = find.descendant(of: find.byType(LineItemTableRow), matching: find.byType(TextField)).first;
    await tester.tap(search);
    await tester.enterText(search, 'fsh');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('TSh 215,000 · Lot DFSVLE11 · Exp 23 Aug 2027 · 10 left'), findsOneWidget);
    expect(find.text('TSh 215,000 · Lot DFSWBF01 · Exp 18 Oct 2027 · 27 left'), findsOneWidget);

    // Click away and back: the list reopens on what matches the typed text,
    // not the whole catalog from the top.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Lot DFSWBF01'), findsNothing);
    await tester.tap(search);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('TSh 215,000 · Lot DFSWBF01 · Exp 18 Oct 2027 · 27 left'), findsOneWidget);
    expect(find.text('TSh 800,000'), findsNothing);

    await tester.enterText(search, 'hemochromax');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('TSh 800,000'), findsOneWidget); // no lots: one option, with its price

    await tester.enterText(search, 'DFSWBF');            // the lot number finds it too
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('TSh 215,000 · Lot DFSWBF01 · Exp 18 Oct 2027 · 27 left'));
    await tester.pump(const Duration(milliseconds: 50));
    final entry = tester.widget<LineItemTableRow>(find.byType(LineItemTableRow)).entry;
    expect(entry.descCtrl.text, 'iChroma FSH');
    expect(entry.priceCtrl.text, '215000');
    expect(entry.lotCtrl.text, 'DFSWBF01');
    expect(entry.expiry, DateTime(2027, 10, 18));
    expect(tester.takeException(), isNull);
  });

  // get() waited on its own future (whenComplete returned the map entry),
  // so Edit / Add payment in All sales never opened.
  test('InvoiceService.get completes', () async {
    try {
      authTokenNotifier = ValueNotifier<String?>('test-token');
    } catch (_) {/* already set */}
    final stub = InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200,
        data: {'data': {'id': 77, 'invoice_number': 'INV-77', 'status': 'pending', 'line_items': <dynamic>[]}})));
    ApiClient.instance.dio.interceptors.insert(0, stub);
    addTearDown(() => ApiClient.instance.dio.interceptors.remove(stub));
    final inv = await InvoiceService.instance.get(77).timeout(const Duration(seconds: 5));
    expect(inv.invoiceNumber, 'INV-77');
  });

  testWidgets('a blocked save says why at the top', (tester) async {
    await pump(tester, const InvoiceBuilderScreen());
    await tester.tap(find.text('Save sale'));
    await tester.pump();
    expect(find.textContaining('Not saved: '), findsOneWidget);
  });
}
