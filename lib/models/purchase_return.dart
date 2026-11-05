/// Goods sent back to the supplier out of a received purchase
/// (Purchases → List purchase returns).
class PurchaseReturnLine {
  final int id;
  final String? itemName;
  final String? itemSku;
  final int quantity;
  final double unitCost;
  final double total;

  const PurchaseReturnLine({required this.id, this.itemName, this.itemSku,
      required this.quantity, required this.unitCost, required this.total});

  factory PurchaseReturnLine.fromJson(Map<String, dynamic> j) {
    final item = j['inventory_item'] as Map<String, dynamic>?;
    return PurchaseReturnLine(
      id:       (j['id'] as num).toInt(),
      itemName: item?['name'] as String?,
      itemSku:  item?['sku'] as String?,
      quantity: (j['quantity'] as num? ?? 0).toInt(),
      unitCost: num.tryParse('${j['unit_cost']}')?.toDouble() ?? 0,
      total:    num.tryParse('${j['total']}')?.toDouble() ?? 0,
    );
  }
}

class PurchaseReturn {
  final int id;
  final String returnNumber;
  final int purchaseOrderId;
  final String? poNumber;
  final String? supplierName;
  final String? locationName;
  final DateTime returnDate;
  final String currency;
  final double totalAmount;
  /// On the supplier's account (the purchase had a supplier invoice).
  final bool posted;
  final String? reason;
  final String? addedBy;
  final List<PurchaseReturnLine> lines;

  const PurchaseReturn({
    required this.id, required this.returnNumber, required this.purchaseOrderId,
    this.poNumber, this.supplierName, this.locationName, required this.returnDate,
    this.currency = 'TZS', required this.totalAmount, this.posted = false,
    this.reason, this.addedBy, this.lines = const [],
  });

  factory PurchaseReturn.fromJson(Map<String, dynamic> j) => PurchaseReturn(
    id:              (j['id'] as num).toInt(),
    returnNumber:    j['return_number'] as String? ?? '—',
    purchaseOrderId: (j['purchase_order_id'] as num).toInt(),
    poNumber:        (j['purchase_order'] as Map?)?['po_number'] as String?,
    supplierName:    (j['supplier'] as Map?)?['name'] as String?,
    locationName:    (j['location'] as Map?)?['name'] as String?,
    returnDate:      DateTime.tryParse('${j['return_date']}') ?? DateTime.now(),
    currency:        j['currency'] as String? ?? 'TZS',
    totalAmount:     num.tryParse('${j['total_amount']}')?.toDouble() ?? 0,
    posted:          j['posted'] == true,
    reason:          j['reason'] as String?,
    addedBy:         (j['created_by'] as Map?)?['name'] as String?,
    lines:           [for (final l in (j['items'] as List? ?? const [])) PurchaseReturnLine.fromJson(l as Map<String, dynamic>)],
  );

  int get totalItems => lines.fold(0, (s, l) => s + l.quantity);
}
