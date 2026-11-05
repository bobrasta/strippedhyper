enum StockOutStatus { pending, approved, rejected, cancelled }

extension StockOutStatusX on StockOutStatus {
  String get label => switch (this) {
    StockOutStatus.pending   => 'Pending',
    StockOutStatus.approved  => 'Approved',
    StockOutStatus.rejected  => 'Rejected',
    StockOutStatus.cancelled => 'Cancelled',
  };
}

StockOutStatus _parseStockOutStatus(String s) => switch (s) {
  'approved'  => StockOutStatus.approved,
  'rejected'  => StockOutStatus.rejected,
  'cancelled' => StockOutStatus.cancelled,
  _           => StockOutStatus.pending,
};

class StockOutRequest {
  final int             id;
  final int             inventoryItemId;
  final String?         itemName;
  final String?         itemSku;
  final int             locationId;
  final String?         locationName;
  final int?            serviceTicketId;
  final String?         serviceTicketNumber;
  final String          type; // issue | write_off
  final int             quantity;
  final String          reason;
  final int             requestedBy;
  final String?         requesterName;
  final StockOutStatus  status;
  final int?            reviewedBy;
  final String?         reviewerName;
  final String?         reviewedAt;
  final String?         rejectionReason;
  final int?            stockMovementId;
  final String?         createdAt;

  const StockOutRequest({
    required this.id,
    required this.inventoryItemId,
    this.itemName,
    this.itemSku,
    required this.locationId,
    this.locationName,
    this.serviceTicketId,
    this.serviceTicketNumber,
    required this.type,
    required this.quantity,
    required this.reason,
    required this.requestedBy,
    this.requesterName,
    required this.status,
    this.reviewedBy,
    this.reviewerName,
    this.reviewedAt,
    this.rejectionReason,
    this.stockMovementId,
    this.createdAt,
  });

  factory StockOutRequest.fromJson(Map<String, dynamic> j) => StockOutRequest(
    id:              (j['id'] as num).toInt(),
    inventoryItemId: (j['inventory_item_id'] as num? ?? 0).toInt(),
    itemName:        j['item_name'] as String?,
    itemSku:         j['item_sku'] as String?,
    locationId:      (j['location_id'] as num? ?? 0).toInt(),
    locationName:    j['location_name'] as String?,
    serviceTicketId: j['service_ticket_id'] != null ? (j['service_ticket_id'] as num).toInt() : null,
    serviceTicketNumber: j['service_ticket_number'] as String?,
    type:            j['type'] as String? ?? 'issue',
    quantity:        (j['quantity'] as num? ?? 0).toInt(),
    reason:          j['reason'] as String? ?? '',
    requestedBy:     (j['requested_by'] as num? ?? 0).toInt(),
    requesterName:   j['requester_name'] as String?,
    status:          _parseStockOutStatus(j['status'] as String? ?? 'pending'),
    reviewedBy:      j['reviewed_by'] != null ? (j['reviewed_by'] as num).toInt() : null,
    reviewerName:    j['reviewer_name'] as String?,
    reviewedAt:      j['reviewed_at'] as String?,
    rejectionReason: j['rejection_reason'] as String?,
    stockMovementId: j['stock_movement_id'] != null ? (j['stock_movement_id'] as num).toInt() : null,
    createdAt:       j['created_at'] as String?,
  );

  bool get isPending => status == StockOutStatus.pending;
}
