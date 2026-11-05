import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/screens/approvals/approvals_screen.dart';
import 'package:bienhypermed/screens/finance/connections_screen.dart';
import 'package:bienhypermed/screens/finance/creditors_screen.dart';
import 'package:bienhypermed/screens/finance/vendor_bills_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Creditors Ledger, statement, connections, the Supplier Payments approval
// tab and supplier invoices, laid out with realistic (made-up) data at phone
// and desktop widths.

Map<String, dynamic> _creditor(int id, String name, String cur, double bal, {String type = 'supplier'}) => {
  'type': type, 'id': id, 'name': name, 'kind': type == 'vendor' ? 'delivery' : 'manufacturer',
  'category': cur == 'TZS' ? 'local' : 'international', 'currency': cur, 'country': cur == 'TZS' ? 'Tanzania' : 'China',
  'contact_person': 'Ms Li Wei (Export Sales Manager)', 'phone': '+86 755 2600 1234', 'email': 'export.sales@biobase-medstar.example.com',
  'is_active': true, 'balance': bal, 'balance_tzs': (bal * (cur == 'TZS' ? 1 : 2670)).round(),
  'book_balance_tzs': (bal * (cur == 'TZS' ? 1 : 2633)).round(), 'total_credit': bal + 120000, 'total_debit': 120000.0,
  'last_activity': '2026-06-06', 'lines': 4, 'pending_payments': id == 1 ? 1 : 0, 'pending_amount': id == 1 ? 1420.0 : 0,
};

final _creditors = [
  _creditor(1, 'BIOBASE MEDSTAR CO., LTD — Jinan International Medical Equipment Division', 'USD', 1420),
  _creditor(2, 'DIASORIN S.p.A.', 'EUR', 25500),
  _creditor(3, 'USIRI TRANSPORT & LOGISTICS COMPANY LIMITED', 'TZS', 3900000, type: 'vendor'),
];

Map<String, dynamic> _line(String date, String narration, String? ref, double rate, {double debit = 0, double credit = 0, required double balance, String src = 'vendor_bill'}) => {
  'date': date, 'narration': narration, 'ref': ref, 'rate': rate, 'debit': debit, 'credit': credit,
  'debit_tzs': (debit * rate).round(), 'credit_tzs': (credit * rate).round(), 'balance': balance, 'balance_tzs': (balance * rate).round(),
  'source': {'type': src, 'id': 7},
};

final _statement = {
  'creditor': _creditors[0], 'period': {'from': null, 'to': '2026-10-20'}, 'opening_balance': 0, 'opening_balance_tzs': 0,
  'entries': [
    _line('2026-01-01', 'OPENING BALANCE', null, 2600, credit: 120500, balance: 120500, src: 'creditor_opening'),
    _line('2026-02-02', 'INVOICE — PO-2026-0042 — Biosafety cabinets class II A2 ×2 and spare HEPA filters', 'PV1', 2650, credit: 920, balance: 121420),
    _line('2026-05-03', "EQUITY BANK USD 300'452 — PO-2026-0042", 'BP 02/5', 2655, debit: 95000, balance: 26420, src: 'supplier_payment'),
    _line('2026-06-06', "EQUITY BANK USD 300'452", 'BP 11/6', 2670, debit: 25000, balance: 1420, src: 'supplier_payment'),
  ],
  'total_credit': 121420, 'total_debit': 120000, 'total_credit_tzs': 315738000, 'total_debit_tzs': 318975000,
  'closing_balance': 1420, 'closing_balance_tzs': 3791400, 'book_balance_tzs': 3738000, 'opening': {'id': 1, 'as_at': '2026-01-01', 'amount': 120500, 'exchange_rate': 2600, 'notes': null},
};

final _payment = {
  'id': 9, 'payment_number': 'SPAY-2026-0009', 'creditor_type': 'supplier', 'creditor_id': 1,
  'creditor_name': 'BIOBASE MEDSTAR CO., LTD — Jinan International Medical Equipment Division',
  'purchase_order': null, 'vendor_bill': {'id': 7, 'bill_number': 'BILL-2026-0007', 'supplier_reference': 'PV1'},
  'currency': 'USD', 'amount': 1420.0, 'exchange_rate': 2685.5, 'amount_tzs': 3813410, 'paid_from': {'id': 13, 'code': '1013', 'name': "Equity Bank USD 300'452"},
  'payment_date': '2026-10-20', 'reference': 'TT 0042/10 balance on PV1', 'notes': 'Balance on the February invoice before the next shipment leaves Qingdao.',
  'status': 'pending_director', 'fx_difference_tzs': 0, 'settled': [], 'advance': null, 'initiated_by': 'Neema Accountant', 'initiated_at': '2026-10-20T08:00:00Z',
};

