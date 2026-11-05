import '../models/permission.dart';
import 'api_client.dart';

class RoleService {
  RoleService._();
  static final instance = RoleService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Neither list() nor catalog() takes filters, so every call is
  // the default view.
  static List<RoleSummary>? cachedList;
  static Map<String, List<PermissionCatalogItem>>? cachedCatalog;

  Future<List<RoleSummary>> list() async {
    final res = await _dio.get('/roles');
    final (data, _) = ApiClient.unwrapList(res);
    final roles = data.map((j) => RoleSummary.fromJson(j as Map<String, dynamic>)).toList();
    cachedList = roles;
    return roles;
  }

  /// Full permission catalog, grouped by module (e.g. 'sales' -> [...]).
  Future<Map<String, List<PermissionCatalogItem>>> catalog() async {
    final res = await _dio.get('/permissions');
    final raw = ApiClient.unwrap(res);
    if (raw is! Map) return {};
    final result = raw.map((module, items) => MapEntry(
      module as String,
      (items as List).map((j) => PermissionCatalogItem.fromJson(j as Map<String, dynamic>)).toList(),
    ));
    cachedCatalog = result;
    return result;
  }

  Future<RoleSummary> create(String name) async {
    final res = await _dio.post('/roles', data: {'name': name});
    return RoleSummary.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> rename(int roleId, String name) =>
      _dio.put('/roles/$roleId', data: {'name': name});

  Future<void> delete(int roleId) => _dio.delete('/roles/$roleId');

  /// Full replace of a role's permission set. [scopes] is optional per-key
  /// scope ('none'|'masked'|'own'|'team'|'all'); omitted keys default to 'all'.
  Future<void> syncPermissions(int roleId, List<String> permissionKeys, {Map<String, String>? scopes}) =>
      _dio.put('/roles/$roleId/permissions', data: {
        'permissions': permissionKeys.map((key) => {
          'key': key,
          if (scopes?[key] != null) 'scope': scopes![key],
        }).toList(),
      });
}
