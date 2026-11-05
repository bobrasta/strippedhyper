import 'package:bienhypermed/models/invoice.dart';
import 'package:bienhypermed/screens/sales/all_sales_screen.dart';
import 'package:bienhypermed/services/invoice_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:bienhypermed/widgets/common/labeled_field.dart';
import 'package:bienhypermed/widgets/common/period_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Invoice _sale(int id, {String status = 'pending', String ch = 'due', int total = 1000000, int paid = 0}) => Invoice.fromJson({
      'id': id,
      'invoice_number': 'HH-$id',
      'client_name': 'Client $id Hospital',
      'contact_phone': '0754 000 00$id',
      'issue_date': '2026-09-${10 + id}',
      'due_date': '2026-10-${10 + id}',
      'subtotal': total,
      'total': total,
      'amount_paid': paid,
      'balance_due': total - paid,
      'status': status,
      'payment_status': ch,
      'sale_status': 'final',
      'added_by': id.isEven ? 'Leticia Mvukiye' : 'Moses Kiduduye',
      'total_items': 3,
      'payment_methods': paid > 0 ? ['bank_transfer'] : [],
      'notes': 'Sell note $id',
      'staff_note': id == 1 ? 'check stock' : null,
      'shipping_status': id == 2 ? 'shipped' : null,
    });

void main() {
  Future<void> pump(WidgetTester tester, Size size, {List<Invoice>? sales}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    InvoiceService.cachedDefaultList = sales ?? [
      _sale(1),
      _sale(2, status: 'paid', ch: 'paid', paid: 1000000),
      _sale(3, status: 'partial', ch: 'partial', paid: 400000),
    ];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: AllSalesScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Desktop: right-click and desktop scrollbars behave as in the app.
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('columns fit, summary above the table, right-click menu', (tester) async {
    await pump(tester, const Size(1600, 1000));

    for (final h in ['INVOICE NO.', 'CUSTOMER', 'STATUS', 'ADDED BY', 'SELL NOTE']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('SELL DUE'), findsNWidgets(2)); // summary card + column
    expect(find.text('STAFF NOTE'), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
    // No sideways scrolling.
    expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsNothing);
    expect(find.text('TOTAL SALES'), findsOneWidget);
    expect(find.text('TSh 3.0M'), findsOneWidget);   // total sales
    expect(find.text('TSh 1.6M'), findsOneWidget);   // sell due

    await tester.tap(find.text('HH-3'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final a in ['View', 'Edit', 'Delete', 'Edit Shipping', 'Print Invoice', 'Delivery Note',
                     'Add payment', 'View Payments', 'Duplicate Sell', 'Sell Return', 'Invoice URL', 'New Sale Notification']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets('click a column to sort; status chips filter', (tester) async {
    await pump(tester, const Size(1600, 1000));
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    // Newest first by default.
    expect(y('HH-3') < y('HH-1'), isTrue);
    await tester.tap(find.text('SELL DUE').last);
    await tester.pump();
    // Sell due, biggest first: HH-1 (1,000,000) above HH-3 (600,000) above HH-2 (0).
    expect(y('HH-1') < y('HH-3') && y('HH-3') < y('HH-2'), isTrue);
    await tester.tap(find.text('SELL DUE').last);
    await tester.pump();
    expect(y('HH-2') < y('HH-3'), isTrue);

    // The status chips sit in the filter row where the Sales/Drafts/Proformas tabs were.
    expect(find.text('Sales'), findsNothing);
    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Proformas'), findsOneWidget);
    expect(y('All'), lessThan(y('TOTAL SALES')));
    // Filter selects and the search box are all 28px; Export as sits in the header.
    expect(tester.getSize(find.byType(DropdownFieldBox<String?>).first).height, 28);
    expect(tester.getSize(find.byType(PeriodSelector)).height, 28);
    expect(tester.getSize(find.byType(SearchField)).height, 28);
    expect(find.text('Export as'), findsOneWidget);
    await tester.tap(find.text('Paid').first);
    await tester.pump();
    expect(find.text('HH-2'), findsOneWidget);
    expect(find.text('HH-1'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets('rows load 100 at a time', (tester) async {
    await pump(tester, const Size(1600, 1000),
        sales: [for (var n = 1; n <= 150; n++) _sale(n % 9 + 1).copyForTest(id: n, number: 'HH-${1000 + n}')]);
    await tester.scrollUntilVisible(find.textContaining('Load 50 more'), 400,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    expect(find.text('Showing 100 of 150 · Load 50 more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets('narrow window drops columns instead of scrolling sideways', (tester) async {
    await pump(tester, const Size(900, 800));
    expect(find.text('HH-2'), findsOneWidget);
    expect(find.text('SELL NOTE'), findsNothing);
    expect(find.text('SELL DUE'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  }, variant: desktop);
}

extension on Invoice {
  Invoice copyForTest({required int id, required String number}) => Invoice.fromJson({
        'id': id, 'invoice_number': number, 'client_name': displayName, 'issue_date': issueDate, 'due_date': dueDate,
        'total': total, 'amount_paid': amountPaid, 'balance_due': balanceDue, 'status': 'pending',
        'payment_status': chPaymentStatus, 'sale_status': 'final',
      });
}
