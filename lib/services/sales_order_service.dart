import '../models/sales_order.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class SalesOrderService {
  SalesOrderService._();
  static final instance = SalesOrderService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<SalesOrder>? cachedDefaultList;
  static final Map<int, SalesOrder> cachedById = {};

  Future<List<SalesOrder>> list({String? status, String? search, Period? period}) async {
    final res = await _dio.get('/sales-orders', queryParameters: {
      ...?period?.query,
      'status': ?status,
      'search': ?search,
    });
    final (data, _) = ApiClient.unwrapList(res);
    final orders = data.map((j) => SalesOrder.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && search == null && (period?.isDefault ?? false)) {
      cachedDefaultList = orders;
    }
    return orders;
  }

  Future<SalesOrder> get(int id) async {
    final res = await _dio.get('/sales-orders/$id');
    final order = SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[order.id] = order;
    return order;
  }

  Future<SalesOrder> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/sales-orders', data: data);
    return SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalesOrder> confirm(int id) async {
    final res = await _dio.post('/sales-orders/$id/confirm');
    return SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// Returns the updated order plus how many Machine records this delivery
  /// registered (equipment items delivered to a hospital-linked order).
  Future<(SalesOrder, int machinesCreated)> deliver(int id, {
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final res = await _dio.post('/sales-orders/$id/deliver', data: {
      'items': items,
      'notes': ?notes,
    });
    final body = res.data as Map<String, dynamic>;
    final order = SalesOrder.fromJson(body['data'] as Map<String, dynamic>);
    final machinesCreated = (body['machines_created'] as List?)?.length ?? 0;
    return (order, machinesCreated);
  }

  Future<SalesOrder> cancel(int id) async {
    final res = await _dio.post('/sales-orders/$id/cancel');
    return SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalesOrder> approve(int id) async {
    final res = await _dio.post('/sales-orders/$id/approve');
    return SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<SalesOrder> rejectApproval(int id, {String? reason}) async {
    final res = await _dio.post('/sales-orders/$id/reject-approval', data: {
      'rejection_reason': ?reason,
    });
    return SalesOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
