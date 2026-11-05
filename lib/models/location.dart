class Location {
  final int    id;
  final String name;
  final String? code;
  final String type;
  final String typeLabel;
  final String? address;
  final String? notes;
  final bool   isActive;

  const Location({
    required this.id,
    required this.name,
    this.code,
    required this.type,
    required this.typeLabel,
    this.address,
    this.notes,
    this.isActive = true,
  });

  factory Location.fromJson(Map<String, dynamic> j) => Location(
    id:        (j['id'] as num).toInt(),
    name:      j['name']       as String? ?? '—',
    code:      j['code']       as String?,
    type:      j['type']       as String? ?? 'warehouse',
    typeLabel: j['type_label'] as String? ?? 'Warehouse',
    address:   j['address']    as String?,
    notes:     j['notes']      as String?,
    isActive:  j['is_active']  as bool? ?? true,
  );

  String get displayCode => code != null ? '$name ($code)' : name;
}
