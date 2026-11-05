class SoldInfo {
  final int? salesOrderId;
  final String? salesOrderNumber;
  final String? hospitalName;
  final DateTime? deliveredAt;

  const SoldInfo({this.salesOrderId, this.salesOrderNumber, this.hospitalName, this.deliveredAt});

  factory SoldInfo.fromJson(Map<String, dynamic> j) => SoldInfo(
    salesOrderId:     (j['sales_order_id'] as num?)?.toInt(),
    salesOrderNumber: j['sales_order_number'] as String?,
    hospitalName:     j['hospital_name'] as String?,
    deliveredAt:      j['delivered_at'] != null ? DateTime.tryParse(j['delivered_at'] as String) : null,
  );
}

class ActionInfo {
  final String? by;
  final DateTime? at;

  const ActionInfo({this.by, this.at});

  factory ActionInfo.fromJson(Map<String, dynamic> j) => ActionInfo(
    by: j['by'] as String?,
    at: j['at'] != null ? DateTime.tryParse(j['at'] as String) : null,
  );
}

class SerialHistoryEntry {
  final String serialNumber;
  final String status;
  final DateTime? receivedAt;
  final SoldInfo? sold;
  final ActionInfo? installed;
  final ActionInfo? signedOff;
  final bool isEquipment;
  final String? machineStatus;

  const SerialHistoryEntry({
    required this.serialNumber,
    required this.status,
    this.receivedAt,
    this.sold,
    this.installed,
    this.signedOff,
    this.isEquipment = false,
    this.machineStatus,
  });

  factory SerialHistoryEntry.fromJson(Map<String, dynamic> j) => SerialHistoryEntry(
    serialNumber: j['serial_number'] as String,
    status:       j['status'] as String? ?? 'available',
    receivedAt:   j['received_at'] != null ? DateTime.tryParse(j['received_at'] as String) : null,
    sold:         j['sold'] is Map ? SoldInfo.fromJson(j['sold'] as Map<String, dynamic>) : null,
    installed:    j['installed'] is Map ? ActionInfo.fromJson(j['installed'] as Map<String, dynamic>) : null,
    signedOff:    j['signed_off'] is Map ? ActionInfo.fromJson(j['signed_off'] as Map<String, dynamic>) : null,
    isEquipment:  j['is_equipment'] as bool? ?? false,
    machineStatus: j['machine_status'] as String?,
  );
}
