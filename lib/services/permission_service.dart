import '../models/permission.dart';
import 'api_client.dart';

class PermissionService {
  PermissionService._();
  static final instance = PermissionService._();
  final _dio = ApiClient.instance.dio;

  /// Always from the network: startup already has the remembered copy
  /// (see refreshPermissions), and this is what replaces it.
  Future<List<UserPermission>> fetchMine() async {
    final res = await _dio.get('/me/permissions', options: ApiClient.noCache);
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => UserPermission.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Effective permissions for another user — admin lookup, gated server-side.
  Future<List<UserPermission>> fetchForUser(int userId) async {
    final res = await _dio.get('/users/$userId/permissions');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => UserPermission.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<UserPermissionOverride>> overridesForUser(int userId) async {
    final res = await _dio.get('/users/$userId/permission-overrides');
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => UserPermissionOverride.fromJson(j as Map<String, dynamic>)).toList();
  }

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. allOverrides() takes no filters, so every call is the
  // default (company-wide) view.
  static List<UserPermissionOverride>? cachedAllOverrides;

  /// Every override across every user, most recent first — the audit trail.
  Future<List<UserPermissionOverride>> allOverrides() async {
    final res = await _dio.get('/permission-overrides');
    final (data, _) = ApiClient.unwrapList(res);
    final overrides = data.map((j) => UserPermissionOverride.fromJson(j as Map<String, dynamic>)).toList();
    cachedAllOverrides = overrides;
    return overrides;
  }

  Future<void> addOverride(int userId, {
    required String key,
    required String effect,
    String? scope,
    String? reason,
  }) => _dio.post('/users/$userId/permission-overrides', data: {
    'key': key,
    'effect': effect,
    'scope': ?scope,
    'reason': ?reason,
  });

  Future<void> removeOverride(int userId, int overrideId) =>
      _dio.delete('/users/$userId/permission-overrides/$overrideId');
}
