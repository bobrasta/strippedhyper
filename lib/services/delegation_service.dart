import '../models/delegation.dart';
import 'api_client.dart';

class DelegationService {
  DelegationService._();
  static final instance = DelegationService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no filters, so every call is the default view.
  static List<Delegation>? cachedList;

  Future<List<Delegation>> list() async {
    final res = await _dio.get('/delegations');
    final (data, _) = ApiClient.unwrapList(res);
    final delegations = data.map((j) => Delegation.fromJson(j as Map<String, dynamic>)).toList();
    cachedList = delegations;
    return delegations;
  }

  Future<Delegation> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/delegations', data: data);
    return Delegation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Delegation> revoke(int id) async {
    final res = await _dio.post('/delegations/$id/revoke');
    return Delegation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
