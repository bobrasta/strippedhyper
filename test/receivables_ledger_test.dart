import 'package:bienhypermed/screens/finance/receivables_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Customer ledger "as at" a date (Credit & Receivables): the accounts team's
// ABC example — invoiced 100M, paid 30M, invoiced 170M, paid 80M — viewed on
// 31 Aug, laid out at phone and desktop widths without overflow.
final _statement = <String, dynamic>{
  'customer': {'hospital_id': null, 'client_name': 'ABC Medical Centre Limited', 'tin': '123-456-789',
    'phone': '0712 000 111', 'email': 'accounts@abc-medical.example', 'address': 'Plot 12, Mikocheni, Dar es Salaam'},
  'period': {'from': '2026-07-01', 'to': '2026-08-31'},
  'opening_balance': 0,
  'total_invoiced': 270000000,
  'total_paid': 110000000,
  'closing_balance': 160000000,
  'balance_due': 90000000,
  'collected_pct': 40.7,
  'as_at': '2026-08-31',
  'invoice_status': [
    {'id': 1, 'invoice_number': 'INV-001', 'issue_date': '2026-07-05', 'due_date': '2026-08-04', 'total': 100000000,
      'paid': 100000000, 'credited': 0, 'remaining': 0, 'status': 'paid', 'days_overdue': 0, 'payments_count': 2,
      'last_payment_at': '2026-08-25'},
    {'id': 2, 'invoice_number': 'INV-002', 'issue_date': '2026-08-02', 'due_date': '2026-09-01', 'total': 170000000,
      'paid': 10000000, 'credited': 0, 'remaining': 160000000, 'status': 'partly_paid', 'days_overdue': 0, 'payments_count': 1,
      'last_payment_at': '2026-08-25'},
  ],
  'entries': [
    {'date': '2026-07-05', 'type': 'invoice', 'ref': 'INV-001', 'description': 'Invoice · terms 30 days', 'debit': 100000000, 'credit': 0, 'balance': 100000000},
    {'date': '2026-07-20', 'type': 'payment', 'ref': 'RCPT-001', 'description': 'Payment 1 for INV-001 · bank transfer · CRDB ref 88231', 'debit': 0, 'credit': 30000000, 'balance': 70000000},
    {'date': '2026-08-02', 'type': 'invoice', 'ref': 'INV-002', 'description': 'Invoice · terms 30 days', 'debit': 170000000, 'credit': 0, 'balance': 240000000},
    {'date': '2026-08-25', 'type': 'payment', 'ref': 'RCPT-002a', 'description': 'Payment 2 for INV-001 · cheque', 'debit': 0, 'credit': 70000000, 'balance': 170000000},
    {'date': '2026-08-25', 'type': 'payment', 'ref': 'RCPT-002b', 'description': 'Payment 1 for INV-002 · cheque', 'debit': 0, 'credit': 10000000, 'balance': 160000000},
  ],
  'open_invoices': [],
};

final _list = <String, dynamic>{
  'as_at': '2026-08-31',
  'summary': {'outstanding': 160000000, 'overdue': 0, 'customers_owing': 1, 'open_invoices': 1, 'no_payment_invoices': 0,
    'collected': 230000000, 'billed': 320000000, 'collection_rate': 71.9},
  'data': [
    {'key': 'n:abc', 'hospital_id': null, 'client_name': 'ABC Medical Centre Limited', 'tin': '123-456-789', 'phone': '0712 000 111',
      'open_invoices': 1, 'billed': 170000000, 'paid': 10000000, 'balance': 160000000, 'overdue_balance': 0,
      'aging': {'current': 160000000, 'd1_30': 0, 'd31_60': 0, 'd61_90': 0, 'd90_plus': 0},
      'oldest_due_date': '2026-09-01', 'max_days_overdue': 0, 'no_payment_invoices': 0, 'last_payment_at': '2026-08-25'},
  ],
};

void main() {
  setUpAll(() {
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      final body = o.path.endsWith('/receivables/statement') ? _statement : _list;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
    }));
  });

  for (final (label, size) in [('desktop', const Size(1440, 1600)), ('phone', const Size(390, 2600))]) {
    testWidgets('statement lays out without overflow on $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const CustomerStatementScreen(clientName: 'ABC Medical Centre Limited'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INVOICE STATUS ON 31 AUG 2026 · 2'), findsOneWidget);
      expect(find.text('OWED ON 31 AUG 2026'), findsOneWidget);
      expect(find.text('40.7% collected'), findsOneWidget);
      expect(find.text('Partly paid'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);
      expect(find.textContaining('RCPT-002b'), findsOneWidget);
      expect(find.text('Closing balance'), findsOneWidget);
    });

    testWidgets('receivables list as at a date lays out on $label', (tester) async {
      tester.view.physicalSize = Size(size.width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ReceivablesScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('As at today'), findsOneWidget);
      expect(find.text('ABC Medical Centre Limited'), findsOneWidget);
    });
  }
}
