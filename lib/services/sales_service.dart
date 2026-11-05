import '../models/sales_lead.dart';
import 'api_client.dart';

class SalesService {
  SalesService._();
  static final instance = SalesService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no filter params at all, so every call is the
  // "default" list.
  static List<SalesLead>? cachedDefaultList;
  static final Map<int, SalesLead> cachedById = {};

  Future<List<SalesLead>> list() async {
    final res = await _dio.get('/leads');
    final (data, _) = ApiClient.unwrapList(res);
    final leads = data.map((j) => SalesLead.fromJson(j as Map<String, dynamic>)).toList();
    cachedDefaultList = leads;
    return leads;
  }

  Future<SalesLead> get(int id) async {
    final res = await _dio.get('/leads/$id');
    final lead = SalesLead.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[lead.id] = lead;
    return lead;
  }

  Future<SalesLead> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/leads', data: data);
    return SalesLead.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalesLead> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/leads/$id', data: data);
    return SalesLead.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalesLead> moveStage(int id, String stage) async {
    final res = await _dio.patch('/leads/$id/stage', data: {'stage': stage});
    return SalesLead.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
