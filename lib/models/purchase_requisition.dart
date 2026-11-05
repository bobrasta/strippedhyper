class PurchaseRequisitionItem {
  final int    id;
  final int    inventoryItemId;
  final String? itemName;
  final String? itemSku;
  final int    quantityRequested;
  final String? justification;
  final double estimatedCost;
  final String currency;

  const PurchaseRequisitionItem({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.quantityRequested,
    this.justification,
    this.estimatedCost = 0,
    this.currency = 'TZS',
  });

  factory PurchaseRequisitionItem.fromJson(Map<String, dynamic> j) {
    final item = j['inventory_item'] as Map<String, dynamic>?;
    return PurchaseRequisitionItem(
      id:                (j['id'] as num).toInt(),
      inventoryItemId:   (j['inventory_item_id'] as num).toInt(),
      itemName:          item?['name'] as String?,
      itemSku:           item?['sku']  as String?,
      quantityRequested: (j['quantity_requested'] as num? ?? 0).toInt(),
      justification:     j['justification'] as String?,
      estimatedCost:     (j['estimated_cost'] as num? ?? 0).toDouble(),
      currency:          j['currency']      as String? ?? 'TZS',
    );
  }
}

class PurchaseRequisition {
  final int    id;
  final String prNumber;
  final String title;
  final String status;         // draft | submitted | approved | rejected | ordered
  final String origin;         // manual | reorder | new_product
  final String? notes;
  final String? requestedByName;
  final String? approvedByName;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime  createdAt;
  final List<PurchaseRequisitionItem> items;

  const PurchaseRequisition({
    required this.id,
    required this.prNumber,
    required this.title,
    required this.status,
    this.origin = 'manual',
    this.notes,
    this.requestedByName,
    this.approvedByName,
    this.submittedAt,
    this.approvedAt,
    required this.createdAt,
    this.items = const [],
  });

  factory PurchaseRequisition.fromJson(Map<String, dynamic> j) => PurchaseRequisition(
    id:               (j['id'] as num).toInt(),
    prNumber:         j['pr_number']        as String? ?? '—',
    title:            j['title']            as String? ?? '—',
    status:           j['status']           as String? ?? 'draft',
    origin:           j['origin']           as String? ?? 'manual',
    notes:            j['notes']            as String?,
    requestedByName:  (j['requested_by']   as Map?)? ['name'] as String?,
    approvedByName:   (j['approved_by']    as Map?)? ['name'] as String?,
    submittedAt:      j['submitted_at'] != null
        ? DateTime.tryParse(j['submitted_at'] as String) : null,
    approvedAt:       j['approved_at'] != null
        ? DateTime.tryParse(j['approved_at'] as String) : null,
    createdAt:        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    items:            (j['items'] as List? ?? [])
        .map((i) => PurchaseRequisitionItem.fromJson(i as Map<String, dynamic>)).toList(),
  );

  String get statusLabel => switch (status) {
    'draft'     => 'Draft',
    'submitted' => 'Submitted',
    'approved'  => 'Approved',
    'rejected'  => 'Rejected',
    'ordered'   => 'Ordered',
    _           => status,
  };
}
