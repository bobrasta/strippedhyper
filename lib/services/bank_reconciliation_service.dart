import 'package:dio/dio.dart';
import '../models/bank_reconciliation.dart';
import 'api_client.dart';

class BankReconciliationService {
  BankReconciliationService._();
  static final instance = BankReconciliationService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. list() takes no filters, so it's always the "default" query.
  static List<BankReconciliation>? cachedDefaultList;
  static final Map<int, BankReconciliation> cachedById = {};

  Future<List<BankReconciliation>> list() async {
    final res = await _dio.get('/bank-reconciliations');
    final (data, _) = ApiClient.unwrapList(res);
    final recons = data.map((j) => BankReconciliation.fromJson(j as Map<String, dynamic>)).toList();
    cachedDefaultList = recons;
    return recons;
  }

  Future<BankReconciliation> get(int id) async {
    final res = await _dio.get('/bank-reconciliations/$id');
    final recon = BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[recon.id] = recon;
    return recon;
  }

  Future<BankReconciliation> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/bank-reconciliations', data: data);
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BankReconciliation> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/bank-reconciliations/$id', data: data);
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/bank-reconciliations/$id');

  Future<Map<String, dynamic>> importStatement(int id, String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'csv_file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final res = await _dio.post('/bank-reconciliations/$id/import-statement', data: formData);
    final raw = ApiClient.unwrap(res);
    return raw is Map<String, dynamic> ? raw : {};
  }

  Future<BankReconciliation> clearStatement(int id) async {
    final res = await _dio.post('/bank-reconciliations/$id/clear-statement');
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BankReconciliation> autoMatch(int id) async {
    final res = await _dio.post('/bank-reconciliations/$id/auto-match');
    final body = res.data as Map<String, dynamic>;
    return BankReconciliation.fromJson(body['reconciliation'] as Map<String, dynamic>);
  }

  Future<BankReconciliation> matchLine(int reconId, int lineId, String type, int matchId) async {
    final res = await _dio.patch('/bank-reconciliations/$reconId/lines/$lineId/match', data: {
      'type': type, 'match_id': matchId,
    });
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BankReconciliation> unmatchLine(int reconId, int lineId) async {
    final res = await _dio.patch('/bank-reconciliations/$reconId/lines/$lineId/unmatch');
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BankReconciliation> complete(int id) async {
    final res = await _dio.post('/bank-reconciliations/$id/complete');
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<BankReconciliation> reopen(int id) async {
    final res = await _dio.post('/bank-reconciliations/$id/reopen');
    return BankReconciliation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
