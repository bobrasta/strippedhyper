class SalesOrderItem {
  const SalesOrderItem({
    required this.id,
    required this.inventoryItemId,
    required this.description,
    required this.unitOfMeasure,
    required this.quantityOrdered,
    required this.quantityDelivered,
    required this.quantityInvoiced,
    required this.unitPrice,
    required this.totalPrice,
    required this.itemSku,
  });

  final int id;
  final int? inventoryItemId;
  final String description;
  final String unitOfMeasure;
  final int quantityOrdered;
  final int quantityDelivered;
  final int quantityInvoiced;
  final int unitPrice;
  final int totalPrice;
  final String? itemSku;

  bool get isFullyDelivered => quantityDelivered >= quantityOrdered;
  int get quantityRemaining => quantityOrdered - quantityDelivered;

  factory SalesOrderItem.fromJson(Map<String, dynamic> j) => SalesOrderItem(
    id:                  j['id'] as int,
    inventoryItemId:     j['inventory_item_id'] as int?,
    description:         j['description'] as String,
    unitOfMeasure:       j['unit_of_measure'] as String? ?? 'pcs',
    quantityOrdered:     j['quantity_ordered'] as int,
    quantityDelivered:   j['quantity_delivered'] as int? ?? 0,
    quantityInvoiced:    j['quantity_invoiced'] as int? ?? 0,
    unitPrice:           j['unit_price'] as int,
    totalPrice:          j['total_price'] as int,
    itemSku:             j['item_sku'] as String?,
  );
}

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.quotationId,
    required this.quotationNumber,
    required this.clientName,
    required this.clientContact,
    required this.locationId,
    required this.locationName,
    required this.status,
    required this.approvalStatus,
    required this.approvalReason,
    required this.approvedByName,
    required this.rejectionReason,
    required this.currency,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.notes,
    required this.expectedDeliveryDate,
    required this.createdByName,
    required this.confirmedByName,
    this.commissionAgentName,
    this.commissionPercent,
    this.commissionAmount,
    required this.confirmedAt,
    required this.deliveredAt,
    this.deliveredByName,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final String orderNumber;
  final int? quotationId;
  final String? quotationNumber;
  final String clientName;
  final String? clientContact;
  final int? locationId;
  final String? locationName;
  final String status;
  final String approvalStatus;
  final String? approvalReason;
  final String? approvedByName;
  final String? rejectionReason;
  final String currency;
  final int subtotal;
  final int discountAmount;
  final int taxAmount;
  final int totalAmount;
  final String? notes;
  final String? expectedDeliveryDate;
  final String? createdByName;
  final String? confirmedByName;
  final String? commissionAgentName;
  final double? commissionPercent;
  final int? commissionAmount;
  final String? confirmedAt;
  final String? deliveredAt;
  final String? deliveredByName;
  final String createdAt;
  final List<SalesOrderItem> items;

  String get statusLabel => const {
    'pending':    'Pending',
    'confirmed':  'Confirmed',
    'delivering': 'Delivering',
    'delivered':  'Delivered',
    'cancelled':  'Cancelled',
  }[status] ?? status;

  bool get canConfirm   => status == 'pending';
  bool get canDeliver   => status == 'confirmed' || status == 'delivering';
  bool get canCancel    => status != 'delivered' && status != 'cancelled';
  bool get needsApproval => approvalStatus == 'pending';

  factory SalesOrder.fromJson(Map<String, dynamic> j) => SalesOrder(
    id:                   j['id'] as int,
    orderNumber:          j['order_number'] as String,
    quotationId:          j['quotation_id'] as int?,
    quotationNumber:      j['quotation_number'] as String?,
    clientName:           j['client_name'] as String,
    clientContact:        j['client_contact'] as String?,
    locationId:           j['location_id'] as int?,
    locationName:         j['location_name'] as String?,
    approvalStatus:       j['approval_status'] as String? ?? 'not_required',
    approvalReason:       j['approval_reason'] as String?,
    approvedByName:       j['approved_by_name'] as String?,
    rejectionReason:      j['rejection_reason'] as String?,
    status:               j['status'] as String,
    currency:             j['currency'] as String? ?? 'TZS',
    subtotal:             j['subtotal'] as int? ?? 0,
    discountAmount:       j['discount_amount'] as int? ?? 0,
    taxAmount:            j['tax_amount'] as int? ?? 0,
    totalAmount:          j['total_amount'] as int? ?? 0,
    notes:                j['notes'] as String?,
    expectedDeliveryDate: j['expected_delivery_date'] as String?,
    createdByName:        j['created_by_name'] as String?,
    confirmedByName:      j['confirmed_by_name'] as String?,
    commissionAgentName:  j['commission_agent_name'] as String?,
    commissionPercent:    (j['commission_percent'] as num?)?.toDouble(),
    commissionAmount:     (j['commission_amount'] as num?)?.toInt(),
    confirmedAt:          j['confirmed_at'] as String?,
    deliveredAt:          j['delivered_at'] as String?,
    deliveredByName:      j['delivered_by_name'] as String?,
    createdAt:            j['created_at'] as String,
    items: (j['items'] as List<dynamic>? ?? [])
        .map((e) => SalesOrderItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
