class UserPermission {
  final String key;
  final String scope;

  const UserPermission({required this.key, required this.scope});

  factory UserPermission.fromJson(Map<String, dynamic> j) => UserPermission(
    key:   j['key'] as String? ?? '',
    scope: j['scope'] as String? ?? 'all',
  );
}

class PermissionCatalogItem {
  final int id;
  final String key;
  final String label;
  final String? description;

  const PermissionCatalogItem({
    required this.id,
    required this.key,
    required this.label,
    this.description,
  });

  factory PermissionCatalogItem.fromJson(Map<String, dynamic> j) => PermissionCatalogItem(
    id:          (j['id'] as num).toInt(),
    key:         j['key'] as String? ?? '',
    label:       j['label'] as String? ?? j['key'] as String? ?? '',
    description: j['description'] as String?,
  );
}

class UserPermissionOverride {
  final int id;
  final String key;
  final String label;
  final String effect; // 'allow' | 'deny'
  final String? scope;
  final String? reason;
  final String? createdByName;
  final String? createdAt;
  // Only populated by the global audit endpoint (allOverrides) — null when
  // fetched per-user, since the caller already knows which user that is.
  final int? userId;
  final String? userName;

  const UserPermissionOverride({
    required this.id,
    required this.key,
    required this.label,
    required this.effect,
    this.scope,
    this.reason,
    this.createdByName,
    this.createdAt,
    this.userId,
    this.userName,
  });

  factory UserPermissionOverride.fromJson(Map<String, dynamic> j) => UserPermissionOverride(
    id:            (j['id'] as num).toInt(),
    key:           j['key'] as String? ?? '',
    label:         j['label'] as String? ?? j['key'] as String? ?? '',
    effect:        j['effect'] as String? ?? 'allow',
    scope:         j['scope'] as String?,
    reason:        j['reason'] as String?,
    createdByName: j['created_by_name'] as String?,
    createdAt:     j['created_at'] as String?,
    userId:        j['user_id'] != null ? (j['user_id'] as num).toInt() : null,
    userName:      j['user_name'] as String?,
  );
}

class RoleSummary {
  final int id;
  final String name;
  final bool isSystem;
  final int permissionCount;
  final List<String> permissionKeys;

  const RoleSummary({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.permissionCount,
    required this.permissionKeys,
  });

  factory RoleSummary.fromJson(Map<String, dynamic> j) => RoleSummary(
    id:              (j['id'] as num).toInt(),
    name:            j['name'] as String? ?? '—',
    isSystem:        j['is_system'] as bool? ?? false,
    permissionCount: (j['permission_count'] as num? ?? 0).toInt(),
    permissionKeys:  (j['permission_keys'] as List? ?? []).cast<String>(),
  );
}
