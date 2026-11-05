import 'api_client.dart';

class SettingService {
  SettingService._();
  static final instance = SettingService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning.
  static Map<String, String?>? cachedAll;

  Future<Map<String, String?>> all() async {
    final res = await _dio.get('/settings');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    final settings = data.map((k, v) => MapEntry(k, v as String?));
    cachedAll = settings;
    return settings;
  }

  Future<void> set(String key, String value) => _dio.put('/settings/$key', data: {'value': value});
}