final _web = {
  'subject': {'key': 'purchase_order:42', 'type': 'purchase_order', 'id': 42, 'depth': 0, 'title': 'PO-2026-0042', 'subtitle': 'LPO · BIOBASE MEDSTAR CO., LTD', 'status': 'received · partial', 'amount': 2000, 'currency': 'USD', 'date': '2026-01-20'},
  'nodes': [
    {'key': 'purchase_order:42', 'type': 'purchase_order', 'id': 42, 'depth': 0, 'title': 'PO-2026-0042', 'subtitle': 'LPO', 'status': 'received', 'amount': 2000, 'currency': 'USD', 'date': '2026-01-20'},
    {'key': 'supplier:1', 'type': 'supplier', 'id': 1, 'depth': 1, 'title': 'BIOBASE MEDSTAR CO., LTD — Jinan International Medical Equipment Division', 'subtitle': 'Supplier · manufacturer · USD', 'status': 'active', 'amount': null, 'currency': 'USD', 'date': null},
    {'key': 'supplier_payment:9', 'type': 'supplier_payment', 'id': 9, 'depth': 1, 'title': 'SPAY-2026-0003', 'subtitle': "Payment from Equity Bank USD 300'452 · TT 0042", 'status': 'paid', 'amount': 95000, 'currency': 'USD', 'date': '2026-05-03'},
    {'key': 'vendor_bill:7', 'type': 'vendor_bill', 'id': 7, 'depth': 1, 'title': 'PV1', 'subtitle': 'Supplier invoice · BIOBASE', 'status': 'partial', 'amount': 920, 'currency': 'USD', 'date': '2026-02-02'},
    {'key': 'shipment:3', 'type': 'shipment', 'id': 3, 'depth': 1, 'title': 'SHP-2026-0003', 'subtitle': 'Shipment · Biosafety cabinets ×2 — JNIA Dar es Salaam', 'status': 'step 9', 'amount': null, 'currency': null, 'date': '2026-03-01'},
    {'key': 'vendor_fee:4', 'type': 'vendor_fee', 'id': 4, 'depth': 2, 'title': 'Fee 4', 'subtitle': 'RainFall Clearing · Clearing — SHP-2026-0003', 'status': 'paid', 'amount': 4000000, 'currency': 'TZS', 'date': '2026-03-20'},
    {'key': 'stock_movement:88', 'type': 'stock_movement', 'id': 88, 'depth': 1, 'title': 'Receive 2 × Biosafety cabinet BSC-1100IIA2-X', 'subtitle': 'Stock · Main Store Mikocheni · batch B2026-03', 'status': 'receive', 'amount': 7200000, 'currency': 'TZS', 'date': '2026-03-25'},
  ],
  'edges': [
    {'from': 'purchase_order:42', 'to': 'supplier:1', 'relation': 'supplier'},
    {'from': 'purchase_order:42', 'to': 'supplier_payment:9', 'relation': 'payment'},
    {'from': 'purchase_order:42', 'to': 'vendor_bill:7', 'relation': 'supplier invoice'},
    {'from': 'purchase_order:42', 'to': 'shipment:3', 'relation': 'shipment'},
    {'from': 'shipment:3', 'to': 'vendor_fee:4', 'relation': 'clearing fee'},
    {'from': 'purchase_order:42', 'to': 'stock_movement:88', 'relation': 'received into store'},
  ],
  'timeline': [
    {'at': '2026-01-21T09:00:00Z', 'node': 'purchase_order:42', 'title': 'PO-2026-0042', 'action': 'Sales Manager approved', 'actor': 'Grace Sales Manager', 'role': 'sales_manager', 'detail': null},
    {'at': '2026-01-22T09:00:00Z', 'node': 'purchase_order:42', 'title': 'PO-2026-0042', 'action': 'Director reviewed', 'actor': 'Dr. Managing Director', 'role': 'super_admin', 'detail': null},
    {'at': '2026-05-03T10:00:00Z', 'node': 'supplier_payment:9', 'title': 'SPAY-2026-0003', 'action': 'Paid', 'actor': 'Dr. Managing Director', 'role': 'super_admin', 'detail': null},
    {'at': '2026-03-25T12:00:00Z', 'node': 'stock_movement:88', 'title': 'Receive 2 ×', 'action': 'Received into Main Store Mikocheni', 'actor': 'John Storekeeper', 'role': null, 'detail': 'Received via PO-2026-0042 — two crates, one dented, contents fine'},
  ],
  'ledger': [
    {'reference': 'BILL-7', 'date': '2026-02-02', 'account': '1006 Inventory', 'type': 'debit', 'amount': 2438000, 'description': 'Invoice PV1 — BIOBASE'},
    {'reference': 'BILL-7', 'date': '2026-02-02', 'account': '2024 Trade Creditors — International', 'type': 'credit', 'amount': 2438000, 'description': 'Invoice PV1 — BIOBASE'},
    {'reference': 'SPAY-9', 'date': '2026-05-03', 'account': '5059 Foreign Exchange Loss', 'type': 'debit', 'amount': 5225000, 'description': 'Exchange loss — SPAY-2026-0003'},
  ],
  'truncated': false,
};

