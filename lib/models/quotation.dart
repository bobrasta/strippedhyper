import '../widgets/sales/terms_editor.dart' show TermItem, termItemsFromJson;

class QuotationItem {
  const QuotationItem({
    required this.id,
    required this.inventoryItemId,
    required this.description,
    required this.unitOfMeasure,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    this.discountAmount = 0,
    required this.totalPrice,
    required this.itemSku,
  });

  final int id;
  final int? inventoryItemId;
  final String description;
  final String unitOfMeasure;
  final int quantity;
  final int unitPrice;
  final double discountPercent;
  // TSh off the line (newer lines); discountPercent is the older kind.
  final int discountAmount;
  final int totalPrice;
  final String? itemSku;

  factory QuotationItem.fromJson(Map<String, dynamic> j) => QuotationItem(
    id:                j['id'] as int,
    inventoryItemId:   j['inventory_item_id'] as int?,
    description:       j['description'] as String,
    unitOfMeasure:     j['unit_of_measure'] as String? ?? 'pcs',
    quantity:          j['quantity'] as int,
    unitPrice:         j['unit_price'] as int,
    discountPercent:   (j['discount_percent'] as num?)?.toDouble() ?? 0,
    discountAmount:    (j['discount_amount'] as num?)?.toInt() ?? 0,
    totalPrice:        j['total_price'] as int,
    itemSku:           j['item_sku'] as String?,
  );
}

class Quotation {
  const Quotation({
    required this.id,
    required this.quotationNumber,
    required this.leadId,
    required this.clientName,
    required this.clientContact,
    required this.clientEmail,
    this.clientTin,
    required this.status,
    required this.approvalStatus,
    required this.approvalReason,
    required this.approvedByName,
    this.approvedAt,
    required this.rejectionReason,
    required this.validUntil,
    required this.currency,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.notes,
    required this.terms,
    this.termItems,
    required this.createdByName,
    required this.sentAt,
    required this.acceptedAt,
    required this.createdAt,
    this.updatedAt,
    this.salesOrderId,
    this.convertedAt,
    required this.items,
  });

  final int id;
  final String quotationNumber;
  final int? leadId;
  final String clientName;
  final String? clientContact;
  final String? clientEmail;
  final String? clientTin;
  final String status;
  final String approvalStatus;
  final String? approvalReason;
  final String? approvedByName;
  final String? approvedAt;
  final String? rejectionReason;
  final String? validUntil;
  final String currency;
  final int subtotal;
  final int discountAmount;
  final int taxAmount;
  final int totalAmount;
  final String? notes;
  final String? terms;
  /// TERMS & CONDITIONS this quotation changed; null = company defaults.
  final List<TermItem>? termItems;
  final String? createdByName;
  final String? sentAt;
  final String? acceptedAt;
  final String createdAt;
  final String? updatedAt;
  final int? salesOrderId;
  final String? convertedAt;
  final List<QuotationItem> items;

  String get statusLabel => const {
    'draft':     'Draft',
    'sent':      'Sent',
    'accepted':  'Accepted',
    'rejected':  'Rejected',
    'expired':   'Expired',
    'converted': 'Converted',
  }[status] ?? status;

  bool get needsApproval => approvalStatus == 'pending';

  factory Quotation.fromJson(Map<String, dynamic> j) => Quotation(
    id:              j['id'] as int,
    quotationNumber: j['quotation_number'] as String,
    leadId:          j['lead_id'] as int?,
    clientName:      j['client_name'] as String,
    clientContact:   j['client_contact'] as String?,
    clientEmail:     j['client_email'] as String?,
    clientTin:       j['client_tin'] as String?,
    status:          j['status'] as String,
    approvalStatus:  j['approval_status'] as String? ?? 'not_required',
    approvalReason:  j['approval_reason'] as String?,
    approvedByName:  j['approved_by_name'] as String?,
    approvedAt:      j['approved_at'] as String?,
    rejectionReason: j['rejection_reason'] as String?,
    validUntil:      j['valid_until'] as String?,
    currency:        j['currency'] as String? ?? 'TZS',
    subtotal:        j['subtotal'] as int? ?? 0,
    discountAmount:  j['discount_amount'] as int? ?? 0,
    taxAmount:       j['tax_amount'] as int? ?? 0,
    totalAmount:     j['total_amount'] as int? ?? 0,
    notes:           j['notes'] as String?,
    terms:           j['terms'] as String?,
    termItems:       termItemsFromJson(j['term_items']),
    createdByName:   j['created_by_name'] as String?,
    sentAt:          j['sent_at'] as String?,
    acceptedAt:      j['accepted_at'] as String?,
    createdAt:       j['created_at'] as String,
    updatedAt:       j['updated_at'] as String?,
    salesOrderId:    j['sales_order_id'] as int?,
    convertedAt:     j['converted_at'] as String?,
    items: (j['items'] as List<dynamic>? ?? [])
        .map((e) => QuotationItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
