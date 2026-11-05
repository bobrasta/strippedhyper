/// A lot of a product that still has stock (GET /inventory-lots) — offered
/// in the product search on the sale / invoice / quotation forms.
class InventoryLot {
  const InventoryLot({required this.itemId, required this.lotNumber, this.expiry, required this.qtyLeft});

  final int itemId;
  final String lotNumber;
  final DateTime? expiry;
  final int qtyLeft;

  factory InventoryLot.fromJson(Map<String, dynamic> j) => InventoryLot(
    itemId:    (j['inventory_item_id'] as num).toInt(),
    lotNumber: j['lot_number'] as String,
    expiry:    DateTime.tryParse(j['expiry_date'] as String? ?? ''),
    qtyLeft:   (j['qty_left'] as num).toInt(),
  );
}
