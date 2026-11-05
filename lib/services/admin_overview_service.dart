import '../models/admin_overview.dart';
import 'api_client.dart';

class AdminOverviewService {
  AdminOverviewService._();
  static final instance = AdminOverviewService._();
  final _dio = ApiClient.instance.dio;

  Future<AdminOverview> load() async {
    final res = await _dio.get('/dashboard/admin-overview');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    return AdminOverview.fromJson(data);
  }
}
