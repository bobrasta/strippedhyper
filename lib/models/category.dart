class Category {
  final int    id;
  final String name;
  final String slug;
  final int?   parentId;
  final String? description;
  final bool   isActive;

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.parentId,
    this.description,
    this.isActive = true,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id:          (j['id'] as num).toInt(),
    name:        j['name']        as String? ?? '—',
    slug:        j['slug']        as String? ?? '',
    parentId:    j['parent_id'] != null ? (j['parent_id'] as num).toInt() : null,
    description: j['description'] as String?,
    isActive:    j['is_active']   as bool? ?? true,
  );
}
