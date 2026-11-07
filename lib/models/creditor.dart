// Creditors Ledger (CreditorController), payments to creditors
// (SupplierPaymentController) and the web of connected records
// (ConnectionsController). Amounts are in the creditor's currency unless
// the name ends in Tzs.

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int _i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
List<Map<String, dynamic>> _maps(dynamic v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

/// "USD 1,420.00" / "TSh 3,738,000".
String money(num v, String currency) {
  final tzs = currency.toUpperCase() == 'TZS';
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(tzs ? 0 : 2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final s = '${tzs ? 'TSh' : currency.toUpperCase()} $whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  return neg ? '−$s' : s;
}

class CreditorRow {
  CreditorRow(this.raw);
  final Map<String, dynamic> raw;
  String get type => raw['type'] as String;
  int get id => _i(raw['id']);
  String get name => raw['name'] as String? ?? '';
  String get kind => raw['kind'] as String? ?? '';
  String get category => raw['category'] as String? ?? 'local';
  bool get isInternational => category == 'international';
  String get currency => raw['currency'] as String? ?? 'TZS';
  String? get country => raw['country'] as String?;
  String? get contactPerson => raw['contact_person'] as String?;
  String? get phone => raw['phone'] as String?;
  String? get email => raw['email'] as String?;
  double get balance => _d(raw['balance']);
  int get balanceTzs => _i(raw['balance_tzs']);
  int get bookBalanceTzs => _i(raw['book_balance_tzs']);
  double get totalCredit => _d(raw['total_credit']);
  double get totalDebit => _d(raw['total_debit']);
  DateTime? get lastActivity => _date(raw['last_activity']);
  int get lines => _i(raw['lines']);
  int get pendingPayments => _i(raw['pending_payments']);
  double get pendingAmount => _d(raw['pending_amount']);
}

class CreditorList {
  CreditorList(this.raw);
  final Map<String, dynamic> raw;
  List<CreditorRow> get creditors => [for (final c in _maps(raw['creditors'])) CreditorRow(c)];
  int get internationalTzs => _i((raw['totals'] as Map?)?['international_tzs']);
  int get localTzs => _i((raw['totals'] as Map?)?['local_tzs']);
  int get pendingPayments => _i((raw['totals'] as Map?)?['pending_payments']);
  bool get canManage => raw['can_manage'] == true;

  /// Trade Creditors in the books vs. the ledgers, per category.
  Map<String, ({String account, int books, int ledgers, int difference})> get reconciliation => {
    for (final e in ((raw['reconciliation'] as Map?) ?? const {}).entries)
      e.key as String: (
        account: (e.value as Map)['account'] as String,
        books: _i((e.value as Map)['books']),
        ledgers: _i((e.value as Map)['ledgers']),
        difference: _i((e.value as Map)['difference']),
      ),
  };
}

class LedgerLine {
  LedgerLine(this.raw);
  final Map<String, dynamic> raw;
  DateTime? get date => _date(raw['date']);
  String get narration => raw['narration'] as String? ?? '';
  String? get ref => raw['ref'] as String?;
  double get rate => _d(raw['rate']);
  double get debit => _d(raw['debit']);
  double get credit => _d(raw['credit']);
  int get debitTzs => _i(raw['debit_tzs']);
  int get creditTzs => _i(raw['credit_tzs']);
  double get balance => _d(raw['balance']);
  int get balanceTzs => _i(raw['balance_tzs']);
  String get sourceType => (raw['source'] as Map?)?['type'] as String? ?? '';
  int get sourceId => _i((raw['source'] as Map?)?['id']);
}

class CreditorStatement {
  CreditorStatement(this.raw);
  final Map<String, dynamic> raw;
  CreditorRow get creditor => CreditorRow(Map<String, dynamic>.from(raw['creditor'] as Map));
  DateTime? get from => _date((raw['period'] as Map?)?['from']);
  DateTime? get to => _date((raw['period'] as Map?)?['to']);
  double get openingBalance => _d(raw['opening_balance']);
  int get openingBalanceTzs => _i(raw['opening_balance_tzs']);
  List<LedgerLine> get entries => [for (final e in _maps(raw['entries'])) LedgerLine(e)];
  double get totalCredit => _d(raw['total_credit']);
  double get totalDebit => _d(raw['total_debit']);
  double get closingBalance => _d(raw['closing_balance']);
  int get closingBalanceTzs => _i(raw['closing_balance_tzs']);
  int get bookBalanceTzs => _i(raw['book_balance_tzs']);
  Map<String, dynamic>? get opening => raw['opening'] == null ? null : Map<String, dynamic>.from(raw['opening'] as Map);
}

class PaymentAccount {
  const PaymentAccount({required this.id, required this.code, required this.name});
  final int id;
  final String code;
  final String name;
  factory PaymentAccount.fromJson(Map<String, dynamic> j) =>
      PaymentAccount(id: _i(j['id']), code: j['code'] as String? ?? '', name: j['name'] as String? ?? '');
  String get label => '$code · $name';
}

class SupplierPayment {
  SupplierPayment(this.raw);
  final Map<String, dynamic> raw;
  int get id => _i(raw['id']);
  String get number => raw['payment_number'] as String? ?? '';
  String get creditorType => raw['creditor_type'] as String? ?? 'supplier';
  int get creditorId => _i(raw['creditor_id']);
  String get creditorName => raw['creditor_name'] as String? ?? '';
  String? get poNumber => (raw['purchase_order'] as Map?)?['po_number'] as String?;
  int? get purchaseOrderId => (raw['purchase_order'] as Map?) == null ? null : _i((raw['purchase_order'] as Map)['id']);
  String? get billRef {
    final b = raw['vendor_bill'] as Map?;
    return b == null ? null : (b['supplier_reference'] as String? ?? b['bill_number'] as String?);
  }
  String get currency => raw['currency'] as String? ?? 'TZS';
  double get amount => _d(raw['amount']);
  double get rate => _d(raw['exchange_rate']);
  int get amountTzs => _i(raw['amount_tzs']);
  String? get paidFrom => (raw['paid_from'] as Map?)?['name'] as String?;
  DateTime? get paymentDate => _date(raw['payment_date']);
  String? get reference => raw['reference'] as String?;
  String? get notes => raw['notes'] as String?;
  String get status => raw['status'] as String? ?? 'pending_director';
  bool get isPending => status == 'pending_director';
  int get fxDifferenceTzs => _i(raw['fx_difference_tzs']);
  double? get advance => raw['advance'] == null ? null : _d(raw['advance']);
  List<Map<String, dynamic>> get settled => _maps(raw['settled']);
  String? get initiatedBy => raw['initiated_by'] as String?;
  DateTime? get initiatedAt => _date(raw['initiated_at']);
  String? get approvedBy => raw['approved_by'] as String?;
  String? get rejectedBy => raw['rejected_by'] as String?;
  String? get rejectionReason => raw['rejection_reason'] as String?;
}

// ── Connections ─────────────────────────────────────────────────────────────

class ConnNode {
  ConnNode(this.raw);
  final Map<String, dynamic> raw;
  String get key => raw['key'] as String;
  String get type => raw['type'] as String;
  int get id => _i(raw['id']);
  int get depth => _i(raw['depth']);
  String get title => raw['title'] as String? ?? '';
  String? get subtitle => raw['subtitle'] as String?;
  String? get status => raw['status'] as String?;
  double? get amount => raw['amount'] == null ? null : _d(raw['amount']);
  String? get currency => raw['currency'] as String?;
  DateTime? get date => _date(raw['date']);
}

class ConnEvent {
  ConnEvent(this.raw);
  final Map<String, dynamic> raw;
  DateTime? get at => _date(raw['at']);
  String get node => raw['node'] as String;
  String get title => raw['title'] as String? ?? '';
  String get action => raw['action'] as String? ?? '';
  String? get actor => raw['actor'] as String?;
  String? get role => raw['role'] as String?;
  String? get detail => raw['detail'] as String?;
}

class ConnLeg {
  ConnLeg(this.raw);
  final Map<String, dynamic> raw;
  String get reference => raw['reference'] as String? ?? '';
  DateTime? get date => _date(raw['date']);
  String get account => raw['account'] as String? ?? '';
  bool get isDebit => raw['type'] == 'debit';
  int get amount => _i(raw['amount']);
  String? get description => raw['description'] as String?;
}

class Connections {
  Connections(this.raw);
  final Map<String, dynamic> raw;
  ConnNode get subject => ConnNode(Map<String, dynamic>.from(raw['subject'] as Map));
  List<ConnNode> get nodes => [for (final n in _maps(raw['nodes'])) ConnNode(n)];
  /// relation per node key, from the edge that first reached it.
  Map<String, String> get relations {
    final out = <String, String>{};
    for (final e in _maps(raw['edges'])) {
      out.putIfAbsent(e['to'] as String, () => e['relation'] as String? ?? '');
    }
    return out;
  }
  List<ConnEvent> get timeline => [for (final e in _maps(raw['timeline'])) ConnEvent(e)];
  /// Null when the viewer has no finance access.
  List<ConnLeg>? get ledger => raw['ledger'] == null ? null : [for (final l in _maps(raw['ledger'])) ConnLeg(l)];
  bool get truncated => raw['truncated'] == true;
}

/// Plain names for node types.
String connectionTypeLabel(String type) => switch (type) {
  'purchase_requisition' => 'Requisition',
  'purchase_order' => 'LPO',
  'supplier_payment' => 'Payment',
  'vendor_bill' => 'Supplier invoice',
  'supplier' => 'Supplier',
  'vendor' => 'Vendor',
  'vendor_fee' => 'Vendor fee',
  'shipment' => 'Shipment',
  'tender' => 'Tender',
  'inventory_item' => 'Stock item',
  'serial_number' => 'Serial',
  'stock_movement' => 'Stock movement',
  'location' => 'Store',
  'sales_order' => 'Sales order',
  'invoice' => 'Customer invoice',
  'payment' => 'Customer payment',
  'hospital' => 'Client',
  'delivery_job' => 'Delivery',
  'expense' => 'Expense',
  'per_diem_request' => 'Per diem',
  'creditor_opening' => 'Opening balance',
  _ => type,
};
