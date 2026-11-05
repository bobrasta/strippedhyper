import 'package:dio/dio.dart';
import '../models/contract.dart';
import 'api_client.dart';

export '../models/contract.dart';

class ContractService {
  ContractService._();
  static final instance = ContractService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. Keyed by the user id it's scoped to.
  static final Map<int, List<Contract>> cachedByUserId = {};

  Future<List<Contract>> list(int userId) async {
    final res = await _dio.get('/staff/$userId/contracts');
    final (data, _) = ApiClient.unwrapList(res);
    final list = data.map((j) => Contract.fromJson(j as Map<String, dynamic>)).toList();
    cachedByUserId[userId] = list;
    return list;
  }

  Future<Contract> create(int userId, Map<String, dynamic> data) async {
    final res = await _dio.post('/staff/$userId/contracts', data: data);
    return Contract.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Contract> renew(int contractId, Map<String, dynamic> data) async {
    final res = await _dio.post('/contracts/$contractId/renew', data: data);
    return Contract.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Contract> end(int contractId, {String? endDate}) async {
    final res = await _dio.post('/contracts/$contractId/end', data: {'end_date': ?endDate});
    return Contract.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Contract> resign(int contractId, {required String resignationDate, String? reason}) async {
    final res = await _dio.post('/contracts/$contractId/resign', data: {
      'resignation_date': resignationDate,
      'resignation_reason': ?reason,
    });
    return Contract.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Contract> uploadDocument(int contractId, String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post('/contracts/$contractId/document', data: formData);
    return Contract.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Allowance> addAllowance(int contractId, Map<String, dynamic> data) async {
    final res = await _dio.post('/contracts/$contractId/allowances', data: data);
    return Allowance.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> removeAllowance(int contractId, int allowanceId) =>
      _dio.delete('/contracts/$contractId/allowances/$allowanceId');
}
