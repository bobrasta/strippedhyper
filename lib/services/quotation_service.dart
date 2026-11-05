import 'package:dio/dio.dart';
import '../models/quotation.dart';
import 'api_client.dart';
import '../widgets/common/period_filter.dart';

class QuotationService {
  QuotationService._();
  static final instance = QuotationService._();
  final _dio = ApiClient.instance.dio;

  // Stale-while-revalidate screen cache — see MachineService for the full
  // reasoning. cachedDefaultList only covers the unfiltered query.
  static List<Quotation>? cachedDefaultList;
  static final Map<int, Quotation> cachedById = {};

  Future<List<Quotation>> list({String? status, String? search, Period? period}) async {
    final data = await ApiClient.getAllPages(_dio, '/quotations', query: {
      ...?period?.query,
      'status': ?status,
      'search': ?search,
    });
    final quotations = data.map((j) => Quotation.fromJson(j as Map<String, dynamic>)).toList();
    if (status == null && search == null && (period?.isDefault ?? false)) {
      cachedDefaultList = quotations;
    }
    return quotations;
  }

  Future<Quotation> get(int id) async {
    final res = await _dio.get('/quotations/$id');
    final quotation = Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
    cachedById[quotation.id] = quotation;
    return quotation;
  }

  Future<Quotation> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/quotations', data: data);
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Quotation> update(int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/quotations/$id', data: data);
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/quotations/$id');

  Future<Quotation> send(int id) async {
    final res = await _dio.post('/quotations/$id/send');
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Quotation> accept(int id) async {
    final res = await _dio.post('/quotations/$id/accept');
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Quotation> reject(int id) async {
    final res = await _dio.post('/quotations/$id/reject');
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Quotation> approve(int id) async {
    final res = await _dio.post('/quotations/$id/approve');
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Quotation> rejectApproval(int id, {String? reason}) async {
    final res = await _dio.post('/quotations/$id/reject-approval', data: {
      'rejection_reason': ?reason,
    });
    return Quotation.fromJson(ApiClient.unwrap(res) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> convert(int id, {required int locationId, String? expectedDeliveryDate, String? notes}) async {
    final res = await _dio.post('/quotations/$id/convert', data: {
      'location_id':            locationId,
      'expected_delivery_date': ?expectedDeliveryDate,
      'notes':                  ?notes,
    });
    return ApiClient.unwrap(res) as Map<String, dynamic>;
  }

  /// Returns a signed, no-login-required URL to the quotation PDF — valid 7 days.
  /// Used for external sharing (WhatsApp etc.), not for in-app downloads.
  Future<String> shareLink(int id) async {
    final res = await _dio.post('/quotations/$id/share-link');
    final data = ApiClient.unwrap(res) as Map<String, dynamic>;
    return data['share_url'] as String;
  }

  Future<List<int>> pdfBytes(int id) async {
    final res = await _dio.get<List<int>>('/quotations/$id/pdf', options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }
}
