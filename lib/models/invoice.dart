import '../widgets/sales/terms_editor.dart' show TermItem, termItemsFromJson;

enum PaymentStatus { pending, partial, paid, overdue, waived, cancelled, sent }

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
    PaymentStatus.pending   => 'Pending',
    PaymentStatus.partial   => 'Partial',
    PaymentStatus.paid      => 'Paid',
    PaymentStatus.overdue   => 'Overdue',
    PaymentStatus.waived    => 'Waived',
    PaymentStatus.cancelled => 'Cancelled',
    PaymentStatus.sent      => 'Sent',
  };
}

PaymentStatus _parseStatus(String s) => switch (s) {
  'partial'   => PaymentStatus.partial,
  'paid'      => PaymentStatus.paid,
  'overdue'   => PaymentStatus.overdue,
  'waived'    => PaymentStatus.waived,
  'cancelled' => PaymentStatus.cancelled,
  'sent'      => PaymentStatus.sent,
  _           => PaymentStatus.pending,
};

class Payment {
  final int     id;
  final String  paymentNumber;
  final int     invoiceId;
  final int     amount;
  final String  paymentMethod;
  final String? reference;
  final String  paidAt;
  final String? notes;
  final String? recordedBy;

  const Payment({
    required this.id,
    required this.paymentNumber,
    required this.invoiceId,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    required this.paidAt,
    this.notes,
    this.recordedBy,
  });

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id:            (j['id'] as num).toInt(),
    paymentNumber: j['payment_number'] as String? ?? '—',
    invoiceId:     (j['invoice_id'] as num? ?? 0).toInt(),
    amount:        (j['amount'] as num? ?? 0).toInt(),
    paymentMethod: j['payment_method'] as String? ?? 'cash',
    reference:     j['reference'] as String?,
    paidAt:        j['paid_at'] as String? ?? '',
    notes:         j['notes'] as String?,
    recordedBy:    j['recorded_by'] as String?,
  );

  String get methodLabel => switch (paymentMethod) {
    'bank_transfer' => 'Bank Transfer',
    'mobile_money'  => 'Mobile Money',
    'cheque'        => 'Cheque',
    _               => 'Cash',
  };
}

class InvoiceLineItem {
  final int?   inventoryItemId;
  final String description;
  final double quantity;
  // Unit of measure, lot number and expiry date (yyyy-mm-dd), as on the
  // invoice PDF's UOM / LOT / EXP. columns.
  final String? unitOfMeasure;
  final String? lotNumber;
  final String? expiryDate;
  final int    unitPrice;
  // TSh off this line; total is already after it.
  final int    discount;
  final int    total;

  const InvoiceLineItem({
    this.inventoryItemId,
    required this.description,
    required this.quantity,
    this.unitOfMeasure,
    this.lotNumber,
    this.expiryDate,
    required this.unitPrice,
    this.discount = 0,
    required this.total,
  });

  factory InvoiceLineItem.fromJson(Map<String, dynamic> j) => InvoiceLineItem(
    inventoryItemId: (j['inventory_item_id'] as num?)?.toInt(),
    unitOfMeasure: j['unit_of_measure'] as String?,
    lotNumber:   j['lot_number'] as String?,
    expiryDate:  j['expiry_date'] as String?,
    description: j['description'] as String? ?? '',
    quantity:    (j['quantity']   as num? ?? 1).toDouble(),
    unitPrice:   (j['unit_price'] as num? ?? 0).toInt(),
    discount:    (j['discount']   as num? ?? 0).toInt(),
    total:       (j['total']      as num? ?? 0).toInt(),
  );
}

