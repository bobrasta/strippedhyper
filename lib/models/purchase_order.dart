class PurchaseOrderItem {
  final int    id;
  final int    inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final int    quantityOrdered;
  final int    quantityReceived;
  /// Units already sent back to the supplier (purchase returns).
  final int    quantityReturned;
  final double unitCost;
  final String currency;
  final double totalCost;
  final String? batchNumber;
  final String? expiryDate;
  final String? notes;

  const PurchaseOrderItem({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.quantityOrdered,
    this.quantityReceived = 0,
    this.quantityReturned = 0,
    required this.unitCost,
    this.currency = 'USD',
    required this.totalCost,
    this.batchNumber,
    this.expiryDate,
    this.notes,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> j) {
    final item = j['inventory_item'] as Map<String, dynamic>?;
    return PurchaseOrderItem(
      id:               (j['id'] as num).toInt(),
      inventoryItemId:  (j['inventory_item_id'] as num).toInt(),
      itemName:         item?['name'] as String?,
      itemSku:          item?['sku']  as String?,
      quantityOrdered:  (j['quantity_ordered']  as num? ?? 0).toInt(),
      quantityReceived: (j['quantity_received'] as num? ?? 0).toInt(),
      quantityReturned: num.tryParse('${j['quantity_returned'] ?? 0}')?.toInt() ?? 0,
      unitCost:         (j['unit_cost']         as num? ?? 0).toDouble(),
      currency:         j['currency']           as String? ?? 'USD',
      totalCost:        (j['total_cost']        as num? ?? 0).toDouble(),
      batchNumber:      j['batch_number']        as String?,
      expiryDate:       j['expiry_date']         as String?,
      notes:            j['notes']               as String?,
    );
  }

  bool get isFullyReceived => quantityReceived >= quantityOrdered;
  int get returnable => quantityReceived - quantityReturned;
}

class PurchaseOrder {
  final int    id;
  final String poNumber;
  final int?   supplierId;
  final String? supplierName;
  final int?   locationId;
  final String? locationName;
  // draft | pending_sales_manager | pending_director_review |
  // pending_payment_initiation | pending_director_final | approved |
  // rejected | sent | acknowledged | partially_received | received | cancelled
  final String status;
  final String? orderedByName;
  final DateTime? expectedDeliveryDate;
  final DateTime? actualDeliveryDate;
  final DateTime? sentAt;
  final String currency;
  final double totalAmount;
  final String? shippingAddress;
  final String? terms;
  final String? notes;
  final DateTime createdAt;
  final List<PurchaseOrderItem> items;

  final String? salesApprovedByName;
  final DateTime? salesApprovedAt;
  final String? directorReviewedByName;
  final DateTime? directorReviewedAt;
  final String? paymentInitiatedByName;
  final DateTime? paymentInitiatedAt;
  final String? directorApprovedByName;
  final DateTime? directorApprovedAt;
  final String? rejectedByName;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  /// Approved on credit: the supplier is paid later against their invoice.
  final bool onCredit;
  final double amountPaid;
  final String paymentStatus; // unpaid | partial | paid
  /// Value of goods sent back to the supplier (list rows only).
  final double returnedAmount;
  /// Payments to the supplier for this order (supplier_payments rows).
  final List<Map<String, dynamic>> payments;
  /// Supplier invoices (vendor_bills rows) entered against this order.
  final List<Map<String, dynamic>> invoices;

  Map<String, dynamic>? get pendingPayment {
    for (final p in payments) {
      if (p['status'] == 'pending_director') return p;
    }
    return null;
  }

  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    this.supplierId,
    this.supplierName,
    this.locationId,
    this.locationName,
    required this.status,
    this.orderedByName,
    this.expectedDeliveryDate,
    this.actualDeliveryDate,
    this.sentAt,
    this.currency = 'USD',
    required this.totalAmount,
    this.shippingAddress,
    this.terms,
    this.notes,
    required this.createdAt,
    this.items = const [],
    this.salesApprovedByName,
    this.salesApprovedAt,
    this.directorReviewedByName,
    this.directorReviewedAt,
    this.paymentInitiatedByName,
    this.paymentInitiatedAt,
    this.directorApprovedByName,
    this.directorApprovedAt,
    this.rejectedByName,
    this.rejectedAt,
    this.rejectionReason,
    this.onCredit = false,
    this.amountPaid = 0,
    this.paymentStatus = 'unpaid',
    this.payments = const [],
    this.invoices = const [],
    this.returnedAmount = 0,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) {
    final supplier            = j['supplier']              as Map<String, dynamic>?;
    final orderedBy           = j['ordered_by']             as Map<String, dynamic>?;
    final salesApprovedBy     = j['sales_approved_by']      as Map<String, dynamic>?;
    final directorReviewedBy  = j['director_reviewed_by']   as Map<String, dynamic>?;
    final paymentInitiatedBy  = j['payment_initiated_by']   as Map<String, dynamic>?;
    final directorApprovedBy  = j['director_approved_by']   as Map<String, dynamic>?;
    final rejectedBy          = j['rejected_by']            as Map<String, dynamic>?;

    DateTime? parseDt(String? key) => j[key] != null ? DateTime.tryParse(j[key] as String) : null;

    return PurchaseOrder(
      id:                   (j['id'] as num).toInt(),
      poNumber:             j['po_number']       as String? ?? '—',
      supplierId:           j['supplier_id'] != null ? (j['supplier_id'] as num).toInt() : null,
      supplierName:         supplier?['name']    as String?,
      locationId:           (j['location_id'] as num?)?.toInt() ?? ((j['location'] as Map?)?['id'] as num?)?.toInt(),
      locationName:         (j['location'] as Map?)?['name'] as String?,
      status:               j['status']          as String? ?? 'draft',
      orderedByName:        orderedBy?['name']   as String?,
      expectedDeliveryDate: j['expected_delivery_date'] != null
          ? DateTime.tryParse(j['expected_delivery_date'] as String) : null,
      actualDeliveryDate:   j['actual_delivery_date'] != null
          ? DateTime.tryParse(j['actual_delivery_date'] as String) : null,
      sentAt:               j['sent_at'] != null
          ? DateTime.tryParse(j['sent_at'] as String) : null,
      currency:             j['currency']        as String? ?? 'USD',
      totalAmount:          (j['total_amount']   as num? ?? 0).toDouble(),
      shippingAddress:      j['shipping_address'] as String?,
      terms:                j['terms']            as String?,
      notes:                j['notes']            as String?,
      createdAt:            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      items:                (j['items'] as List? ?? [])
          .map((i) => PurchaseOrderItem.fromJson(i as Map<String, dynamic>)).toList(),
      salesApprovedByName:    salesApprovedBy?['name'] as String?,
      salesApprovedAt:        parseDt('sales_approved_at'),
      directorReviewedByName: directorReviewedBy?['name'] as String?,
      directorReviewedAt:     parseDt('director_reviewed_at'),
      paymentInitiatedByName: paymentInitiatedBy?['name'] as String?,
      paymentInitiatedAt:     parseDt('payment_initiated_at'),
      directorApprovedByName: directorApprovedBy?['name'] as String?,
      directorApprovedAt:     parseDt('director_approved_at'),
      rejectedByName:         rejectedBy?['name'] as String?,
      rejectedAt:             parseDt('rejected_at'),
      rejectionReason:        j['rejection_reason'] as String?,
      onCredit:               j['on_credit'] == true,
      amountPaid:             (j['amount_paid'] as num? ?? 0).toDouble(),
      paymentStatus:          j['payment_status'] as String? ?? 'unpaid',
      payments:               [for (final p in (j['supplier_payments'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)],
      invoices:               [for (final b in (j['vendor_bills'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)],
      // returned_amount on list rows; the detail carries the returns themselves.
      returnedAmount:         num.tryParse('${j['returned_amount'] ?? ''}')?.toDouble()
          ?? (j['returns'] as List? ?? const []).fold<double>(0, (s, r) => s + (num.tryParse('${(r as Map)['total_amount']}') ?? 0)),
    );
  }

  /// What's still to pay: the order less goods sent back and payments.
  double get paymentDue {
    final due = totalAmount - returnedAmount - amountPaid;
    return due > 0 ? due : 0;
  }

  /// Goods can go back to the supplier once some were received.
  bool get canReturn => status == 'partially_received' || status == 'received';

  String get statusLabel => switch (status) {
    'draft'                       => 'Draft',
    'pending_sales_manager'       => 'Awaiting Sales Approval',
    'pending_director_review'     => 'Awaiting Director Review',
    'pending_payment_initiation'  => 'Awaiting Payment',
    'pending_director_final'      => 'Awaiting Final Approval',
    'approved'                    => 'Approved',
    'rejected'                    => 'Rejected',
    'sent'                        => 'Sent',
    'acknowledged'                => 'Acknowledged',
    'partially_received'          => 'Partial GRN',
    'received'                    => 'Received',
    'cancelled'                   => 'Cancelled',
    _                             => status,
  };
}