final _bills = [
  {'id': 7, 'bill_number': 'BILL-2026-0007', 'supplier_reference': 'PV1', 'supplier_id': 1, 'supplier_name': 'BIOBASE MEDSTAR CO., LTD — Jinan International Medical Equipment Division',
    'purchase_order_id': 42, 'purchase_order_number': 'PO-2026-0042', 'issue_date': '2026-10-01', 'due_date': '2026-10-25',
    'subtotal': 920.0, 'tax_rate': 0, 'tax_amount': 0.0, 'total': 920.0, 'amount_paid': 0.0, 'balance_due': 920.0, 'status': 'pending',
    'currency': 'USD', 'exchange_rate': 2650.0, 'total_tzs': 2438000, 'line_items': [], 'payments': []},
  {'id': 8, 'bill_number': 'BILL-2026-0008', 'supplier_reference': null, 'supplier_id': 3, 'supplier_name': 'CYPRESS DIAGNOSTICS',
    'purchase_order_id': null, 'issue_date': '2026-09-01', 'due_date': '2026-09-30',
    'subtotal': 2000000.0, 'tax_rate': 18, 'tax_amount': 360000.0, 'total': 2360000.0, 'amount_paid': 1000000.0, 'balance_due': 1360000.0, 'status': 'partial',
    'currency': 'TZS', 'exchange_rate': 1.0, 'total_tzs': 2360000, 'line_items': [], 'payments': []},
];

dynamic _respond(RequestOptions o) {
  final p = o.path;
  if (p == '/creditors') {
    return {'data': {'as_at': '2026-10-20', 'creditors': _creditors,
      'totals': {'international_tzs': 3738000 + 68000000, 'local_tzs': 3900000, 'pending_payments': 1},
      'reconciliation': {'international': {'account': '2024', 'books': 71738000, 'ledgers': 71738000, 'difference': 0},
        'local': {'account': '2025', 'books': 7900000, 'ledgers': 3900000, 'difference': 4000000}},
      'can_manage': true}};
  }
  if (p.contains('/statement')) return {'data': _statement};
  if (p.startsWith('/connections/')) return {'data': _web};
  if (p == '/supplier-payments') return {'data': [_payment]};
  if (p == '/vendor-bills') return {'data': _bills, 'meta': {'total': 2}};
  return {'data': <dynamic>[]};
}

Future<List<String>> _layoutErrors(WidgetTester tester, Widget screen, double width, {Future<void> Function()? then}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (e) => errors.add(e.exceptionAsString().split('\n').first);
  try {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: Scaffold(body: screen)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (then != null) await then();
  } finally {
    FlutterError.onError = previous;
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  return errors;
}

void main() {
  setUpAll(() {
    userRoleNotifier.value = 'super_admin';
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: _respond(o)));
    }));
  });

  for (final w in [390.0, 1440.0]) {
    testWidgets('Creditors list at $w px', (tester) async {
      final errors = await _layoutErrors(tester, const CreditorsScreen(), w, then: () async {
        expect(find.textContaining('BIOBASE'), findsWidgets);
        expect(find.textContaining('USD 1,420.00'), findsWidgets);
        // The local books are off by the vendor fee: the banner says so.
        expect(find.textContaining('difference TSh 4,000,000'), findsOneWidget);
        await tester.tap(find.text('Local'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('USIRI'), findsWidgets);
      });
      expect(errors, isEmpty);
    });

    testWidgets('Creditor statement at $w px', (tester) async {
      final errors = await _layoutErrors(tester,
          const CreditorStatementScreen(type: 'supplier', id: 1, name: 'BIOBASE'), w, then: () async {
        expect(find.textContaining('OPENING BALANCE'), findsWidgets);
        expect(find.textContaining('awaiting the Director'), findsOneWidget);
        expect(find.textContaining('USD 1,420.00'), findsWidgets);
      });
      expect(errors, isEmpty);
    });

    testWidgets('Connections at $w px', (tester) async {
      final errors = await _layoutErrors(tester, const ConnectionsScreen(type: 'purchase_order', id: 42), w, then: () async {
        expect(find.textContaining('Sales Manager approved'), findsOneWidget);
        expect(find.textContaining('Received into Main Store'), findsOneWidget);
        await tester.scrollUntilVisible(find.textContaining('Foreign Exchange Loss'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Foreign Exchange Loss'), findsOneWidget);
      });
      expect(errors, isEmpty);
    });

    testWidgets('Supplier Payments approval tab at $w px', (tester) async {
      final errors = await _layoutErrors(tester, const ApprovalsScreen(initialTabIndex: 4), w, then: () async {
        expect(find.textContaining('SPAY-2026-0009'), findsOneWidget);
        expect(find.textContaining('USD 1,420.00 @ 2685.5'), findsOneWidget);
        expect(find.text('Money is out'), findsOneWidget);
      });
      expect(errors, isEmpty);
    });

    testWidgets('Supplier invoices in two currencies at $w px', (tester) async {
      final errors = await _layoutErrors(tester, const VendorBillsScreen(), w, then: () async {
        expect(find.textContaining('USD 920.00'), findsWidgets);
        expect(find.textContaining('TSh 1,360,000'), findsWidgets);
      });
      expect(errors, isEmpty);
    });
  }
}
