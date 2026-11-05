import 'package:bienhypermed/models/purchase_order.dart';
import 'package:bienhypermed/models/purchase_return.dart';
import 'package:bienhypermed/screens/purchases/all_purchases_screen.dart';
import 'package:bienhypermed/screens/purchases/purchase_returns_screen.dart';
import 'package:bienhypermed/services/purchase_order_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PurchaseOrder _po(int id, String status, {String pay = 'unpaid', int total = 4500000, int paid = 0, int returned = 0, String currency = 'TZS'}) =>
    PurchaseOrder.fromJson({
      'id': id,
      'po_number': 'CH-PO2026/00$id',
      'supplier': {'name': 'Supplier number $id Medical Distributors Limited'},
      'location': {'name': 'Main store Dar es Salaam'},
      'ordered_by': {'name': id.isEven ? 'Ansa Kambaganya' : 'Moses Kiduduye'},
      'status': status,
      'currency': currency,
      'total_amount': total,
      'amount_paid': paid,
      'payment_status': pay,
      'returned_amount': returned,
      'created_at': '2026-09-${10 + id}T09:00:00Z',
    });

PurchaseReturn _ret(int id, {bool posted = false}) => PurchaseReturn.fromJson({
      'id': id,
      'return_number': 'PRET-2026-000$id',
      'purchase_order_id': id,
      'purchase_order': {'po_number': 'CH-PO2026/00$id'},
      'supplier': {'name': 'Supplier number $id Medical Distributors Limited'},
      'location': {'name': 'Main store Dar es Salaam'},
      'created_by': {'name': 'Ansa Kambaganya'},
      'return_date': '2026-10-0$id',
      'currency': 'TZS',
      'total_amount': 250000 * id,
      'posted': posted,
      'reason': 'Expired on arrival',
      'items': [
        {'id': id, 'quantity': id, 'unit_cost': 250000, 'total': 250000 * id, 'inventory_item': {'name': 'Ichroma CRP cartridges', 'sku': 'HH-12'}},
      ],
    });

void main() {
  Future<void> pump(WidgetTester tester, Size size, Widget screen) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PurchaseOrderService.cachedDefaultList = [
      _po(1, 'received', pay: 'paid', paid: 4500000),
      _po(2, 'pending_sales_manager'),
      _po(3, 'received', pay: 'partial', paid: 1000000, returned: 500000),
      _po(4, 'sent', currency: 'USD', total: 12000),
      _po(5, 'cancelled'),
    ];
    PurchaseOrderService.cachedDefaultReturns = [_ret(1, posted: true), _ret(3)];
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (e) {
      if (e.exceptionAsString().contains('overflowed')) overflows.add(e.exceptionAsString().split('\n').first);
    };
    try {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: screen)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      FlutterError.onError = previous;
    }
    expect(overflows, isEmpty);
  }

  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('List purchases: Clickhuduma columns, totals, right-click menu', (tester) async {
    await pump(tester, const Size(1440, 900), const AllPurchasesScreen());
    for (final h in ['REFERENCE NO', 'LOCATION', 'SUPPLIER', 'PURCHASE STATUS', 'PAYMENT STATUS', 'GRAND TOTAL', 'ADDED BY']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('PAYMENT DUE'), findsNWidgets(2)); // summary card + column
    expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsNothing);
    // Cancelled purchases don't count; shillings lead, dollars follow.
    expect(find.text('TSh 13,500,000'), findsOneWidget);          // 3 live TZS purchases
    expect(find.textContaining('USD 12,000'), findsWidgets);
    expect(find.text('TSh 3,000,000'), findsWidgets);             // due on CH-PO2026/003 after its return
    expect(find.text('TSh 500,000'), findsOneWidget);             // purchase returns tile

    await tester.tap(find.text('CH-PO2026/003'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final a in ['View', 'Print', 'Submit for approval', 'Cancel purchase', 'Purchase Return']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    // Status chips filter.
    await tester.tap(find.text('In approval'));
    await tester.pump();
    expect(find.text('CH-PO2026/002'), findsOneWidget);
    expect(find.text('CH-PO2026/001'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets('List purchases fits a phone with real data', (tester) async {
    await pump(tester, const Size(390, 844), const AllPurchasesScreen());
    expect(find.text('Purchases'), findsOneWidget);
    // Cards sit under the summary tiles: scroll to them (no overflow on the way).
    await tester.scrollUntilVisible(find.text('Supplier number 1 Medical Distributors Limited'), 300,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    expect(find.text('Supplier number 1 Medical Distributors Limited'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('List purchase returns at desktop and phone width', (tester) async {
    await pump(tester, const Size(1440, 900), const PurchaseReturnsScreen());
    for (final h in ['REFERENCE NO', 'PARENT PURCHASE', 'SUPPLIER', 'GRAND TOTAL', 'SUPPLIER ACCOUNT', 'ADDED BY']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Credited'), findsOneWidget);
    expect(find.text('Stock only'), findsOneWidget);
    expect(find.text('TSh 1,000,000'), findsOneWidget);           // 250,000 + 750,000
    await tester.tap(find.text('PRET-2026-0003'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final a in ['View', 'Print', 'View parent purchase']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase return · PRET-2026-0003'), findsOneWidget);
    expect(find.text('Expired on arrival'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, const Size(390, 844), const PurchaseReturnsScreen());
    await tester.scrollUntilVisible(find.textContaining('PRET-2026-0001 · '), 300,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    expect(find.textContaining('PRET-2026-0001 · '), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktop);
}
