import '../models/client.dart';
import 'api_client.dart';

/// Customer organisations — backed by the API's `/hospitals` endpoints.
class ClientService {
  ClientService._();
  static final instance = ClientService._();
  final _dio = ApiClient.instance.dio;

  /// Server-side search for comboboxes — never loads the full directory.
  Future<List<Client>> search(String q) async {
    final res = await _dio.get('/hospitals', queryParameters: {'q': q, 'per_page': 50});
    final (data, _) = ApiClient.unwrapList(res);
    return data.map((j) => Client.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Client> get(int id) async {
    final res = await _dio.get('/hospitals/$id');
    return Client.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Client> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/hospitals', data: data);
    return Client.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Client> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/hospitals/$id', data: data);
    return Client.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
