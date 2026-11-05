import 'package:dio/dio.dart';
import '../models/invoice.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class InvoiceService {
  InvoiceService._();
  static final instance = InvoiceService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<Invoice>? cachedDefaultList;
  static final Map<int, Invoice> cachedById = {};
  static Map<String, dynamic>? cachedRevenueSummary;
  static List<Map<String, dynamic>>? cachedRevenueByHospital;

  Future<List<Invoice>> list({String? status, String? search, int? salesOrderId, int? machineId, Period? period, String? saleStatus}) async {
    final data = await ApiClient.getAllPages(_dio, '/invoices', query: {
      ...?period?.query,
      'sale_status':     ?saleStatus,
      'status':          ?status,
      'search':          ?search,
      'sales_order_id':  ?salesOrderId,
      'machine_id':      ?machineId,
    });
    final invoices = data.map((j) => Invoice.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && search == null && salesOrderId == null && machineId == null && saleStatus == null && (period?.isDefault ?? false)) {
      cachedDefaultList = invoices;
    }
    return invoices;
  }

  // One request per invoice at a time — a hover prefetch and the detail
  // dialog opened right after it share the same fetch.
  static final Map<int, Future<Invoice>> _inFlight = {};

  // Block body on purpose: `=> _inFlight.remove(id)` returns this very
  // future, and whenComplete waits on a returned future — so get() never
  // completed and Edit / Add payment from All sales did nothing.
  Future<Invoice> get(int id) => _inFlight[id] ??= _fetch(id).whenComplete(() { _inFlight.remove(id); });

  Future<Invoice> _fetch(int id) async {
    final res = await _dio.get('/invoices/$id');
    final invoice = Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[invoice.id] = invoice;
    return invoice;
  }

  /// Warm [cachedById] (e.g. when the pointer rests on a list row) so the
  /// detail dialog opens with line items and payments already there.
  void prefetch(int id) {
    if (!cachedById.containsKey(id)) get(id).ignore();
  }

  /// Full edit (line items, terms, notes) or a sale-status change
  /// (draft ↔ proforma, or finalise with sale_status: 'final').
  Future<Invoice> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/invoices/$id', data: data);
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Invoice> updateShipping(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/invoices/$id/shipping', data: data);
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/invoices/$id');

  /// New Sale Notification: emails the invoice PDF to the customer.
  Future<String> notify(int id, {required String to, required String subject, required String message}) async {
    final res = await _dio.post('/invoices/$id/notify', data: {'to': to, 'subject': subject, 'message': message});
    return (res.data as Map)['message'] as String? ?? 'Sent.';
  }

  Future<List<int>> deliveryNoteBytes(int id) async {
    final res = await _dio.get<List<int>>('/invoices/$id/delivery-note', options: Options(responseType: ResponseType.bytes));
    return res.data ?? [];
  }

  Future<Invoice> send(int id) async {
    final res = await _dio.post('/invoices/$id/send');
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Invoice> cancel(int id) async {
    final res = await _dio.post('/invoices/$id/cancel');
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> recordPayment(int id, Map<String, dynamic> data) async {
    final res = await _dio.post('/invoices/$id/payments', data: data);
    final body = res.data as Map<String, dynamic>;
    return {
      'payment': Payment.fromJson(body['data'] as Map<String, dynamic>),
      'invoice': Invoice.fromJson(body['invoice'] as Map<String, dynamic>),
    };
  }

  Future<Invoice> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/invoices', data: data);
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Invoice> fromSalesOrder(int salesOrderId) async {
    final res = await _dio.post('/sales-orders/$salesOrderId/invoice');
    return Invoice.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  /// [year] = Jan-Dec of that year; null = rolling last 12 months.
  Future<Map<String, dynamic>> revenueSummary({int? year}) async {
    try {
      final res = await _dio.get('/revenue/summary', queryParameters: {'year': ?year});
      final raw = ApiClient.unwrap(res);
      // The API returns one row per month ({month, label, actual, target});
      // the screen reads parallel lists, so reshape here. (Accepting only a
      // Map used to drop every response and leave the chart empty.)
      if (raw is List) {
        final rows = raw.whereType<Map<String, dynamic>>().toList();
        final shaped = <String, dynamic>{
          'months': [for (final r in rows) (r['label'] ?? r['month'] ?? '').toString()],
          'actual': [for (final r in rows) (r['actual'] as num?) ?? 0],
          'target': [for (final r in rows) (r['target'] as num?) ?? 0],
        };
        if (year == null || year == DateTime.now().year) cachedRevenueSummary = shaped;
        return shaped;
      }
      if (raw is Map<String, dynamic>) { cachedRevenueSummary = raw; return raw; }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Returns a signed, no-login-required URL to the invoice PDF — valid 7 days.
  /// Used for external sharing (WhatsApp etc.), not for in-app downloads.
  Future<String> shareLink(int id) async {
    final res = await _dio.post('/invoices/$id/share-link');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    return data['share_url'] as String;
  }

  /// All sales as an Excel ('xlsx') or PDF ('pdf') file — exactly [ids],
  /// in that order (the rows on screen).
  Future<List<int>> exportBytes(String format, List<int> ids, {String? saleStatus}) async {
    final res = await _dio.post<List<int>>('/invoices/export',
        data: {'format': format, 'ids': ids, 'period': 'all', 'sale_status': ?saleStatus},
        // A year of sales as PDF takes the server ~10-20 s to lay out.
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)));
    return res.data!;
  }

  Future<List<int>> pdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/invoices/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<List<Map<String, dynamic>>> revenueByHospital({Period? period}) async {
    try {
      final res = await _dio.get('/revenue/by-hospital', queryParameters: {
        'date_from': ?period?.fromIso,
        'date_to': ?period?.toIso,
      });
      final (data, _) = ApiClient.unwrapList(res);
      final list = data.whereType<Map<String, dynamic>>().toList();
      cachedRevenueByHospital = list;
      return list;
    } catch (_) {
      return [];
    }
  }
}
