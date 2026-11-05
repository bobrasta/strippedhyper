class Position {
  final int id;
  final String title;
  final String? department;
  final String? description;

  const Position({
    required this.id,
    required this.title,
    this.department,
    this.description,
  });

  factory Position.fromJson(Map<String, dynamic> j) => Position(
    id:          (j['id'] as num).toInt(),
    title:       j['title'] as String? ?? '—',
    department:  j['department'] as String?,
    description: j['description'] as String?,
  );
}