class Invoice {
  final int           id;
  final String        invoiceNumber;
  // Hospital invoices
  final int?          hospitalId;
  final String?       hospitalName;
  // Sales-linked invoices
  final int?          salesOrderId;
  final String?       salesOrderNumber;
  final String?       clientName;
  final String?       clientContact;
  final String?       clientEmail;
  final String?       clientTin;
  // Dates
  final String        issueDate;
  final String        dueDate;
  // Payment term, e.g. 30 days / 4 months (null for invoices with a hand-picked due date).
  final int?          payTermNumber;
  final String?       payTermType;
  // Financials
  final int           subtotal;
  final double        taxRate;
  final int           taxAmount;
  final int           shippingCharges;
  final int           total;
  final int           amountPaid;
  final PaymentStatus status;
  final String        currency;
  final String?       notes;
  // Relations
  final List<InvoiceLineItem> lineItems;
  final List<Payment>         payments;
  // Server-computed, accounts for applied credit notes on top of payments —
  // prefer this over the local total-minus-paid math below when present.
  final int?          balanceDueOverride;
  // Clickhuduma sale record ("All sales")
  final String        saleStatus;      // final | draft | proforma
  final String        chPaymentStatus; // paid | due | partial | overdue | cancelled | waived | draft | proforma
  final String?       contactPhone;
  final int?          createdBy;
  final String?       addedBy;
  final String?       staffNote;
  /// TERMS & CONDITIONS this sale changed; null = company defaults.
  final List<TermItem>? termItems;
  final double?       totalItems;
  final List<String>  paymentMethods;
  final int           credited;
  final String?       shippingStatus;
  final String?       shippingAddress;
  final String?       shippingDetails;
  final String?       deliveredTo;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    this.hospitalId,
    this.hospitalName,
    this.salesOrderId,
    this.salesOrderNumber,
    this.clientName,
    this.clientContact,
    this.clientEmail,
    this.clientTin,
    required this.issueDate,
    required this.dueDate,
    this.payTermNumber,
    this.payTermType,
    required this.subtotal,
    this.taxRate = 0,
    required this.taxAmount,
    this.shippingCharges = 0,
    required this.total,
    required this.amountPaid,
    required this.status,
    this.currency = 'TZS',
    this.notes,
    this.lineItems = const [],
    this.payments  = const [],
    this.balanceDueOverride,
    this.saleStatus = 'final',
    this.chPaymentStatus = 'due',
    this.contactPhone,
    this.createdBy,
    this.addedBy,
    this.staffNote,
    this.termItems,
    this.totalItems,
    this.paymentMethods = const [],
    this.credited = 0,
    this.shippingStatus,
    this.shippingAddress,
    this.shippingDetails,
    this.deliveredTo,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id:              (j['id'] as num).toInt(),
    invoiceNumber:   j['invoice_number'] as String? ?? '—',
    hospitalId:      j['hospital_id'] != null ? (j['hospital_id'] as num).toInt() : null,
    hospitalName:    j['hospital'] is Map
                         ? (j['hospital'] as Map)['name'] as String?
                         : j['hospital_name'] as String?,
    salesOrderId:    j['sales_order_id'] != null ? (j['sales_order_id'] as num).toInt() : null,
    salesOrderNumber:j['sales_order_number'] as String?,
    clientName:      j['client_name'] as String?,
    clientContact:   j['client_contact'] as String?,
    clientEmail:     j['client_email'] as String?,
    clientTin:       j['client_tin'] as String?,
    issueDate:       j['issue_date'] as String? ?? j['created_at'] as String? ?? '—',
    dueDate:         j['due_date']   as String? ?? '—',
    payTermNumber:   (j['pay_term_number'] as num?)?.toInt(),
    payTermType:     j['pay_term_type'] as String?,
    shippingCharges: (j['shipping_charges'] as num? ?? 0).toInt(),
    subtotal:        (j['subtotal']    as num? ?? 0).toInt(),
    taxRate:         (j['tax_rate']    as num? ?? 0).toDouble(),
    taxAmount:       (j['tax_amount']  as num? ?? 0).toInt(),
    total:           (j['total']       as num? ?? 0).toInt(),
    amountPaid:      (j['amount_paid'] as num? ?? 0).toInt(),
    status:          _parseStatus(j['status'] as String? ?? 'pending'),
    currency:        j['currency']     as String? ?? 'TZS',
    notes:           j['notes']        as String?,
    lineItems:       (j['line_items']  as List? ?? [])
                         .map((e) => InvoiceLineItem.fromJson(e as Map<String, dynamic>)).toList(),
    payments:        (j['payments']    as List? ?? [])
                         .map((e) => Payment.fromJson(e as Map<String, dynamic>)).toList(),
    balanceDueOverride: (j['balance_due'] as num?)?.toInt(),
    saleStatus:      j['sale_status'] as String? ?? 'final',
    chPaymentStatus: j['payment_status'] as String? ?? 'due',
    contactPhone:    j['contact_phone'] as String?,
    createdBy:       (j['created_by'] as num?)?.toInt(),
    addedBy:         j['added_by'] as String?,
    staffNote:       j['staff_note'] as String?,
    termItems:       termItemsFromJson(j['term_items']),
    totalItems:      (j['total_items'] as num?)?.toDouble(),
    paymentMethods:  (j['payment_methods'] as List? ?? []).map((e) => e.toString()).toList(),
    credited:        (j['credited'] as num? ?? 0).toInt(),
    shippingStatus:  j['shipping_status'] as String?,
    shippingAddress: j['shipping_address'] as String?,
    shippingDetails: j['shipping_details'] as String?,
    deliveredTo:     j['delivered_to'] as String?,
  );

  bool get isFinal => saleStatus == 'final';

  static String methodLabelOf(String m) => switch (m) {
    'bank_transfer' => 'Bank Transfer',
    'mobile_money'  => 'Mobile Money',
    'cheque'        => 'Cheque',
    _               => 'Cash',
  };

  int    get balanceDue  => balanceDueOverride ?? (total - amountPaid).clamp(0, total);
  String get displayName => clientName ?? hospitalName ?? '—';
  bool get isPaid        => status == PaymentStatus.paid || status == PaymentStatus.waived;
  bool get canSend       => isFinal && status == PaymentStatus.pending;
  bool get canPay        => isFinal && !isPaid && status != PaymentStatus.cancelled;
  bool get canCancel     => isFinal && !isPaid;

  // The backend never actually stores PaymentStatus.overdue on a row — it's
  // a point-in-time fact ("still unpaid past its due date"), not a workflow
  // stage a controller transitions through, so it's computed here the same
  // way FinanceReportController@arAging computes it server-side: unpaid
  // balance + due_date in the past, not cancelled/waived.
  bool get isOverdue => balanceDue > 0
      && status != PaymentStatus.cancelled
      && status != PaymentStatus.waived
      && (DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) ?? false);

  // Single source of truth for both the status badge on a row and the
  // filter chip counts, so "Overdue" means the same thing in both places.
  PaymentStatus get effectiveStatus => isOverdue ? PaymentStatus.overdue : status;
}
