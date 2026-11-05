import '../models/stock_out_request.dart';
import 'api_client.dart';

class StockOutRequestService {
  StockOutRequestService._();
  static final instance = StockOutRequestService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Only covers the unfiltered (status == null) query.
  static List<StockOutRequest>? cachedDefaultList;

  Future<List<StockOutRequest>> list({String? status}) async {
    final res = await _dio.get('/stock-out-requests', queryParameters: {
      'status': ?status,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final requests = data.map((j) => StockOutRequest.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null) cachedDefaultList = requests;
    return requests;
  }

  Future<StockOutRequest> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/stock-out-requests', data: data);
    return StockOutRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<StockOutRequest> approve(int id) async {
    final res = await _dio.post('/stock-out-requests/$id/approve');
    return StockOutRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<StockOutRequest> reject(int id, {String? reason}) async {
    final res = await _dio.post('/stock-out-requests/$id/reject', data: {'rejection_reason': reason});
    return StockOutRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<StockOutRequest> cancel(int id) async {
    final res = await _dio.post('/stock-out-requests/$id/cancel');
    return StockOutRequest.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
