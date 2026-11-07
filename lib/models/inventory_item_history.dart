/// What took a unit out of stock (a sales order or another reference).
class SoldInfo {
  final String? salesOrderNumber;
  final DateTime? deliveredAt;

  const SoldInfo({this.salesOrderNumber, this.deliveredAt});

  factory SoldInfo.fromJson(Map<String, dynamic> j) => SoldInfo(
    salesOrderNumber: j['sales_order_number'] as String?,
    deliveredAt:      j['delivered_at'] != null ? DateTime.tryParse(j['delivered_at'] as String) : null,
  );
}

class SerialHistoryEntry {
  final String serialNumber;
  final String status;
  final DateTime? receivedAt;
  final SoldInfo? sold;

  const SerialHistoryEntry({
    required this.serialNumber,
    required this.status,
    this.receivedAt,
    this.sold,
  });

  factory SerialHistoryEntry.fromJson(Map<String, dynamic> j) => SerialHistoryEntry(
    serialNumber: j['serial_number'] as String,
    status:       j['status'] as String? ?? 'available',
    receivedAt:   j['received_at'] != null ? DateTime.tryParse(j['received_at'] as String) : null,
    sold:         j['sold'] is Map ? SoldInfo.fromJson(j['sold'] as Map<String, dynamic>) : null,
  );
}
