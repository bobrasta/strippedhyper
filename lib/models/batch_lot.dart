class BatchLot {
  final int     id;
  final int     inventoryItemId;
  final String  batchNumber;
  final String? lotNumber;
  final DateTime? expiryDate;
  final DateTime? manufacturedDate;
  final int     qtyReceived;
  final int     qtyRemaining;
  final int?    supplierId;
  final String? supplierName;
  final int     unitCost;
  final String  currency;
  final DateTime? receivedAt;
  final String? notes;
  final bool    isExpired;
  final bool    isExpiringSoon;

  const BatchLot({
    required this.id,
    required this.inventoryItemId,
    required this.batchNumber,
    this.lotNumber,
    this.expiryDate,
    this.manufacturedDate,
    required this.qtyReceived,
    required this.qtyRemaining,
    this.supplierId,
    this.supplierName,
    required this.unitCost,
    this.currency = 'TZS',
    this.receivedAt,
    this.notes,
    this.isExpired = false,
    this.isExpiringSoon = false,
  });

  factory BatchLot.fromJson(Map<String, dynamic> j) => BatchLot(
    id:               (j['id']                as num).toInt(),
    inventoryItemId:  (j['inventory_item_id'] as num).toInt(),
    batchNumber:      j['batch_number']        as String? ?? '—',
    lotNumber:        j['lot_number']          as String?,
    expiryDate:       j['expiry_date'] != null
        ? DateTime.tryParse(j['expiry_date'] as String)
        : null,
    manufacturedDate: j['manufactured_date'] != null
        ? DateTime.tryParse(j['manufactured_date'] as String)
        : null,
    qtyReceived:  (j['qty_received']  as num? ?? 0).toInt(),
    qtyRemaining: (j['qty_remaining'] as num? ?? 0).toInt(),
    supplierId:   j['supplier_id'] != null ? (j['supplier_id'] as num).toInt() : null,
    supplierName: j['supplier_name'] as String?,
    unitCost:     (j['unit_cost']    as num? ?? 0).toInt(),
    currency:     j['currency']      as String? ?? 'TZS',
    receivedAt:   j['received_at'] != null
        ? DateTime.tryParse(j['received_at'] as String)
        : null,
    notes:          j['notes']          as String?,
    isExpired:      j['is_expired']     as bool? ?? false,
    isExpiringSoon: j['is_expiring_soon'] as bool? ?? false,
  );

  int get qtyUsed => qtyReceived - qtyRemaining;
  double get usagePercent => qtyReceived > 0 ? qtyUsed / qtyReceived : 0;
}
