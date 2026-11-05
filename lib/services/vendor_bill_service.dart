import '../models/vendor_bill.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class VendorBillService {
  VendorBillService._();
  static final instance = VendorBillService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<VendorBill>? cachedDefaultList;
  static final Map<int, VendorBill> cachedById = {};

  Future<List<VendorBill>> list({int? supplierId, String? status, String? search, Period? period}) async {
    final res = await _dio.get('/vendor-bills', queryParameters: {
      ...?period?.query,
      'supplier_id': ?supplierId,
      'status':      ?status,
      'search':      ?search,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final bills = data.map((j) => VendorBill.fromJson(j as Map<String, dynamic>)).toList();
    if (supplierId == null && status == null && search == null && (period?.isDefault ?? false)) cachedDefaultList = bills;
    return bills;
  }

  Future<VendorBill> get(int id) async {
    final res = await _dio.get('/vendor-bills/$id');
    final bill = VendorBill.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[bill.id] = bill;
    return bill;
  }

  Future<VendorBill> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/vendor-bills', data: data);
    return VendorBill.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorBill> approve(int id) async {
    final res = await _dio.post('/vendor-bills/$id/approve');
    return VendorBill.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorBill> cancel(int id) async {
    final res = await _dio.post('/vendor-bills/$id/cancel');
    return VendorBill.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<VendorBill> recordPayment(int id, Map<String, dynamic> data) async {
    final res = await _dio.post('/vendor-bills/$id/payments', data: data);
    return VendorBill.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/vendor-bills/$id');
}
