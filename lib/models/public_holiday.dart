class PublicHoliday {
  final int id;
  final String name;
  final String date;
  final bool recurring;

  const PublicHoliday({required this.id, required this.name, required this.date, required this.recurring});

  factory PublicHoliday.fromJson(Map<String, dynamic> j) => PublicHoliday(
    id:        (j['id'] as num).toInt(),
    name:      j['name'] as String,
    date:      j['date'] as String? ?? '—',
    recurring: j['recurring'] as bool? ?? false,
  );
}
