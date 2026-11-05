class StockMovement {
  final int    id;
  final int    inventoryItemId;
  final String? itemSku;
  final String? itemName;
  final String type;           // receive | issue | transfer | write_off | adjustment | return
  final int    quantity;       // signed — negative for outbound
  final int    quantityBefore;
  final int    quantityAfter;
  final int?   unitCost;
  final String? currency;
  final String? referenceType;
  final int?   referenceId;
  final String? batchNumber;
  final String? expiryDate;
  final String? notes;
  final String? performedByName;
  final String? locationName;
  final String? locationFromName;
  final String? locationToName;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.inventoryItemId,
    this.itemSku,
    this.itemName,
    required this.type,
    required this.quantity,
    required this.quantityBefore,
    required this.quantityAfter,
    this.unitCost,
    this.currency,
    this.referenceType,
    this.referenceId,
    this.batchNumber,
    this.expiryDate,
    this.notes,
    this.performedByName,
    this.locationName,
    this.locationFromName,
    this.locationToName,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> j) {
    final item = j['inventory_item'] as Map<String, dynamic>?;
    final perf = j['performed_by']  as Map<String, dynamic>?;
    final loc      = j['location']      as Map<String, dynamic>?;
    final locFrom  = j['location_from'] as Map<String, dynamic>?;
    final locTo    = j['location_to']   as Map<String, dynamic>?;

    return StockMovement(
      id:               (j['id'] as num).toInt(),
      inventoryItemId:  (j['inventory_item_id'] as num).toInt(),
      itemSku:          item?['sku']  as String?,
      itemName:         item?['name'] as String?,
      type:             j['type']             as String? ?? 'adjustment',
      quantity:         (j['quantity']         as num? ?? 0).toInt(),
      quantityBefore:   (j['quantity_before']  as num? ?? 0).toInt(),
      quantityAfter:    (j['quantity_after']   as num? ?? 0).toInt(),
      unitCost:         j['unit_cost'] != null ? (j['unit_cost'] as num).toInt() : null,
      currency:         j['currency']          as String?,
      referenceType:    j['reference_type']    as String?,
      referenceId:      j['reference_id'] != null ? (j['reference_id'] as num).toInt() : null,
      batchNumber:      j['batch_number']      as String?,
      expiryDate:       j['expiry_date']       as String?,
      notes:            j['notes']             as String?,
      performedByName:  perf?['name']          as String?,
      locationName:     loc?['name']           as String?,
      locationFromName: locFrom?['name']       as String?,
      locationToName:   locTo?['name']         as String?,
      createdAt:        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  bool get isInbound => quantity > 0;

  /// "Main Warehouse" for a normal movement, "Main Warehouse → Branch" for a transfer.
  String get locationLabel {
    if (type == 'transfer' && (locationFromName != null || locationToName != null)) {
      return '${locationFromName ?? '—'} → ${locationToName ?? '—'}';
    }
    return locationName ?? '—';
  }

  String get typeLabel => switch (type) {
    'receive'    => 'Receive',
    'issue'      => 'Issue',
    'transfer'   => 'Transfer',
    'write_off'  => 'Write-off',
    'adjustment' => 'Adjustment',
    'return'     => 'Return',
    _            => type,
  };
}
