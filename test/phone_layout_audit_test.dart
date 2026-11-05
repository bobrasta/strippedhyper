import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/trial_service.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/common/app_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every menu screen, opened at phone size (390×844) with empty data, must
/// lay out without overflowing — guards the phone layouts against a desktop
/// header row or table quietly coming back.
const _screens = [
  'dashboard', 'inventory_items', 'inventory_suppliers',
  'inventory_movements', 'inventory_requisitions', 'inventory_orders', 'inventory_locations',
  'revenue', 'finance_dashboard', 'finance_expenses', 'finance_bills', 'finance_creditors',
  'finance_ledger', 'finance_reports', 'finance_bank_rec', 'finance_receivables', 'vendor_fees',
  'tmda_permits', 'clearing_fees', 'shipment_settings', 'shipments', 'tenders', 'tender_devices', 'nest_tenders',
  'email', 'purchases_list', 'purchases_new', 'purchases_returns', 'sales_leads', 'sales_dashboard', 'sales_quotations', 'sales_orders', 'sales_invoices',
  'sales_history', 'sales_new', 'sales_team', 'team_performance', 'my_performance', 'customers',
  'staff', 'my_leave', 'my_expenses', 'my_travel_plans', 'hr_approvals', 'hr_settings',
  'hr_directory', 'hr_recruitment', 'hr_leave_calendar', 'hr_attendance', 'hr_payroll',
  'hr_reports', 'approvals', 'notifications', 'reports', 'settings', 'delegations',
  'notification_templates', 'activity_log', 'downloads', 'meetings', 'letters', 'quotations', 'contributions',
];

void main() {
  setUpAll(() {
    try {
      trialNotifier = ValueNotifier(const TrialStatus(state: TrialState.valid));
    } catch (_) {/* already set by another test in this isolate */}
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200,
          data: {'data': <dynamic>[], 'meta': {'current_page': 1, 'last_page': 1, 'total': 0}}));
    }));
  });

  for (final key in _screens) {
    testWidgets('$key fits a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      userRoleNotifier.value = 'admin';
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (e) {
        final msg = e.exceptionAsString();
        if (msg.contains('overflowed')) {
          final at = RegExp(r'lib/[A-Za-z0-9_/]+\.dart:\d+').firstMatch(e.toString())?.group(0) ?? '';
          overflows.add('${msg.split('\n').first} $at');
        }
      };
      await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark),
          home: AppShell(initialScreenKey: key)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      FlutterError.onError = previous;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(overflows, isEmpty);
    });
  }

  // The "new …" forms, opened from their screen's button on a phone: they
  // must open as a bottom sheet without any layout error.
  const forms = [
    ('inventory_items', 'Add'), ('inventory_movements', 'Record'),
    ('inventory_requisitions', 'New'), ('inventory_locations', 'Add Location'),
    ('finance_expenses', 'New expense'), ('finance_bills', 'New invoice'), ('finance_ledger', 'New'),
    ('my_leave', 'Request Leave'), ('my_leave', 'Running Late'), ('my_travel_plans', 'New travel plan'),
    ('sales_leads', 'New'), ('vendor_fees', 'Record fee'), ('my_expenses', 'New expense'),
    ('purchases_list', 'Add'), ('purchases_returns', 'Add'),
  ];
  for (final (key, button) in forms) {
    testWidgets('$key › $button opens on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      userRoleNotifier.value = 'admin';
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (e) {
        final at = RegExp(r'lib/[A-Za-z0-9_/]+\.dart:\d+').firstMatch(e.toString())?.group(0) ?? '';
        errors.add('${e.exceptionAsString().split('\n').first} $at');
      };
      var found = false;
      try {
        await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark),
            home: AppShell(initialScreenKey: key)));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        final target = find.text(button);
        found = target.evaluate().isNotEmpty;
        if (found) {
          await tester.tap(target.first, warnIfMissed: false);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      } finally {
        FlutterError.onError = previous;
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(found, isTrue, reason: 'no "$button" button on $key');
      expect(errors, isEmpty);
    });
  }
}
