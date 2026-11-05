import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/chart_of_account.dart';
import '../models/contact.dart';
import '../models/permission.dart';
import '../models/inventory_item.dart';
import '../models/task_item.dart';

class CsvExport {
  CsvExport._();

  /// file_picker has no Android implementation in this build (its legacy
  /// Kotlin Gradle Plugin declaration is incompatible with AGP 9's built-in
  /// Kotlin, and no fixed release exists upstream yet) — CSV export/import
  /// remains fully available on Windows/desktop.
  static void _checkSupported() {
    if (Platform.isAndroid) {
      throw Exception('CSV export isn\'t available on Android in this build — use the desktop app instead.');
    }
  }

  static Future<String?> inventoryItems(List<InventoryItem> items) async {
    _checkSupported();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export Inventory',
      fileName: 'inventory_${_today()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return null;

    final buf = StringBuffer();
    buf.writeln(_row(['SKU', 'Name', 'Category', 'Manufacturer', 'Unit',
        'Stock Qty', 'Reorder Level', 'Unit Cost', 'Currency', 'CE', 'FDA', 'TBS']));
    for (final p in items) {
      buf.writeln(_row([
        p.sku, p.name, p.category, p.manufacturer ?? '',
        p.unitOfMeasure, p.stockQty.toString(), p.reorderLevel.toString(),
        p.unitCost.toStringAsFixed(0), p.currency,
        p.hasCe ? 'Yes' : 'No', p.hasFda ? 'Yes' : 'No', p.hasTbs ? 'Yes' : 'No',
      ]));
    }
    await File(path).writeAsString(buf.toString(), flush: true);
    return path;
  }

  static Future<String?> contacts(List<Contact> items) async {
    _checkSupported();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export Contacts',
      fileName: 'contacts_${_today()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return null;

    final buf = StringBuffer();
    buf.writeln(_row(['First Name', 'Last Name', 'Job Title', 'Department',
        'Client', 'Phone', 'Email', 'WhatsApp', 'Tags',
        'Last Contacted', 'Next Follow-up']));
    for (final c in items) {
      buf.writeln(_row([
        c.firstName, c.lastName, c.jobTitle ?? '', c.department ?? '',
        c.hospitalName, c.phone ?? '', c.email ?? '', c.whatsapp ?? '',
        c.tags.join('; '), c.lastContactedAt ?? '', c.nextFollowupAt ?? '',
      ]));
    }
    await File(path).writeAsString(buf.toString(), flush: true);
    return path;
  }

  static Future<String?> tasks(List<TaskItem> items, {String? staffName}) async {
    _checkSupported();
    final label = staffName != null ? staffName.replaceAll(' ', '_') : 'all';
    final path  = await FilePicker.saveFile(
      dialogTitle: 'Export Task Report',
      fileName: 'tasks_${label}_${_today()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return null;

    final buf = StringBuffer();
    buf.writeln(_row(['Title', 'Category', 'Task Type', 'Priority', 'Status',
        'Assigned To', 'Due Date', 'Started At', 'Completed At', 'Created At', 'Description']));
    for (final t in items) {
      buf.writeln(_row([
        t.title, t.category, t.taskType, t.priority, t.status,
        t.assigneeName ?? '', t.dueDate ?? '', t.startedAt ?? '',
        t.completedAt ?? '', t.createdAt, t.description ?? '',
      ]));
    }
    await File(path).writeAsString(buf.toString(), flush: true);
    return path;
  }

  static Future<String?> financeSummary({
    required String periodLabel,
    required int revenue,
    required int totalExpenses,
    required int netProfit,
    required int netCashFlow,
    required int totalOutstanding,
    required int totalAssets,
    required int totalLiabilities,
    required int totalEquity,
    required List<Map<String, dynamic>> expensesByCategory,
    required List<LedgerEntry> recentActivity,
  }) async {
    _checkSupported();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export Finance Report',
      fileName: 'finance_overview_${_today()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return null;

    final buf = StringBuffer();
    buf.writeln(_row(['Finance Overview', periodLabel]));
    buf.writeln();
    buf.writeln(_row(['Metric', 'Value (TZS)']));
    buf.writeln(_row(['Revenue', revenue.toString()]));
    buf.writeln(_row(['Total Expenses', totalExpenses.toString()]));
    buf.writeln(_row(['Net Profit', netProfit.toString()]));
    buf.writeln(_row(['Net Cash Flow', netCashFlow.toString()]));
    buf.writeln(_row(['AR Outstanding', totalOutstanding.toString()]));
    buf.writeln(_row(['Total Assets', totalAssets.toString()]));
    buf.writeln(_row(['Total Liabilities', totalLiabilities.toString()]));
    buf.writeln(_row(['Total Equity', totalEquity.toString()]));
    buf.writeln();
    buf.writeln(_row(['Expense Category', 'Total (TZS)']));
    for (final e in expensesByCategory) {
      buf.writeln(_row(['${e['category']}', '${e['total']}']));
    }
    buf.writeln();
    buf.writeln(_row(['Recent Ledger Activity']));
    buf.writeln(_row(['Date', 'Account', 'Type', 'Amount (TZS)', 'Description']));
    for (final a in recentActivity) {
      buf.writeln(_row([
        a.createdAt?.toIso8601String().substring(0, 10) ?? '',
        a.accountName, a.type, a.amount.toString(), a.description ?? '',
      ]));
    }
    await File(path).writeAsString(buf.toString(), flush: true);
    return path;
  }

  static Future<String?> permissionAuditLog(List<UserPermissionOverride> entries) async {
    _checkSupported();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export Permission Audit Log',
      fileName: 'permission_audit_${_today()}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return null;

    final buf = StringBuffer();
    buf.writeln(_row(['Member', 'Permission', 'Effect', 'Scope', 'Reason', 'Granted By', 'Date']));
    for (final e in entries) {
      buf.writeln(_row([
        e.userName ?? '', e.label, e.effect, e.scope ?? '',
        e.reason ?? '', e.createdByName ?? '', e.createdAt ?? '',
      ]));
    }
    await File(path).writeAsString(buf.toString(), flush: true);
    return path;
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);
  static String _q(String s) => '"${s.replaceAll('"', '""')}"';
  static String _row(List<String> cells) => cells.map(_q).join(',');
}
