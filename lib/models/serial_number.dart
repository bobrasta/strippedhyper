class SerialNumber {
  final int     id;
  final int     inventoryItemId;
  final String  serialNumber;
  final String  status;        // available|assigned|in_service|damaged|disposed
  final bool    hasMissingParts;
  final int?    locationId;
  final String? locationName;
  final int?    assignedToMachineId;
  final String? machineName;
  final DateTime? purchaseDate;
  final DateTime? warrantyExpiresAt;
  final bool    isWarrantyExpired;
  final String? notes;

  const SerialNumber({
    required this.id,
    required this.inventoryItemId,
    required this.serialNumber,
    required this.status,
    this.hasMissingParts = false,
    this.locationId,
    this.locationName,
    this.assignedToMachineId,
    this.machineName,
    this.purchaseDate,
    this.warrantyExpiresAt,
    this.isWarrantyExpired = false,
    this.notes,
  });

  factory SerialNumber.fromJson(Map<String, dynamic> j) => SerialNumber(
    id:               (j['id']                as num).toInt(),
    inventoryItemId:  (j['inventory_item_id'] as num).toInt(),
    serialNumber:     j['serial_number']       as String? ?? '—',
    status:           j['status']              as String? ?? 'available',
    hasMissingParts:  j['has_missing_parts']   as bool? ?? false,
    locationId:       j['location_id'] != null ? (j['location_id'] as num).toInt() : null,
    locationName:     j['location_name']           as String?,
    assignedToMachineId: j['assigned_to_machine_id'] != null
        ? (j['assigned_to_machine_id'] as num).toInt()
        : null,
    machineName:      j['machine_name']            as String?,
    purchaseDate:     j['purchase_date'] != null
        ? DateTime.tryParse(j['purchase_date'] as String)
        : null,
    warrantyExpiresAt: j['warranty_expires_at'] != null
        ? DateTime.tryParse(j['warranty_expires_at'] as String)
        : null,
    isWarrantyExpired: j['is_warranty_expired'] as bool? ?? false,
    notes:             j['notes']               as String?,
  );

  String get statusLabel => switch (status) {
    'available'  => 'Available',
    'assigned'   => 'Assigned',
    'in_service' => 'In Service',
    'damaged'    => 'Damaged',
    'disposed'   => 'Disposed',
    _            => status,
  };
}
