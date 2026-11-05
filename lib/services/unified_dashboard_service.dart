import '../models/unified_dashboard_section.dart';
import 'api_client.dart';

class UnifiedDashboardService {
  UnifiedDashboardService._();
  static final instance = UnifiedDashboardService._();
  final _dio = ApiClient.instance.dio;

  Future<List<UnifiedDashboardSection>> load() async {
    final res = await _dio.get('/dashboard/unified');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    final sections = (data['sections'] as List? ?? []);
    return sections
        .map((s) => UnifiedDashboardSection.fromJson((s as Map).cast<String, dynamic>()))
        .toList();
  }
}
