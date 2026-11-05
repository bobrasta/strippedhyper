class TaxRate {
  final int    id;
  final String name;
  final double rate;
  final bool   isDefault;

  const TaxRate({required this.id, required this.name, required this.rate, required this.isDefault});

  factory TaxRate.fromJson(Map<String, dynamic> j) => TaxRate(
    id:        (j['id'] as num).toInt(),
    name:      j['name'] as String? ?? '',
    rate:      (j['rate'] as num?)?.toDouble() ?? 0,
    isDefault: j['is_default'] as bool? ?? false,
  );
}
