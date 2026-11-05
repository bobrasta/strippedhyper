import 'package:dio/dio.dart';

import '../models/creditor.dart';
import 'api_client.dart';

/// Creditors Ledger, payments to creditors (initiate → Director) and the
/// connections web.
class CreditorService {
  CreditorService._();
  static final instance = CreditorService._();
  final _dio = ApiClient.instance.dio;

  static CreditorList? cachedList;
  static List<PaymentAccount>? _accounts;

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<CreditorList> list({DateTime? asAt, String? category, String? search, bool withBalance = false}) async {
    final res = await _dio.get('/creditors', queryParameters: {
      if (asAt != null) 'as_at': _iso(asAt),
      'category': ?category,
      if (search != null && search.isNotEmpty) 'q': search,
      if (withBalance) 'with_balance': 1,
    });
    final list = CreditorList(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
    if (asAt == null && category == null && (search ?? '').isEmpty) cachedList = list;
    return list;
  }

  Map<String, dynamic> _period(DateTime? from, DateTime? to) => {
    if (from != null) 'from': _iso(from),
    if (to != null) 'to': _iso(to),
  };

  Future<CreditorStatement> statement(String type, int id, {DateTime? from, DateTime? to}) async {
    final res = await _dio.get('/creditors/$type/$id/statement', queryParameters: _period(from, to));
    return CreditorStatement(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<List<int>> _bytes(String path, Map<String, dynamic> q) async {
    final res = await _dio.get<List<int>>(path, queryParameters: q, options: Options(responseType: ResponseType.bytes));
    return res.data ?? const [];
  }

  Future<List<int>> statementXlsx(String type, int id, {DateTime? from, DateTime? to}) =>
      _bytes('/creditors/$type/$id/statement/xlsx', _period(from, to));
  Future<List<int>> statementPdf(String type, int id, {DateTime? from, DateTime? to}) =>
      _bytes('/creditors/$type/$id/statement/pdf', _period(from, to));
  Future<List<int>> allXlsx({DateTime? from, DateTime? to}) => _bytes('/creditors/xlsx', _period(from, to));

  Future<void> saveOpening(String type, int id, {required DateTime asAt, required double amount, double? rate, String? notes}) =>
      _dio.put('/creditors/$type/$id/opening-balance', data: {
        'as_at': _iso(asAt), 'amount': amount, 'exchange_rate': ?rate, 'notes': ?notes,
      });

  Future<void> deleteOpening(String type, int id) => _dio.delete('/creditors/$type/$id/opening-balance');

  // ── payments ──

  Future<List<PaymentAccount>> accounts() async {
    if (_accounts != null) return _accounts!;
    final res = await _dio.get('/supplier-payments/accounts');
    return _accounts = [for (final a in (ApiClient.unwrap(res) as List)) PaymentAccount.fromJson(Map<String, dynamic>.from(a as Map))];
  }

  Future<List<SupplierPayment>> payments({String? status, String? creditorType, int? creditorId, int? purchaseOrderId}) async {
    final res = await _dio.get('/supplier-payments', queryParameters: {
      'status': ?status,
      if (creditorType == 'supplier') 'supplier_id': ?creditorId,
      if (creditorType == 'vendor') 'vendor_id': ?creditorId,
      'purchase_order_id': ?purchaseOrderId,
    }, options: ApiClient.noCache);
    return [for (final p in (ApiClient.unwrap(res) as List)) SupplierPayment(Map<String, dynamic>.from(p as Map))];
  }

  /// Finance asks to pay; the Director approves before it posts.
  Future<SupplierPayment> requestPayment(Map<String, dynamic> data) async {
    final res = await _dio.post('/supplier-payments', data: data);
    return SupplierPayment(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }

  Future<SupplierPayment> approve(int id) async =>
      SupplierPayment(Map<String, dynamic>.from(ApiClient.unwrap(await _dio.post('/supplier-payments/$id/approve')) as Map));

  Future<SupplierPayment> reject(int id, String reason) async => SupplierPayment(Map<String, dynamic>.from(
      ApiClient.unwrap(await _dio.post('/supplier-payments/$id/reject', data: {'rejection_reason': reason})) as Map));

  // ── connections ──

  Future<Connections> connections(String type, int id) async {
    final res = await _dio.get('/connections/$type/$id');
    return Connections(Map<String, dynamic>.from(ApiClient.unwrap(res) as Map));
  }
}
