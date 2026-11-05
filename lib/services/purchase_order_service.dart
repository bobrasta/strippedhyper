import 'package:dio/dio.dart';
import '../models/purchase_order.dart';
import '../models/purchase_return.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class PurchaseOrderService {
  PurchaseOrderService._();
  static final instance = PurchaseOrderService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<PurchaseOrder>? cachedDefaultList;
  static final Map<int, PurchaseOrder> cachedById = {};

  Future<List<PurchaseOrder>> list({String? status, int? supplierId, Period? period}) async {
    // Every page: one page is only 25 orders (492 imported Clickhuduma purchases).
    final data = await ApiClient.getAllPages(_dio, '/purchase-orders', query: {
      ...?period?.query,
      'status':      ?status,
      'supplier_id': ?supplierId,
    });
    final orders = data.map((j) => PurchaseOrder.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && supplierId == null && (period?.isDefault ?? false)) cachedDefaultList = orders;
    return orders;
  }

  /// Edit a draft or rejected order (header and lines); a rejected one goes back to draft.
  Future<PurchaseOrder> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/purchase-orders/$id', data: data);
    final order = PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[order.id] = order;
    return order;
  }

  Future<PurchaseOrder> get(int id) async {
    final res = await _dio.get('/purchase-orders/$id');
    final order = PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[order.id] = order;
    return order;
  }

  /// Print — the order on the letterhead.
  Future<List<int>> pdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/purchase-orders/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  // ── Purchase returns ──────────────────────────────────────────────────────

  static List<PurchaseReturn>? cachedDefaultReturns;

  Future<List<PurchaseReturn>> returns({Period? period, int? purchaseOrderId}) async {
    final data = await ApiClient.getAllPages(_dio, '/purchase-returns', query: {
      ...?period?.query,
      'purchase_order_id': ?purchaseOrderId,
    });
    final list = data.map((j) => PurchaseReturn.fromJson(j as Map<String, dynamic>)).toList();
    if (purchaseOrderId == null && (period?.isDefault ?? false)) cachedDefaultReturns = list;
    return list;
  }

  /// [lines] maps purchase_order_item_id → quantity sent back.
  Future<PurchaseReturn> createReturn(int purchaseOrderId, Map<int, int> lines, {String? reason, DateTime? date}) async {
    final res = await _dio.post('/purchase-returns', data: {
      'purchase_order_id': purchaseOrderId,
      'reason': ?reason,
      if (date != null) 'return_date': date.toIso8601String().substring(0, 10),
      'items': [for (final e in lines.entries) {'purchase_order_item_id': e.key, 'quantity': e.value}],
    });
    return PurchaseReturn.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<List<int>> returnPdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/purchase-returns/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<PurchaseOrder> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/purchase-orders', data: data);
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> send(int id) async {
    final res = await _dio.post('/purchase-orders/$id/send');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> receive(int id, Map<String, dynamic> data) async {
    final res = await _dio.post('/purchase-orders/$id/receive', data: data);
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> cancel(int id) async {
    final res = await _dio.post('/purchase-orders/$id/cancel');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  // ── Approval / payment chain ──────────────────────────────────────────────
  // draft -> pending_sales_manager -> pending_director_review ->
  // pending_payment_initiation -> pending_director_final -> approved.

  Future<PurchaseOrder> submitForApproval(int id) async {
    final res = await _dio.post('/purchase-orders/$id/submit-for-approval');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> approveSalesManager(int id) async {
    final res = await _dio.post('/purchase-orders/$id/approve-sales-manager');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> rejectSalesManager(int id, {String? reason}) async {
    final res = await _dio.post('/purchase-orders/$id/reject-sales-manager',
        data: {'rejection_reason': reason});
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> approveDirectorReview(int id) async {
    final res = await _dio.post('/purchase-orders/$id/approve-director-review');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> rejectDirectorReview(int id, {String? reason}) async {
    final res = await _dio.post('/purchase-orders/$id/reject-director-review',
        data: {'rejection_reason': reason});
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// [payment] is the payment-request dialog's body: amount, exchange
  /// rate, paid-from account, date, reference — or {'on_credit': true}.
  Future<PurchaseOrder> initiatePayment(int id, Map<String, dynamic> payment) async {
    final res = await _dio.post('/purchase-orders/$id/initiate-payment', data: payment);
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> approveDirectorFinal(int id) async {
    final res = await _dio.post('/purchase-orders/$id/approve-director-final');
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<PurchaseOrder> rejectDirectorFinal(int id, {String? reason}) async {
    final res = await _dio.post('/purchase-orders/$id/reject-director-final',
        data: {'rejection_reason': reason});
    return PurchaseOrder.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }
}
