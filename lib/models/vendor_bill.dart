// A supplier's invoice (VendorBillResource). Amounts are in the supplier's
// currency (cents allowed); totalTzs is what was posted to the books.

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

class VendorBillLineItem {
  final int    id;
  final String description;
  final double quantity;
  final double unitPrice;
  final double total;

  const VendorBillLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  factory VendorBillLineItem.fromJson(Map<String, dynamic> j) => VendorBillLineItem(
    id:          (j['id'] as num? ?? 0).toInt(),
    description: j['description'] as String? ?? '',
    quantity:    _d(j['quantity'] ?? 1),
    unitPrice:   _d(j['unit_price']),
    total:       _d(j['total']),
  );
}

/// A payment requested or made for this invoice (supplier_payments), or an
/// earlier advance it used.
class VendorBillPayment {
  final int    id;
  final String paymentNumber;
  final double amount;
  final String currency;
  final double exchangeRate;
  final String status; // pending_director | paid | rejected
  final String? paidFrom;
  final String? reference;
  final String paidAt;
  /// How much of it went to this invoice.
  final double applied;

  const VendorBillPayment({
    required this.id,
    required this.paymentNumber,
    required this.amount,
    this.currency = 'TZS',
    this.exchangeRate = 1,
    this.status = 'paid',
    this.paidFrom,
    this.reference,
    required this.paidAt,
    this.applied = 0,
  });

  factory VendorBillPayment.fromJson(Map<String, dynamic> j) => VendorBillPayment(
    id:            (j['id'] as num).toInt(),
    paymentNumber: j['payment_number'] as String? ?? '—',
    amount:        _d(j['amount']),
    currency:      j['currency'] as String? ?? 'TZS',
    exchangeRate:  _d(j['exchange_rate'] ?? 1),
    status:        j['status'] as String? ?? 'paid',
    paidFrom:      j['paid_from'] as String?,
    reference:     j['reference'] as String?,
    paidAt:        j['paid_at'] as String? ?? '',
    applied:       _d(j['applied']),
  );

  bool get isPending => status == 'pending_director';
  String get statusLabel => switch (status) {
    'pending_director' => 'Awaiting Director',
    'rejected'         => 'Rejected',
    _                  => 'Paid',
  };
}

class VendorBill {
  final int     id;
  final String  billNumber;
  /// The supplier's own invoice number.
  final String? supplierReference;
  final int     supplierId;
  final String? supplierName;
  final int?    purchaseOrderId;
  final String? purchaseOrderNumber;
  final int?    categoryId;
  final String? categoryName;
  final String  issueDate;
  final String  dueDate;
  final double  subtotal;
  final double  taxRate;
  final double  taxAmount;
  final double  total;
  final double  amountPaid;
  final double  balanceDue;
  final String  status; // pending | partial | paid | overdue | cancelled
  final String  currency;
  final double  exchangeRate;
  final int     totalTzs;
  final String? notes;
  final String? createdByName;
  final String? approvedByName;
  final String? approvedAt;
  final List<VendorBillLineItem> lineItems;
  final List<VendorBillPayment>  payments;
  final DateTime? createdAt;

  const VendorBill({
    required this.id,
    required this.billNumber,
    this.supplierReference,
    required this.supplierId,
    this.supplierName,
    this.purchaseOrderId,
    this.purchaseOrderNumber,
    this.categoryId,
    this.categoryName,
    required this.issueDate,
    required this.dueDate,
    required this.subtotal,
    this.taxRate = 0,
    required this.taxAmount,
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.status,
    this.currency = 'TZS',
    this.exchangeRate = 1,
    this.totalTzs = 0,
    this.notes,
    this.createdByName,
    this.approvedByName,
    this.approvedAt,
    this.lineItems = const [],
    this.payments  = const [],
    this.createdAt,
  });

  factory VendorBill.fromJson(Map<String, dynamic> j) => VendorBill(
    id:                  (j['id'] as num).toInt(),
    billNumber:          j['bill_number'] as String? ?? '—',
    supplierReference:   j['supplier_reference'] as String?,
    supplierId:          (j['supplier_id'] as num? ?? 0).toInt(),
    supplierName:        j['supplier_name'] as String?,
    purchaseOrderId:     j['purchase_order_id'] != null ? (j['purchase_order_id'] as num).toInt() : null,
    purchaseOrderNumber: j['purchase_order_number'] as String?,
    categoryId:          j['category_id'] != null ? (j['category_id'] as num).toInt() : null,
    categoryName:        j['category_name'] as String?,
    issueDate:           j['issue_date'] as String? ?? '—',
    dueDate:             j['due_date'] as String? ?? '—',
    subtotal:            _d(j['subtotal']),
    taxRate:             _d(j['tax_rate']),
    taxAmount:           _d(j['tax_amount']),
    total:               _d(j['total']),
    amountPaid:          _d(j['amount_paid']),
    balanceDue:          _d(j['balance_due']),
    status:              j['status'] as String? ?? 'pending',
    currency:            j['currency'] as String? ?? 'TZS',
    exchangeRate:        _d(j['exchange_rate'] ?? 1),
    totalTzs:            (j['total_tzs'] as num? ?? 0).toInt(),
    notes:               j['notes'] as String?,
    createdByName:       j['created_by_name'] as String?,
    approvedByName:      j['approved_by_name'] as String?,
    approvedAt:          j['approved_at'] as String?,
    lineItems:           (j['line_items'] as List? ?? [])
                             .map((e) => VendorBillLineItem.fromJson(e as Map<String, dynamic>)).toList(),
    payments:            (j['payments'] as List? ?? [])
                             .map((e) => VendorBillPayment.fromJson(e as Map<String, dynamic>)).toList(),
    createdAt:           j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
  );

  bool get isForeign => currency.toUpperCase() != 'TZS';
  /// For totals across suppliers: at the invoice's own rate.
  int get balanceDueTzs => (balanceDue * exchangeRate).round();
  int get amountPaidTzs => (amountPaid * exchangeRate).round();
  int get totalTzsOrRate => totalTzs > 0 ? totalTzs : (total * exchangeRate).round();
  String get displayNumber => supplierReference ?? billNumber;
  bool get hasPendingPayment => payments.any((p) => p.isPending);

  String get statusLabel => switch (status) {
    'approved'  => 'Approved',
    'partial'   => 'Partly paid',
    'paid'      => 'Paid',
    'overdue'   => 'Overdue',
    'cancelled' => 'Cancelled',
    _           => 'Unpaid',
  };

  bool get isPaid      => status == 'paid';
  // Payments are approved by the Director per payment (initiate → final),
  // so an invoice no longer needs its own approval before paying.
  bool get canApprove => false;
  bool get canPay      => status != 'paid' && status != 'cancelled' && balanceDue > 0.004;
  bool get canCancel   => !isPaid && status != 'cancelled' && amountPaid <= 0.004;
}
